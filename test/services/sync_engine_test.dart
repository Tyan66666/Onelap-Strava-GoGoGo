import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/models/onelap_activity.dart';
import 'package:onelap_strava_sync/models/sync_record.dart';
import 'package:onelap_strava_sync/models/sync_result_banner.dart';
import 'package:onelap_strava_sync/models/sync_summary.dart';
import 'package:onelap_strava_sync/services/fit_coordinate_rewrite_service.dart';
import 'package:onelap_strava_sync/services/onelap_client.dart';
import 'package:onelap_strava_sync/services/state_store.dart';
import 'package:onelap_strava_sync/services/strava_client.dart';
import 'package:onelap_strava_sync/services/sync_engine.dart';
import 'package:onelap_strava_sync/services/xingzhe_client.dart';

class _FakeOneLapClient extends OneLapClient {
  _FakeOneLapClient({required this.activities, required this.downloadedFile})
    : super(baseUrl: 'https://example.com', username: 'user', password: 'pass');

  final List<OneLapActivity> activities;
  final File downloadedFile;

  @override
  Future<List<OneLapActivity>> listFitActivities({
    required DateTime since,
    int limit = 50,
  }) async {
    return activities;
  }

  @override
  Future<File> downloadFit(
    String url,
    String fileKey,
    Directory outDir, {
    OneLapActivity? activity,
  }) async {
    return downloadedFile;
  }
}

class _FakeStravaClient extends StravaClient {
  _FakeStravaClient()
    : super(
        clientId: 'client-id',
        clientSecret: 'client-secret',
        refreshToken: 'refresh-token',
        accessToken: 'access-token',
        expiresAt: 4102444800,
      );

  File? uploadedFile;
  int uploadCalls = 0;

  @override
  Future<int> uploadFit(File file, {int retries = 3}) async {
    uploadedFile = file;
    uploadCalls++;
    return 42;
  }

  @override
  Future<Map<String, dynamic>> pollUpload(
    int uploadId, {
    int maxAttempts = 10,
  }) {
    return Future<Map<String, dynamic>>.value(<String, dynamic>{
      'activity_id': 99,
    });
  }
}

class _FakeStateStore extends StateStore {
  String? checkedFingerprint;
  String? markedFingerprint;
  int? markedActivityId;
  bool synced = false;
  final Map<String, bool> uploadedPlatforms = <String, bool>{};

  @override
  Future<bool> isAlreadyUploaded(String fingerprint, String platform) async {
    checkedFingerprint = fingerprint;
    return uploadedPlatforms[platform] ?? synced;
  }

  @override
  Future<bool> isDedupeKey(String dedupeKey) async => false;

  @override
  Future<String?> getDedupeKeyFingerprint(String dedupeKey) async => null;

  @override
  Future<void> markPlatformSynced(
    String fingerprint,
    String platform,
    int? remoteActivityId,
  ) async {
    markedFingerprint = fingerprint;
    markedActivityId = remoteActivityId;
  }

  @override
  Future<void> markDedupeKey(String dedupeKey, String fingerprint) async {}

  @override
  Future<void> saveSyncRecords(List<SyncRecord> records) async {}
}

class _FakeXingzheClient extends XingzheClient {
  _FakeXingzheClient()
    : super(username: 'xingzhe-user', password: 'xingzhe-pass');

  @override
  Future<int> uploadFit(File fitFile, {int retries = 3}) async {
    return 7;
  }

  @override
  Future<Map<String, dynamic>> pollUpload(
    int uploadId, {
    int maxAttempts = 10,
  }) async {
    return <String, dynamic>{'activity_id': 0, 'error': 'bad password'};
  }
}

class _FakeFitCoordinateRewriteService extends FitCoordinateRewriteService {
  _FakeFitCoordinateRewriteService({this.rewrittenFile, this.error});

  final File? rewrittenFile;
  final Exception? error;
  File? receivedFile;

  @override
  Future<File> rewrite(File inputFile, {RewriteOptions? options}) async {
    receivedFile = inputFile;
    if (error != null) {
      throw error!;
    }
    return rewrittenFile!;
  }
}

OneLapActivity _activity({String sourceFilename = 'activity.fit'}) {
  return OneLapActivity(
    activityId: 'activity-id',
    startTime: '2026-04-10T08:00:00Z',
    fitUrl: 'https://example.com/activity.fit',
    recordKey: 'record-key',
    sourceFilename: sourceFilename,
  );
}

