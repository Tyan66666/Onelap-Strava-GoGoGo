import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/onelap_activity.dart';
import '../models/sync_summary.dart';
import '../models/sync_record.dart';
import 'concurrency_pool.dart';
import 'dedupe_service.dart';
import 'fit_coordinate_rewrite_service.dart';
import 'onelap_client.dart';
import 'strava_client.dart';
import 'state_store.dart';
import 'xingzhe_client.dart';

class _PlatformUploadResult {
  final List<PlatformSyncResult> platformResults;
  final int uploaded;
  final int failed;
  final int success;
  final int deduped;
  final List<FailedActivitySummary> failures;
  final List<String> failureReasons;

  const _PlatformUploadResult({
    this.platformResults = const [],
    this.uploaded = 0,
    this.failed = 0,
    this.success = 0,
    this.deduped = 0,
    this.failures = const [],
    this.failureReasons = const [],
  });
}

class _DownloadResult {
  final OneLapActivity item;
  final File file;
  final FitSessionMeta meta;
  final Object? error;

  _DownloadResult({
    required this.item,
    File? file,
    this.meta = const FitSessionMeta(),
    this.error,
  }) : file = file ?? File('');
}

class SyncEngine {
  final OneLapClient oneLapClient;
  final StravaClient? stravaClient;
  final XingzheClient? xingzheClient;
  final StateStore stateStore;
  final bool gcjCorrectionEnabled;
  final FitCoordinateRewriteService? rewriteService;
  final bool uploadToStrava;
  final bool uploadToXingzhe;
  final int downloadConcurrency;

  SyncEngine({
    required this.oneLapClient,
    required this.stravaClient,
    this.xingzheClient,
    required this.stateStore,
    this.gcjCorrectionEnabled = false,
    this.rewriteService,
    this.uploadToStrava = true,
    this.uploadToXingzhe = false,
    this.downloadConcurrency = 2,
  });

