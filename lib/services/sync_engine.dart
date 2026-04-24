import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/onelap_activity.dart';
import '../models/sync_summary.dart';
import '../models/sync_record.dart';
import 'dedupe_service.dart';
import 'fit_coordinate_rewrite_service.dart';
import 'onelap_client.dart';
import 'strava_client.dart';
import 'state_store.dart';
import 'xingzhe_client.dart';

class SyncEngine {
  final OneLapClient oneLapClient;
  final StravaClient? stravaClient;
  final XingzheClient? xingzheClient;
  final StateStore stateStore;
  final bool gcjCorrectionEnabled;
  final FitCoordinateRewriteService? rewriteService;
  final bool uploadToStrava;
  final bool uploadToXingzhe;

  SyncEngine({
    required this.oneLapClient,
    required this.stravaClient,
    this.xingzheClient,
    required this.stateStore,
    this.gcjCorrectionEnabled = false,
    this.rewriteService,
    this.uploadToStrava = true,
    this.uploadToXingzhe = false,
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

    String fmtDate(String startTime) =>
        startTime.length >= 10 ? startTime.substring(0, 10) : startTime;
    String fmtDist(double? m) =>
        m == null ? '--' : '${(m / 1000).toStringAsFixed(1)}km';
    String fmtAscent(int? m) => m == null ? '--' : '${m}m';

    FailedActivitySummary failSummary(
      String fp,
      String startTime,
      FitSessionMeta sm,
      String err,
    ) {
      return FailedActivitySummary(
        fingerprint: fp,
        date: fmtDate(startTime),
        distance: fmtDist(sm.distanceM),
        ascent: fmtAscent(sm.ascentM),
        error: err,
      );
    }

    for (final item in activities) {
      String? currentFingerprint;
      FitSessionMeta sessionMeta = const FitSessionMeta();
      File fitFile = File('');

      // ---- 1. download + parse session meta ----
      try {
        fitFile = await oneLapClient.downloadFit(
          item.fitUrl,
          item.sourceFilename,
          downloadDir,
          activity: item,
        );
        sessionMeta = await parseFitSessionMeta(fitFile);
      } on DioException catch (e) {
        failed++;
        final statusCode = e.response?.statusCode;
        final msg = e.message?.trim() ?? '';
        failureReasons.add(
          '下载失败 (${item.sourceFilename}): ${[if (statusCode != null) 'HTTP $statusCode', if (msg.isNotEmpty) msg].join(' | ')}',
        );
        syncRecords.add(
          _failedRecord('', item, sessionMeta, 'download', '下载失败: $msg'),
        );
        continue;
      } catch (e) {
        failed++;
        failureReasons.add('下载失败 (${item.sourceFilename}): $e');
        syncRecords.add(
          _failedRecord('', item, sessionMeta, 'download', '下载失败: $e'),
        );
        continue;
      }

      // ---- 2. 生成 dedupeKey（startTime + distance），检查是否命中 ----
      final distM = sessionMeta.distanceM;
      final dedupeKey =
          '${item.startTime}_${distM != null ? distM.round() : 'na'}';
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
              skipStrava = true;
              preSkipped.add(
                PlatformSyncResult(
                  platform: SyncPlatform.strava,
                  status: SyncStatus.deduped,
                  syncedAt: DateTime.now().toIso8601String(),
                ),
              );
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
            skipStrava = true;
            preSkipped.add(
              PlatformSyncResult(
                platform: SyncPlatform.strava,
                status: SyncStatus.deduped,
                syncedAt: DateTime.now().toIso8601String(),
              ),
            );
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

      // ---- upload to Strava ----
      if (uploadToStrava && stravaClient != null) {
        final skipStrava = await stateStore.isAlreadyUploaded(
          currentFingerprint,
          'strava',
        );
        if (skipStrava) {
          platformResults.add(
            PlatformSyncResult(
              platform: SyncPlatform.strava,
              status: SyncStatus.deduped,
              syncedAt: now,
            ),
          );
          stravaDeduped++;
        } else if (!gcjCorrectionEnabled || !rewriteFailed) {
          try {
            final uploadId = await stravaClient!.uploadFit(uploadFile);
            final result = await stravaClient!.pollUpload(uploadId);
            final activityId = result['activity_id'];
            final error = result['error'];

            if (activityId == null && error != null) {
              final errorStr = '$error'.toLowerCase();
              if (errorStr.contains('duplicate of')) {
                await stateStore.markPlatformSynced(
                  currentFingerprint,
                  'strava',
                  null,
                );
                platformResults.add(
                  PlatformSyncResult(
                    platform: SyncPlatform.strava,
                    status: SyncStatus.deduped,
                    syncedAt: now,
                  ),
                );
                stravaDeduped++;
              } else {
                platformResults.add(
                  PlatformSyncResult(
                    platform: SyncPlatform.strava,
                    status: SyncStatus.failed,
                    errorMessage: '$error',
                    syncedAt: now,
                  ),
                );
                platformsFailed++;
                stravaFailed++;
                stravaFailures.add(
                  failSummary(
                    currentFingerprint,
                    item.startTime,
                    sessionMeta,
                    error,
                  ),
                );
                failureReasons.add(
                  'Strava 上传失败 (${item.sourceFilename}): $error',
                );
              }
            } else {
              final aid = (activityId as num).toInt();
              await stateStore.markPlatformSynced(
                currentFingerprint,
                'strava',
                aid,
              );
              platformResults.add(
                PlatformSyncResult(
                  platform: SyncPlatform.strava,
                  status: SyncStatus.success,
                  remoteActivityId: aid,
                  syncedAt: now,
                ),
              );
              platformsUploaded++;
              stravaSuccess++;
            }
          } catch (e) {
            if (_isIdempotentSuccess(e)) {
              await stateStore.markPlatformSynced(
                currentFingerprint,
                'strava',
                null,
              );
              platformResults.add(
                PlatformSyncResult(
                  platform: SyncPlatform.strava,
                  status: SyncStatus.success,
                  syncedAt: now,
                ),
              );
              platformsUploaded++;
              stravaSuccess++;
            } else {
              platformResults.add(
                PlatformSyncResult(
                  platform: SyncPlatform.strava,
                  status: SyncStatus.failed,
                  errorMessage: '$e',
                  syncedAt: now,
                ),
              );
              platformsFailed++;
              stravaFailed++;
              stravaFailures.add(
                failSummary(
                  currentFingerprint,
                  item.startTime,
                  sessionMeta,
                  '$e',
                ),
              );
              failureReasons.add('Strava 上传失败 (${item.sourceFilename}): $e');
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
          platformsFailed++;
          stravaFailed++;
          stravaFailures.add(
            failSummary(
              currentFingerprint,
              item.startTime,
              sessionMeta,
              '坐标转换失败',
            ),
          );
        }
      }

      // ---- upload to Xingzhe ----
      if (uploadToXingzhe && xingzheClient != null) {
        final skipXingzhe = await stateStore.isAlreadyUploaded(
          currentFingerprint,
          'xingzhe',
        );
        if (skipXingzhe) {
          platformResults.add(
            PlatformSyncResult(
              platform: SyncPlatform.xingzhe,
              status: SyncStatus.deduped,
              syncedAt: now,
            ),
          );
          xingzheDeduped++;
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
                platformsFailed++;
                xingzheFailed++;
                xingzheFailures.add(
                  failSummary(
                    currentFingerprint,
                    item.startTime,
                    sessionMeta,
                    error ?? '',
                  ),
                );
                failureReasons.add('行者 上传失败 (${item.sourceFilename}): $error');
              } else {
                await stateStore.markPlatformSynced(
                  currentFingerprint,
                  'xingzhe',
                  null,
                );
                platformResults.add(
                  PlatformSyncResult(
                    platform: SyncPlatform.xingzhe,
                    status: SyncStatus.success,
                    syncedAt: now,
                  ),
                );
                platformsUploaded++;
                xingzheSuccess++;
              }
            } else {
              final aid = activityId is int
                  ? activityId
                  : int.tryParse('$activityId') ?? 0;
              await stateStore.markPlatformSynced(
                currentFingerprint,
                'xingzhe',
                aid,
              );
              platformResults.add(
                PlatformSyncResult(
                  platform: SyncPlatform.xingzhe,
                  status: SyncStatus.success,
                  remoteActivityId: aid,
                  syncedAt: now,
                ),
              );
              platformsUploaded++;
              xingzheSuccess++;
            }
          } catch (e) {
            if (_isIdempotentSuccess(e)) {
              await stateStore.markPlatformSynced(
                currentFingerprint,
                'xingzhe',
                null,
              );
              platformResults.add(
                PlatformSyncResult(
                  platform: SyncPlatform.xingzhe,
                  status: SyncStatus.success,
                  syncedAt: now,
                ),
              );
              platformsUploaded++;
              xingzheSuccess++;
            } else {
              platformResults.add(
                PlatformSyncResult(
                  platform: SyncPlatform.xingzhe,
                  status: SyncStatus.failed,
                  errorMessage: '$e',
                  syncedAt: now,
                ),
              );
              platformsFailed++;
              xingzheFailed++;
              xingzheFailures.add(
                failSummary(
                  currentFingerprint,
                  item.startTime,
                  sessionMeta,
                  '$e',
                ),
              );
              failureReasons.add('行者 上传失败 (${item.sourceFilename}): $e');
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
          platformsFailed++;
          xingzheFailed++;
          xingzheFailures.add(
            failSummary(
              currentFingerprint,
              item.startTime,
              sessionMeta,
              '坐标转换失败',
            ),
          );
        }
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
}