Future<String> _expectedFingerprint(File file) async {
  final Digest hash = sha256.convert(await file.readAsBytes());
  return 'record-key|$hash|2026-04-10T08:00:00Z';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel pathProviderChannel = MethodChannel(
    'plugins.flutter.io/path_provider',
  );
  late Directory cacheDirectory;

  setUpAll(() async {
    cacheDirectory = await Directory.systemTemp.createTemp(
      'sync-engine-cache-',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (
          MethodCall methodCall,
        ) async {
          if (methodCall.method == 'getApplicationCacheDirectory') {
            return cacheDirectory.path;
          }
          return null;
        });
  });

  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (await cacheDirectory.exists()) {
      await cacheDirectory.delete(recursive: true);
    }
  });

  group('SyncEngine.runOnce', () {
    test('original downloaded file is still used for fingerprinting', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'sync-engine-fingerprint-original-',
      );
      final File originalFile = File('${tempDir.path}/activity.fit');
      final File rewrittenFile = File('${tempDir.path}/rewritten.fit');
      await originalFile.writeAsBytes(<int>[1, 2, 3]);
      await rewrittenFile.writeAsBytes(<int>[4, 5, 6]);
      final String rewrittenFingerprint = await _expectedFingerprint(
        rewrittenFile,
      );

      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final _FakeStateStore stateStore = _FakeStateStore();
      final SyncEngine engine = SyncEngine(
        oneLapClient: _FakeOneLapClient(
          activities: <OneLapActivity>[_activity()],
          downloadedFile: originalFile,
        ),
        stravaClient: _FakeStravaClient(),
        stateStore: stateStore,
        gcjCorrectionEnabled: true,
        rewriteService: _FakeFitCoordinateRewriteService(
          rewrittenFile: rewrittenFile,
        ),
      );

      await engine.runOnce();

      expect(
        stateStore.checkedFingerprint,
        await _expectedFingerprint(originalFile),
      );
      expect(stateStore.checkedFingerprint, isNot(rewrittenFingerprint));
    });

    test('rewritten file is used for upload when rewrite is enabled', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'sync-engine-upload-rewritten-',
      );
      final File originalFile = File('${tempDir.path}/activity.fit');
      final File rewrittenFile = File('${tempDir.path}/rewritten.fit');
      await originalFile.writeAsBytes(<int>[1, 2, 3]);
      await rewrittenFile.writeAsBytes(<int>[4, 5, 6]);

      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final _FakeStravaClient stravaClient = _FakeStravaClient();
      final _FakeFitCoordinateRewriteService rewriteService =
          _FakeFitCoordinateRewriteService(rewrittenFile: rewrittenFile);
      final SyncEngine engine = SyncEngine(
        oneLapClient: _FakeOneLapClient(
          activities: <OneLapActivity>[_activity()],
          downloadedFile: originalFile,
        ),
        stravaClient: stravaClient,
        stateStore: _FakeStateStore(),
        gcjCorrectionEnabled: true,
        rewriteService: rewriteService,
      );

      await engine.runOnce();

      expect(rewriteService.receivedFile?.path, originalFile.path);
      expect(stravaClient.uploadedFile?.path, rewrittenFile.path);
    });

    test('cleans up the rewrite temp directory after upload attempt', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'sync-engine-rewrite-cleanup-',
      );
      final Directory rewrittenDir = Directory(
        '${tempDir.path}/rewritten-temp',
      );
      await rewrittenDir.create();
      final File originalFile = File('${tempDir.path}/activity.fit');
      final File rewrittenFile = File('${rewrittenDir.path}/rewritten.fit');
      await originalFile.writeAsBytes(<int>[1, 2, 3]);
      await rewrittenFile.writeAsBytes(<int>[4, 5, 6]);

      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final SyncEngine engine = SyncEngine(
        oneLapClient: _FakeOneLapClient(
          activities: <OneLapActivity>[_activity()],
          downloadedFile: originalFile,
        ),
        stravaClient: _FakeStravaClient(),
        stateStore: _FakeStateStore(),
        gcjCorrectionEnabled: true,
        rewriteService: _FakeFitCoordinateRewriteService(
          rewrittenFile: rewrittenFile,
        ),
      );

      await engine.runOnce();

      expect(await originalFile.exists(), isTrue);
      expect(await Directory(tempDir.path).exists(), isTrue);
      expect(await rewrittenFile.exists(), isFalse);
      expect(await rewrittenDir.exists(), isFalse);
    });

    test('rewrite errors are reported as localized failure messages', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'sync-engine-rewrite-error-',
      );
      final File originalFile = File('${tempDir.path}/activity.fit');
      await originalFile.writeAsBytes(<int>[1, 2, 3]);

      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final _FakeStravaClient stravaClient = _FakeStravaClient();
      final SyncEngine engine = SyncEngine(
        oneLapClient: _FakeOneLapClient(
          activities: <OneLapActivity>[_activity()],
          downloadedFile: originalFile,
        ),
        stravaClient: stravaClient,
        stateStore: _FakeStateStore(),
        gcjCorrectionEnabled: true,
        rewriteService: _FakeFitCoordinateRewriteService(
          error: Exception('bad coordinate'),
        ),
      );

      final summary = await engine.runOnce();

      expect(summary.failed, 1);
      expect(summary.success, 0);
      expect(summary.failureReasons, isEmpty);
      expect(summary.stravaFailed, 1);
      expect(summary.stravaFailures, hasLength(1));
      expect(summary.stravaFailures.single.error, '坐标转换失败');
      expect(stravaClient.uploadedFile, isNull);
    });

    test('tracks platform deduped counts separately from failures', () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'sync-engine-platform-deduped-',
      );
      final File originalFile = File('${tempDir.path}/activity.fit');
      await originalFile.writeAsBytes(<int>[1, 2, 3]);

      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final _FakeStateStore stateStore = _FakeStateStore()
        ..uploadedPlatforms['strava'] = true;
      final SyncEngine engine = SyncEngine(
        oneLapClient: _FakeOneLapClient(
          activities: <OneLapActivity>[_activity()],
          downloadedFile: originalFile,
        ),
        stravaClient: _FakeStravaClient(),
        xingzheClient: _FakeXingzheClient(),
        stateStore: stateStore,
        uploadToStrava: true,
        uploadToXingzhe: true,
      );

      final SyncSummary summary = await engine.runOnce();
      final SyncResultBanner banner = SyncResultBanner.fromSyncSummary(summary);

      expect(summary.success, 0);
      expect(summary.failed, 1);
      expect(summary.stravaSuccess, 0);
      expect(summary.stravaFailed, 0);
      expect(summary.stravaDeduped, 1);
      expect(summary.xingzheSuccess, 0);
      expect(summary.xingzheFailed, 1);
      expect(summary.xingzheDeduped, 0);
      expect(banner.stravaDeduped, 1);
      expect(banner.xingzheFailed, 1);
    });
  });
}