  Future<SyncSummary> runOnce({
    DateTime? sinceDate,
    int lookbackDays = 3,
  }) async {
    final since =
        sinceDate ?? DateTime.now().subtract(Duration(days: lookbackDays));
    final cacheDir = await getApplicationCacheDirectory();
    final downloadDir = Directory('${cacheDir.path}/fit_downloads');
    if (!downloadDir.existsSync()) downloadDir.createSync(recursive: true);

    final List<OneLapActivity> activities;
    try {
      activities = await oneLapClient.listFitActivities(since: since);
    } on OnelapRiskControlError {
      return const SyncSummary(
        fetched: 0,
        deduped: 0,
        success: 0,
        failed: 0,
        abortedReason: 'risk-control',
      );
    }

    int deduped = 0, success = 0, failed = 0;
    final List<String> failureReasons = [];
    final List<SyncRecord> syncRecords = [];

    // === 按平台统计 ===
    int xingzheSuccess = 0, xingzheFailed = 0, xingzheDeduped = 0;
    int stravaSuccess = 0, stravaFailed = 0, stravaDeduped = 0;
    final List<FailedActivitySummary> xingzheFailures = [];
    final List<FailedActivitySummary> stravaFailures = [];

    // Phase 1: Download all FIT files concurrently
    final pool = ConcurrencyPool<_DownloadResult>(
      maxConcurrent: downloadConcurrency,
    );
    final downloadTasks = activities
        .map(
          (item) => () async {
            try {
              final file = await oneLapClient.downloadFit(
                item.fitUrl,
                item.sourceFilename,
                downloadDir,
                activity: item,
              );
              final meta = await parseFitSessionMeta(file);
              return _DownloadResult(item: item, file: file, meta: meta);
            } catch (e) {
              return _DownloadResult(item: item, error: e);
            }
          },
        )
        .toList();
    final downloadResults = await pool.runAll(downloadTasks);

    // Phase 2: Process each downloaded activity sequentially
    for (final dlResult in downloadResults) {
      if (dlResult is! _DownloadResult) continue;
      final item = dlResult.item;

      if (dlResult.error != null) {
        final e = dlResult.error!;
        failed++;
        if (e is DioException) {
          final statusCode = e.response?.statusCode;
          final msg = e.message?.trim() ?? '';
          failureReasons.add(
            '下载失败 (${item.sourceFilename}): ${[if (statusCode != null) 'HTTP $statusCode', if (msg.isNotEmpty) msg].join(' | ')}',
          );
          syncRecords.add(
            _failedRecord(
              '',
              item,
              const FitSessionMeta(),
              'download',
              '下载失败: $msg',
            ),
          );
        } else {
          failureReasons.add('下载失败 (${item.sourceFilename}): $e');
          syncRecords.add(
            _failedRecord(
              '',
              item,
              const FitSessionMeta(),
              'download',
              '下载失败: $e',
            ),
          );
        }
        continue;
      }

      String? currentFingerprint;
      final sessionMeta = dlResult.meta;
      final fitFile = dlResult.file;

      // ---- 2. 生成 dedupeKey（startTime + distance），检查是否命中 ----
      final distM = sessionMeta.distanceM;
      final dedupeKey =
          '${item.startTime}_${distM != null ? distM.round() : 'na'}_${item.timeSeconds ?? 'na'}';
      final alreadyDeduped = await stateStore.isDedupeKey(dedupeKey);

      if (alreadyDeduped) {
        // 该活动已完整同步过（dedupeKey 命中），跳过下载，用存储指纹判断 per-platform
        final storedFp = await stateStore.getDedupeKeyFingerprint(dedupeKey);
        currentFingerprint = storedFp;

        if (storedFp != null) {
          bool skipStrava = false;
          bool skipXingzhe = false;
          final List<PlatformSyncResult> preSkipped = [];

          if (uploadToStrava) {
            final already = await stateStore.isAlreadyUploaded(
              storedFp,
              'strava',
            );
            if (already) {
              final remoteId = await stateStore.getRemoteActivityId(
                storedFp,
                'strava',
              );
              bool verified = true;
              if (remoteId != null && stravaClient != null) {
                verified = await stravaClient!.activityExists(remoteId);
              } else if (remoteId == null) {
                verified = false;
              }
              if (verified) {
                skipStrava = true;
                preSkipped.add(
                  PlatformSyncResult(
                    platform: SyncPlatform.strava,
                    status: SyncStatus.deduped,
                    syncedAt: DateTime.now().toIso8601String(),
                  ),
                );
              } else {
                await stateStore.clearPlatformStatus(storedFp, 'strava');
              }
            }
          }
          if (uploadToXingzhe) {
            final already = await stateStore.isAlreadyUploaded(
              storedFp,
              'xingzhe',
            );
            if (already) {
              skipXingzhe = true;
              preSkipped.add(
                PlatformSyncResult(
                  platform: SyncPlatform.xingzhe,
                  status: SyncStatus.deduped,
                  syncedAt: DateTime.now().toIso8601String(),
                ),
              );
            }
          }

          if ((!uploadToStrava || skipStrava) &&
              (!uploadToXingzhe || skipXingzhe)) {
            // 两个平台都已在之前同步完，本次完全跳过，不计入任何计数
            deduped++;
            syncRecords.add(
              SyncRecord(
                fingerprint: storedFp,
                sourceFilename: item.sourceFilename,
                startTime: item.startTime,
                syncedAt: DateTime.now(),
                distanceM: sessionMeta.distanceM,
                ascentM: sessionMeta.ascentM,
                sport: sessionMeta.sport,
                uploadedToStrava: uploadToStrava,
                uploadedToXingzhe: uploadToXingzhe,
                platformResults: preSkipped,
              ),
            );
            continue;
          }
        }
        // 有平台未完成，继续正常上传流程（dedupeKey 命中但部分平台之前失败）
      }

      // ---- 3. 计算指纹（dedupeKey 未命中时执行；dedupeKey 命中但部分平台未完成时也执行） ----
      if (currentFingerprint == null) {
        currentFingerprint = await _makeFingerprint(
          fitFile,
          item.startTime,
          item.recordKey,
        );
        if (currentFingerprint == null) {
          failed++;
          failureReasons.add('无法生成指纹 (${item.sourceFilename})');
          syncRecords.add(
            _failedRecord('', item, sessionMeta, 'fingerprint', '无法生成指纹'),
          );
          continue;
        }

        // ---- 4. 按平台指纹检查：是否已成功上传过？ ----
        bool skipStrava = false;
        bool skipXingzhe = false;
        final List<PlatformSyncResult> preSkipped = [];

        if (uploadToStrava) {
          final already = await stateStore.isAlreadyUploaded(
            currentFingerprint,
            'strava',
          );
          if (already) {
            final remoteId = await stateStore.getRemoteActivityId(
              currentFingerprint,
              'strava',
            );
            bool verified = true;
            if (remoteId != null && stravaClient != null) {
              verified = await stravaClient!.activityExists(remoteId);
            } else if (remoteId == null) {
              verified = false;
            }
            if (verified) {
              skipStrava = true;
              preSkipped.add(
                PlatformSyncResult(
                  platform: SyncPlatform.strava,
                  status: SyncStatus.deduped,
                  syncedAt: DateTime.now().toIso8601String(),
                ),
              );
            } else {
              await stateStore.clearPlatformStatus(
                currentFingerprint,
                'strava',
              );
            }
          }
        }
        if (uploadToXingzhe) {
          final already = await stateStore.isAlreadyUploaded(
            currentFingerprint,
            'xingzhe',
          );
          if (already) {
            skipXingzhe = true;
            preSkipped.add(
              PlatformSyncResult(
                platform: SyncPlatform.xingzhe,
                status: SyncStatus.deduped,
                syncedAt: DateTime.now().toIso8601String(),
              ),
            );
          }
        }

        // 两个平台都已在之前同步完
        if ((!uploadToStrava || skipStrava) &&
            (!uploadToXingzhe || skipXingzhe)) {
          deduped++;
          syncRecords.add(
            SyncRecord(
              fingerprint: currentFingerprint,
              sourceFilename: item.sourceFilename,
              startTime: item.startTime,
              syncedAt: DateTime.now(),
              distanceM: sessionMeta.distanceM,
              ascentM: sessionMeta.ascentM,
              sport: sessionMeta.sport,
              uploadedToStrava: uploadToStrava,
              uploadedToXingzhe: uploadToXingzhe,
              platformResults: preSkipped,
            ),
          );
          continue;
        }
      }

      // ---- 5. 坐标转换 ----
      File uploadFile = fitFile;
      bool rewriteFailed = false;
      String? rewriteError;
      if (gcjCorrectionEnabled) {
        try {
          final svc = rewriteService ?? FitCoordinateRewriteService();
          uploadFile = await svc.rewrite(
            fitFile,
            options: RewriteOptions(
              startTime: item.startTime,
              sourceFilename: item.sourceFilename,
            ),
          );
        } catch (e) {
          rewriteFailed = true;
          rewriteError = '$e';
        }
      }

      final List<PlatformSyncResult> platformResults = [];
      int platformsUploaded = 0;
      int platformsFailed = 0;
      final now = DateTime.now().toIso8601String();

      // ---- upload to Strava + Xingzhe in parallel ----
      final List<_PlatformUploadResult> stravaResults = [];
      final List<_PlatformUploadResult> xingzheResults = [];

      final List<Future<void>> uploadFutures = [];

      if (uploadToStrava && stravaClient != null) {
        uploadFutures.add(
          _uploadToStrava(
            fingerprint: currentFingerprint,
            sourceFilename: item.sourceFilename,
            startTime: item.startTime,
            sessionMeta: sessionMeta,
            uploadFile: uploadFile,
            rewriteFailed: rewriteFailed,
            rewriteError: rewriteError,
            now: now,
          ).then((r) => stravaResults.add(r)),
        );
      }

      if (uploadToXingzhe && xingzheClient != null) {
        uploadFutures.add(
          _uploadToXingzhe(
            fingerprint: currentFingerprint,
            sourceFilename: item.sourceFilename,
            startTime: item.startTime,
            sessionMeta: sessionMeta,
            uploadFile: uploadFile,
            rewriteFailed: rewriteFailed,
            rewriteError: rewriteError,
            now: now,
          ).then((r) => xingzheResults.add(r)),
        );
      }

      // Run all platform uploads in parallel.
      // Each helper catches all exceptions internally, so Future.wait
      // never sees a rejected future — this is critical: if one helper
      // let an exception escape, Future.wait would cancel the other.
      await Future.wait(uploadFutures);

      // Aggregate Strava results
      for (final r in stravaResults) {
        platformResults.addAll(r.platformResults);
        platformsUploaded += r.uploaded;
        platformsFailed += r.failed;
        stravaSuccess += r.success;
        stravaFailed += r.failed;
        stravaDeduped += r.deduped;
        stravaFailures.addAll(r.failures);
        failureReasons.addAll(r.failureReasons);
      }

      // Aggregate Xingzhe results
      for (final r in xingzheResults) {
        platformResults.addAll(r.platformResults);
        platformsUploaded += r.uploaded;
        platformsFailed += r.failed;
        xingzheSuccess += r.success;
        xingzheFailed += r.failed;
        xingzheDeduped += r.deduped;
        xingzheFailures.addAll(r.failures);
        failureReasons.addAll(r.failureReasons);
      }

      // ---- 6. 更新计数 ----
      if (platformsUploaded > 0) {
        success++;
        // 成功后保存 dedupeKey（稳定 key，兜底后续指纹变化情况）
        await stateStore.markDedupeKey(dedupeKey, currentFingerprint);
      }
      if (platformsFailed > 0 && platformsUploaded == 0) {
        failed++;
      }

      // ---- 7. 保存记录 ----
      syncRecords.add(
        SyncRecord(
          fingerprint: currentFingerprint,
          sourceFilename: item.sourceFilename,
          startTime: item.startTime,
          syncedAt: DateTime.now(),
          distanceM: sessionMeta.distanceM,
          ascentM: sessionMeta.ascentM,
          sport: sessionMeta.sport,
          uploadedToStrava: uploadToStrava,
          uploadedToXingzhe: uploadToXingzhe,
          platformResults: platformResults,
        ),
      );

      // Cleanup rewritten temp file
      if (uploadFile.path != fitFile.path) {
        try {
          await uploadFile.delete();
        } catch (_) {}
        try {
          await uploadFile.parent.delete();
        } catch (_) {}
      }
    }

    if (syncRecords.isNotEmpty) {
      await stateStore.saveSyncRecords(syncRecords);
    }

    try {
      if (downloadDir.existsSync()) {
        await downloadDir.delete(recursive: true);
      }
    } catch (_) {}

    return SyncSummary(
      fetched: activities.length,
      deduped: deduped,
      success: success,
      failed: failed,
      failureReasons: failureReasons,
      xingzheSuccess: xingzheSuccess,
      xingzheFailed: xingzheFailed,
      xingzheDeduped: xingzheDeduped,
      xingzheFailures: xingzheFailures,
      stravaSuccess: stravaSuccess,
      stravaFailed: stravaFailed,
      stravaDeduped: stravaDeduped,
      stravaFailures: stravaFailures,
      syncedAt: DateTime.now(),
    );
  }

  Future<String?> _makeFingerprint(
    File fitFile,
    String startTime,
    String recordKey,
  ) async {
    try {
      return makeFingerprint(fitFile, startTime, recordKey);
    } catch (_) {
      return null;
    }
  }

  bool _isIdempotentSuccess(dynamic e) {
    final s = '$e'.toLowerCase();
    if (s.contains('9006') ||
        s.contains('文件已上传') ||
        s.contains('already') ||
        s.contains('duplicate') ||
        s.contains('dedupe') ||
        s.contains('already exists') ||
        s.contains('duplicate of')) {
      return true;
    }
    return false;
  }

  SyncRecord _failedRecord(
    String fp,
    OneLapActivity item,
    FitSessionMeta sm,
    String phase,
    String err,
  ) {
    final now = DateTime.now().toIso8601String();
    return SyncRecord(
      fingerprint: fp,
      sourceFilename: item.sourceFilename,
      startTime: item.startTime,
      syncedAt: DateTime.now(),
      distanceM: sm.distanceM,
      ascentM: sm.ascentM,
      sport: sm.sport,
      uploadedToStrava: uploadToStrava,
      uploadedToXingzhe: uploadToXingzhe,
      platformResults: [
        if (uploadToStrava)
          PlatformSyncResult(
            platform: SyncPlatform.strava,
            status: SyncStatus.failed,
            errorMessage: '[$phase] $err',
            syncedAt: now,
          ),
        if (uploadToXingzhe)
          PlatformSyncResult(
            platform: SyncPlatform.xingzhe,
            status: SyncStatus.failed,
            errorMessage: '[$phase] $err',
            syncedAt: now,
          ),
      ],
    );
  }

  // === Parallel upload helpers ===
  // Each helper catches ALL exceptions internally — never let an exception
  // escape, because Future.wait in the caller would cancel other uploads.

  FailedActivitySummary _failSummary(
    String fingerprint,
    String startTime,
    FitSessionMeta sm,
    String err,
  ) {
    String fmtDate(String s) => s.length >= 10 ? s.substring(0, 10) : s;
    String fmtDist(double? m) =>
        m == null ? '--' : '${(m / 1000).toStringAsFixed(1)}km';
    String fmtAscent(int? m) => m == null ? '--' : '${m}m';
    return FailedActivitySummary(
      fingerprint: fingerprint,
      date: fmtDate(startTime),
      distance: fmtDist(sm.distanceM),
      ascent: fmtAscent(sm.ascentM),
      error: err,
    );
  }

  Future<_PlatformUploadResult> _uploadToStrava({
    required String fingerprint,
    required String sourceFilename,
    required String startTime,
    required FitSessionMeta sessionMeta,
    required File uploadFile,
    required bool rewriteFailed,
    required String? rewriteError,
    required String now,
  }) async {
    final platformResults = <PlatformSyncResult>[];
    int uploaded = 0, failed = 0;
    int sSuccess = 0, sDeduped = 0;
    final List<FailedActivitySummary> sFailures = [];
    final List<String> sFailureReasons = [];

    final alreadySynced = await stateStore.isAlreadyUploaded(
      fingerprint,
      'strava',
    );
    bool shouldSkip = false;

    if (alreadySynced) {
      final remoteId = await stateStore.getRemoteActivityId(
        fingerprint,
        'strava',
      );
      bool verified = true;
      if (remoteId != null && stravaClient != null) {
        verified = await stravaClient!.activityExists(remoteId);
      } else if (remoteId == null) {
        verified = false;
      }
      if (verified) {
        shouldSkip = true;
      } else {
        await stateStore.clearPlatformStatus(fingerprint, 'strava');
      }
    }

    if (shouldSkip) {
      platformResults.add(
        PlatformSyncResult(
          platform: SyncPlatform.strava,
          status: SyncStatus.deduped,
          syncedAt: now,
        ),
      );
      sDeduped++;
    } else if (!gcjCorrectionEnabled || !rewriteFailed) {
      try {
        final uploadId = await stravaClient!.uploadFit(uploadFile);
        final result = await stravaClient!.pollUpload(uploadId);
        final activityId = result['activity_id'];
        final error = result['error'];

        if (activityId == null && error != null) {
          final errorStr = '$error'.toLowerCase();
          if (errorStr.contains('duplicate of')) {
            // Safe to call concurrently — Dart is single-threaded, so both
            // platform helpers mutate the same cached Map reference.
            await stateStore.markPlatformSynced(fingerprint, 'strava', null);
            platformResults.add(
              PlatformSyncResult(
                platform: SyncPlatform.strava,
                status: SyncStatus.deduped,
                syncedAt: now,
              ),
            );
            sDeduped++;
          } else {
            platformResults.add(
              PlatformSyncResult(
                platform: SyncPlatform.strava,
                status: SyncStatus.failed,
                errorMessage: '$error',
                syncedAt: now,
              ),
            );
            failed++;

            sFailures.add(
              _failSummary(fingerprint, startTime, sessionMeta, error),
            );
            sFailureReasons.add('Strava 上传失败 ($sourceFilename): $error');
          }
        } else {
          final aid = (activityId as num).toInt();
          await stateStore.markPlatformSynced(fingerprint, 'strava', aid);
          platformResults.add(
            PlatformSyncResult(
              platform: SyncPlatform.strava,
              status: SyncStatus.success,
              remoteActivityId: aid,
              syncedAt: now,
            ),
          );
          uploaded++;
          sSuccess++;
        }
      } catch (e) {
        if (_isIdempotentSuccess(e)) {
          await stateStore.markPlatformSynced(fingerprint, 'strava', null);
          platformResults.add(
            PlatformSyncResult(
              platform: SyncPlatform.strava,
              status: SyncStatus.success,
              syncedAt: now,
            ),
          );
          uploaded++;
          sSuccess++;
        } else {
          platformResults.add(
            PlatformSyncResult(
              platform: SyncPlatform.strava,
              status: SyncStatus.failed,
              errorMessage: '$e',
              syncedAt: now,
            ),
          );
          failed++;
          sFailures.add(
            _failSummary(fingerprint, startTime, sessionMeta, '$e'),
          );
          sFailureReasons.add('Strava 上传失败 ($sourceFilename): $e');
        }
      }
    } else {
      platformResults.add(
        PlatformSyncResult(
          platform: SyncPlatform.strava,
          status: SyncStatus.failed,
          errorMessage: '坐标转换失败: $rewriteError',
          syncedAt: now,
        ),
      );
      failed++;
      sFailures.add(
        _failSummary(fingerprint, startTime, sessionMeta, '坐标转换失败'),
      );
    }

    return _PlatformUploadResult(
      platformResults: platformResults,
      uploaded: uploaded,
      failed: failed,
      success: sSuccess,
      deduped: sDeduped,
      failures: sFailures,
      failureReasons: sFailureReasons,
    );
  }

  Future<_PlatformUploadResult> _uploadToXingzhe({
    required String fingerprint,
    required String sourceFilename,
    required String startTime,
    required FitSessionMeta sessionMeta,
    required File uploadFile,
    required bool rewriteFailed,
    required String? rewriteError,
    required String now,
  }) async {
    final platformResults = <PlatformSyncResult>[];
    int uploaded = 0, failed = 0;
    int xSuccess = 0, xDeduped = 0;
    final List<FailedActivitySummary> xFailures = [];
    final List<String> xFailureReasons = [];

    final skip = await stateStore.isAlreadyUploaded(fingerprint, 'xingzhe');
    if (skip) {
      platformResults.add(
        PlatformSyncResult(
          platform: SyncPlatform.xingzhe,
          status: SyncStatus.deduped,
          syncedAt: now,
        ),
      );
      xDeduped++;
    } else if (!gcjCorrectionEnabled || !rewriteFailed) {
      try {
        final uploadId = await xingzheClient!.uploadFit(uploadFile);
        final result = await xingzheClient!.pollUpload(uploadId);
        final activityId = result['activity_id'];
        final error = result['error'];

        if (activityId == null || (activityId is num && activityId == 0)) {
          final isIdempotent = _isIdempotentSuccess(error ?? '');
          if (error != null && !isIdempotent) {
            platformResults.add(
              PlatformSyncResult(
                platform: SyncPlatform.xingzhe,
                status: SyncStatus.failed,
                errorMessage: '$error',
                syncedAt: now,
              ),
            );
            failed++;
            xFailures.add(
              _failSummary(fingerprint, startTime, sessionMeta, error),
            );
            xFailureReasons.add('行者 上传失败 ($sourceFilename): $error');
          } else {
            // Safe to call concurrently — Dart is single-threaded, so both
            // platform helpers mutate the same cached Map reference.
            await stateStore.markPlatformSynced(fingerprint, 'xingzhe', null);
            platformResults.add(
              PlatformSyncResult(
                platform: SyncPlatform.xingzhe,
                status: SyncStatus.success,
                syncedAt: now,
              ),
            );
            uploaded++;
            xSuccess++;
          }
        } else {
          final aid = activityId is int
              ? activityId
              : int.tryParse('$activityId') ?? 0;
          await stateStore.markPlatformSynced(fingerprint, 'xingzhe', aid);
          platformResults.add(
            PlatformSyncResult(
              platform: SyncPlatform.xingzhe,
              status: SyncStatus.success,
              remoteActivityId: aid,
              syncedAt: now,
            ),
          );
          uploaded++;
          xSuccess++;
        }
      } catch (e) {
        if (_isIdempotentSuccess(e)) {
          await stateStore.markPlatformSynced(fingerprint, 'xingzhe', null);
          platformResults.add(
            PlatformSyncResult(
              platform: SyncPlatform.xingzhe,
              status: SyncStatus.success,
              syncedAt: now,
            ),
          );
          uploaded++;
          xSuccess++;
        } else {
          platformResults.add(
            PlatformSyncResult(
              platform: SyncPlatform.xingzhe,
              status: SyncStatus.failed,
              errorMessage: '$e',
              syncedAt: now,
            ),
          );
          failed++;
          xFailures.add(
            _failSummary(fingerprint, startTime, sessionMeta, '$e'),
          );
          xFailureReasons.add('行者 上传失败 ($sourceFilename): $e');
        }
      }
    } else {
      platformResults.add(
        PlatformSyncResult(
          platform: SyncPlatform.xingzhe,
          status: SyncStatus.failed,
          errorMessage: '坐标转换失败: $rewriteError',
          syncedAt: now,
        ),
      );
      failed++;
      xFailures.add(
        _failSummary(fingerprint, startTime, sessionMeta, '坐标转换失败'),
      );
    }

    return _PlatformUploadResult(
      platformResults: platformResults,
      uploaded: uploaded,
      failed: failed,
      success: xSuccess,
      deduped: xDeduped,
      failures: xFailures,
      failureReasons: xFailureReasons,
    );
  }
}
