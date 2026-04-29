import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/models/shared_fit_draft.dart';
import 'package:onelap_strava_sync/models/shared_fit_event.dart';
import 'package:onelap_strava_sync/screens/share_confirm_screen.dart';
import 'package:onelap_strava_sync/services/fit_upload_coordinator.dart';
import 'package:onelap_strava_sync/services/share_navigation_coordinator.dart';
import 'package:onelap_strava_sync/services/shared_fit_upload_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpScreen(
    WidgetTester tester, {
    required SharedFitEvent event,
    required SharedFitUploadService uploadService,
    ShareFlowUploadActivity? uploadActivity,
    Duration? successFeedbackDuration,
    VoidCallback? onOpenSettings,
    VoidCallback? onDismissToHome,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ShareConfirmScreen(
          event: event,
          uploadService: uploadService,
          uploadActivity: uploadActivity ?? ShareFlowUploadActivity(),
          successFeedbackDuration:
              successFeedbackDuration ?? const Duration(seconds: 1),
          onOpenSettings: onOpenSettings,
          onDismissToHome: onDismissToHome,
        ),
      ),
    );
  }

  Future<void> pumpScreenAndSettle(
    WidgetTester tester, {
    required SharedFitEvent event,
    required SharedFitUploadService uploadService,
    ShareFlowUploadActivity? uploadActivity,
    Duration? successFeedbackDuration,
    VoidCallback? onOpenSettings,
    VoidCallback? onDismissToHome,
  }) async {
    await pumpScreen(
      tester,
      event: event,
      uploadService: uploadService,
      uploadActivity: uploadActivity,
      successFeedbackDuration: successFeedbackDuration,
      onOpenSettings: onOpenSettings,
      onDismissToHome: onDismissToHome,
    );
    await tester.pump();
  }

  testWidgets(
    'does not show Strava wording before preflight target metadata loads',
    (WidgetTester tester) async {
      final Completer<FitUploadPlan> planCompleter = Completer<FitUploadPlan>();

      await pumpScreen(
        tester,
        event: const SharedFitEvent.draft(
          SharedFitDraft(
            localFilePath: '/tmp/ride.fit',
            displayName: 'ride.fit',
          ),
        ),
        uploadService: _FakeUploadService.withAsyncPlanAndResult(
          planFuture: planCompleter.future,
          result: const SharedFitUploadResult(
            status: SharedFitUploadStatus.success,
            message: 'FIT 文件已经上传到 Strava 和行者。',
          ),
        ),
      );

      expect(find.text('上传到 Strava'), findsNothing);
      expect(find.text('上传到行者'), findsNothing);
      expect(find.text('上传到 Strava 和行者'), findsNothing);
      expect(find.text('确认将这个 FIT 文件上传到 Strava。'), findsNothing);
      expect(find.text('确认将这个 FIT 文件上传到行者。'), findsNothing);
      expect(find.text('确认将这个 FIT 文件上传到 Strava 和行者。'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      planCompleter.complete(_dualPlan());
      await tester.pumpAndSettle();

      expect(find.text('上传到 Strava 和行者'), findsOneWidget);
      expect(find.text('确认将这个 FIT 文件上传到 Strava 和行者。'), findsOneWidget);
    },
  );

  testWidgets(
    'uses preflight missing-configuration state before upload starts',
    (WidgetTester tester) async {
      await pumpScreenAndSettle(
        tester,
        event: const SharedFitEvent.draft(
          SharedFitDraft(
            localFilePath: '/tmp/ride.fit',
            displayName: 'ride.fit',
          ),
        ),
        uploadService: _FakeUploadService.withPlanAndResult(
          plan: _dualPlan(missingConfiguration: true),
          result: const SharedFitUploadResult(
            status: SharedFitUploadStatus.success,
            message: 'should not upload',
          ),
        ),
      );

      expect(find.text('缺少 Strava 和行者 必需配置，请先前往设置完成授权。'), findsOneWidget);
      expect(find.text('去设置'), findsOneWidget);
      expect(find.text('上传到 Strava 和行者'), findsNothing);
    },
  );

  testWidgets('preflight failure does not expose upload confirmation actions', (
    WidgetTester tester,
  ) async {
    bool dismissed = false;

    await pumpScreenAndSettle(
      tester,
      event: const SharedFitEvent.draft(
        SharedFitDraft(localFilePath: '/tmp/ride.fit', displayName: 'ride.fit'),
      ),
      uploadService: _FakeUploadService.withPlanLoadFailure(
        Exception('preflight unavailable'),
      ),
      onDismissToHome: () {
        dismissed = true;
      },
    );

    expect(find.text('上传到 Strava'), findsNothing);
    expect(find.text('上传到行者'), findsNothing);
    expect(find.text('上传到 Strava 和行者'), findsNothing);
    expect(find.text('返回首页'), findsOneWidget);

    await tester.tap(find.text('返回首页'));
    await tester.pumpAndSettle();

    expect(dismissed, isTrue);
  });

  testWidgets('shows success feedback before returning home', (
    WidgetTester tester,
  ) async {
    bool dismissed = false;

    await pumpScreenAndSettle(
      tester,
      event: const SharedFitEvent.draft(
        SharedFitDraft(localFilePath: '/tmp/ride.fit', displayName: 'ride.fit'),
      ),
      uploadService: _FakeUploadService.withPlanAndResult(
        plan: _stravaPlan(),
        result: const SharedFitUploadResult(
          status: SharedFitUploadStatus.success,
          message: 'FIT 文件已经上传到 Strava。',
        ),
      ),
      successFeedbackDuration: const Duration(milliseconds: 300),
      onDismissToHome: () {
        dismissed = true;
      },
    );

    expect(find.text('上传到 Strava'), findsOneWidget);

    await tester.tap(find.text('上传到 Strava'));
    await tester.pump();

    expect(find.text('上传成功'), findsOneWidget);
    expect(find.text('FIT 文件已经上传到 Strava。'), findsOneWidget);
    expect(dismissed, isFalse);

    await tester.pump(const Duration(milliseconds: 300));

    expect(dismissed, isTrue);
  });

  testWidgets('shows missing settings state and opens settings on request', (
    WidgetTester tester,
  ) async {
    bool openedSettings = false;

    await pumpScreenAndSettle(
      tester,
      event: const SharedFitEvent.draft(
        SharedFitDraft(localFilePath: '/tmp/ride.fit', displayName: 'ride.fit'),
      ),
      uploadService: _FakeUploadService.withPlanAndResult(
        plan: _stravaPlan(),
        result: const SharedFitUploadResult(
          status: SharedFitUploadStatus.missingConfiguration,
        ),
      ),
      onOpenSettings: () {
        openedSettings = true;
      },
    );

    await tester.tap(find.text('上传到 Strava'));
    await tester.pumpAndSettle();

    expect(find.text('去设置'), findsOneWidget);
    expect(find.text('缺少 Strava 必需配置，请先前往设置完成授权。'), findsOneWidget);

    await tester.tap(find.text('去设置'));
    await tester.pumpAndSettle();

    expect(openedSettings, isTrue);
  });

  testWidgets('shows invalid file state with a dismiss-to-home action', (
    WidgetTester tester,
  ) async {
    bool dismissed = false;

    await pumpScreenAndSettle(
      tester,
      event: const SharedFitEvent.draft(
        SharedFitDraft(localFilePath: '/tmp/ride.fit', displayName: 'ride.fit'),
      ),
      uploadService: _FakeUploadService.withPlanAndResult(
        plan: _stravaPlan(),
        result: const SharedFitUploadResult(
          status: SharedFitUploadStatus.invalidFile,
        ),
      ),
      onDismissToHome: () {
        dismissed = true;
      },
    );

    await tester.tap(find.text('上传到 Strava'));
    await tester.pumpAndSettle();

    expect(find.text('这个共享文件不是可上传的 FIT 文件。'), findsOneWidget);
    expect(find.text('返回首页'), findsOneWidget);

    await tester.tap(find.text('返回首页'));
    await tester.pumpAndSettle();

    expect(dismissed, isTrue);
  });

  testWidgets(
    'renders native intake errors as an error-only confirmation flow',
    (WidgetTester tester) async {
      bool dismissed = false;

      await pumpScreenAndSettle(
        tester,
        event: const SharedFitEvent.error('Unable to read shared FIT file'),
        uploadService: _FakeUploadService.withPlanAndResult(
          plan: _stravaPlan(),
          result: const SharedFitUploadResult(
            status: SharedFitUploadStatus.success,
            message: 'FIT 文件已经上传到 Strava。',
          ),
        ),
        onDismissToHome: () {
          dismissed = true;
        },
      );

      expect(find.text('Unable to read shared FIT file'), findsOneWidget);
      expect(find.text('返回首页'), findsOneWidget);
      expect(find.text('上传到 Strava'), findsNothing);

      await tester.tap(find.text('返回首页'));
      await tester.pumpAndSettle();

      expect(dismissed, isTrue);
    },
  );

  testWidgets('shows uploading state while the upload is active', (
    WidgetTester tester,
  ) async {
    final Completer<SharedFitUploadResult> completer =
        Completer<SharedFitUploadResult>();
    final ShareFlowUploadActivity uploadActivity = ShareFlowUploadActivity();

    await pumpScreenAndSettle(
      tester,
      event: const SharedFitEvent.draft(
        SharedFitDraft(localFilePath: '/tmp/ride.fit', displayName: 'ride.fit'),
      ),
      uploadService: _FakeUploadService.withPlanAndFuture(
        plan: _stravaPlan(),
        future: completer.future,
      ),
      uploadActivity: uploadActivity,
      successFeedbackDuration: Duration.zero,
    );

    await tester.tap(find.text('上传到 Strava'));
    await tester.pump();

    expect(find.text('上传中...'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(uploadActivity.isUploadActive, isTrue);

    completer.complete(
      const SharedFitUploadResult(
        status: SharedFitUploadStatus.success,
        message: 'FIT 文件已经上传到 Strava。',
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('keeps failures retryable on the same page', (
    WidgetTester tester,
  ) async {
    int attempts = 0;
    bool dismissed = false;

    await pumpScreenAndSettle(
      tester,
      event: const SharedFitEvent.draft(
        SharedFitDraft(localFilePath: '/tmp/ride.fit', displayName: 'ride.fit'),
      ),
      uploadService: _FakeUploadService.withPlanAndHandler(
        plan: _stravaPlan(),
        call: () async {
          attempts += 1;
          if (attempts == 1) {
            return const SharedFitUploadResult(
              status: SharedFitUploadStatus.failure,
              message: 'network error',
            );
          }
          return const SharedFitUploadResult(
            status: SharedFitUploadStatus.success,
            message: 'FIT 文件已经上传到 Strava。',
          );
        },
      ),
      successFeedbackDuration: Duration.zero,
      onDismissToHome: () {
        dismissed = true;
      },
    );

    await tester.tap(find.text('上传到 Strava'));
    await tester.pumpAndSettle();

    expect(find.text('上传失败'), findsOneWidget);
    expect(find.text('network error'), findsOneWidget);
    expect(find.text('重新上传'), findsOneWidget);
    expect(dismissed, isFalse);

    await tester.tap(find.text('重新上传'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(dismissed, isTrue);
  });

  testWidgets('confirm button says 上传到 Strava when only Strava is enabled', (
    WidgetTester tester,
  ) async {
    await pumpScreenAndSettle(
      tester,
      event: const SharedFitEvent.draft(
        SharedFitDraft(localFilePath: '/tmp/ride.fit', displayName: 'ride.fit'),
      ),
      uploadService: _FakeUploadService.withPlanAndResult(
        plan: _stravaPlan(),
        result: const SharedFitUploadResult(
          status: SharedFitUploadStatus.success,
          message: 'FIT 文件已经上传到 Strava。',
        ),
      ),
    );

    expect(find.text('上传到 Strava'), findsOneWidget);
    expect(find.text('确认将这个 FIT 文件上传到 Strava。'), findsOneWidget);
  });

  testWidgets('confirm button says 上传到行者 when only Xingzhe is enabled', (
    WidgetTester tester,
  ) async {
    await pumpScreenAndSettle(
      tester,
      event: const SharedFitEvent.draft(
        SharedFitDraft(localFilePath: '/tmp/ride.fit', displayName: 'ride.fit'),
      ),
      uploadService: _FakeUploadService.withPlanAndResult(
        plan: _xingzhePlan(),
        result: const SharedFitUploadResult(
          status: SharedFitUploadStatus.success,
          message: 'FIT 文件已经上传到行者。',
        ),
      ),
    );

    expect(find.text('上传到行者'), findsOneWidget);
    expect(find.text('确认将这个 FIT 文件上传到行者。'), findsOneWidget);
  });

  testWidgets('confirm button says 上传到 Strava 和行者 when both are enabled', (
    WidgetTester tester,
  ) async {
    await pumpScreenAndSettle(
      tester,
      event: const SharedFitEvent.draft(
        SharedFitDraft(localFilePath: '/tmp/ride.fit', displayName: 'ride.fit'),
      ),
      uploadService: _FakeUploadService.withPlanAndResult(
        plan: _dualPlan(),
        result: const SharedFitUploadResult(
          status: SharedFitUploadStatus.success,
          message: 'FIT 文件已经上传到 Strava 和行者。',
        ),
      ),
    );

    expect(find.text('上传到 Strava 和行者'), findsOneWidget);
    expect(find.text('确认将这个 FIT 文件上传到 Strava 和行者。'), findsOneWidget);
  });

  testWidgets('success copy supports Xingzhe-only success wording', (
    WidgetTester tester,
  ) async {
    await pumpScreenAndSettle(
      tester,
      event: const SharedFitEvent.draft(
        SharedFitDraft(localFilePath: '/tmp/ride.fit', displayName: 'ride.fit'),
      ),
      uploadService: _FakeUploadService.withPlanAndResult(
        plan: _xingzhePlan(),
        result: const SharedFitUploadResult(
          status: SharedFitUploadStatus.success,
          message: 'FIT 文件已经上传到行者。',
        ),
      ),
      successFeedbackDuration: Duration.zero,
    );

    await tester.tap(find.text('上传到行者'));
    await tester.pump();

    expect(find.text('上传成功'), findsOneWidget);
    expect(find.text('FIT 文件已经上传到行者。'), findsOneWidget);

    await tester.pumpAndSettle();
  });

  testWidgets('success copy supports dual-platform success wording', (
    WidgetTester tester,
  ) async {
    await pumpScreenAndSettle(
      tester,
      event: const SharedFitEvent.draft(
        SharedFitDraft(localFilePath: '/tmp/ride.fit', displayName: 'ride.fit'),
      ),
      uploadService: _FakeUploadService.withPlanAndResult(
        plan: _dualPlan(),
        result: const SharedFitUploadResult(
          status: SharedFitUploadStatus.success,
          message: 'FIT 文件已经上传到 Strava 和行者。',
        ),
      ),
      successFeedbackDuration: Duration.zero,
    );

    await tester.tap(find.text('上传到 Strava 和行者'));
    await tester.pump();

    expect(find.text('上传成功'), findsOneWidget);
    expect(find.text('FIT 文件已经上传到 Strava 和行者。'), findsOneWidget);

    await tester.pumpAndSettle();
  });

  testWidgets(
    'missing-config copy references enabled targets instead of always Strava',
    (WidgetTester tester) async {
      await pumpScreenAndSettle(
        tester,
        event: const SharedFitEvent.draft(
          SharedFitDraft(
            localFilePath: '/tmp/ride.fit',
            displayName: 'ride.fit',
          ),
        ),
        uploadService: _FakeUploadService.withPlanAndResult(
          plan: _dualPlan(missingConfiguration: true),
          result: const SharedFitUploadResult(
            status: SharedFitUploadStatus.missingConfiguration,
          ),
        ),
      );

      expect(find.text('缺少 Strava 和行者 必需配置，请先前往设置完成授权。'), findsOneWidget);
      expect(find.text('上传到 Strava 和行者'), findsNothing);
    },
  );

  testWidgets('partial-success upload uses a partial-success title', (
    WidgetTester tester,
  ) async {
    await pumpScreenAndSettle(
      tester,
      event: const SharedFitEvent.draft(
        SharedFitDraft(localFilePath: '/tmp/ride.fit', displayName: 'ride.fit'),
      ),
      uploadService: _FakeUploadService.withPlanAndResult(
        plan: _dualPlan(),
        result: const SharedFitUploadResult(
          status: SharedFitUploadStatus.partialSuccess,
          message: '已上传到 Strava；行者上传失败：session expired',
        ),
      ),
      successFeedbackDuration: Duration.zero,
    );

    await tester.tap(find.text('上传到 Strava 和行者'));
    await tester.pump();

    expect(find.text('部分成功'), findsOneWidget);
    expect(find.text('已上传到 Strava；行者上传失败：session expired'), findsOneWidget);

    await tester.pumpAndSettle();
  });

  testWidgets(
    'partial-success upload uses a partial-success fallback message when service message is absent',
    (WidgetTester tester) async {
      await pumpScreenAndSettle(
        tester,
        event: const SharedFitEvent.draft(
          SharedFitDraft(
            localFilePath: '/tmp/ride.fit',
            displayName: 'ride.fit',
          ),
        ),
        uploadService: _FakeUploadService.withPlanAndResult(
          plan: _dualPlan(),
          result: const SharedFitUploadResult(
            status: SharedFitUploadStatus.partialSuccess,
          ),
        ),
        successFeedbackDuration: Duration.zero,
      );

      await tester.tap(find.text('上传到 Strava 和行者'));
      await tester.pump();

      expect(find.text('部分成功'), findsOneWidget);
      expect(find.text('FIT 文件已上传，部分目标同步失败。'), findsOneWidget);
      expect(find.text('FIT 文件已经上传到 Strava 和行者。'), findsNothing);
      expect(find.textContaining('Strava 和行者'), findsNothing);

      await tester.pumpAndSettle();
    },
  );

  testWidgets('success screen uses the service-provided success message', (
    WidgetTester tester,
  ) async {
    await pumpScreenAndSettle(
      tester,
      event: const SharedFitEvent.draft(
        SharedFitDraft(localFilePath: '/tmp/ride.fit', displayName: 'ride.fit'),
      ),
      uploadService: _FakeUploadService.withPlanAndResult(
        plan: _dualPlan(),
        result: const SharedFitUploadResult(
          status: SharedFitUploadStatus.success,
          message: '服务返回的成功文案',
        ),
      ),
      successFeedbackDuration: Duration.zero,
    );

    await tester.tap(find.text('上传到 Strava 和行者'));
    await tester.pump();

    expect(find.text('服务返回的成功文案'), findsOneWidget);

    await tester.pumpAndSettle();
  });
}

class _FakeUploadService extends SharedFitUploadService {
  _FakeUploadService._({
    required Future<FitUploadPlan> Function() loadPlan,
    required Future<SharedFitUploadResult> Function() call,
  }) : _loadPlan = loadPlan,
       _call = call,
       super(loadSettings: () async => <String, String>{});

  final Future<FitUploadPlan> Function() _loadPlan;
  final Future<SharedFitUploadResult> Function() _call;

  factory _FakeUploadService.withPlanAndResult({
    required FitUploadPlan plan,
    required SharedFitUploadResult result,
  }) {
    return _FakeUploadService._(
      loadPlan: () async => plan,
      call: () async => result,
    );
  }

  factory _FakeUploadService.withAsyncPlanAndResult({
    required Future<FitUploadPlan> planFuture,
    required SharedFitUploadResult result,
  }) {
    return _FakeUploadService._(
      loadPlan: () => planFuture,
      call: () async => result,
    );
  }

  factory _FakeUploadService.withPlanLoadFailure(Exception error) {
    return _FakeUploadService._(
      loadPlan: () async => throw error,
      call: () async => throw StateError('uploadDraft should not be called'),
    );
  }

  factory _FakeUploadService.withPlanAndFuture({
    required FitUploadPlan plan,
    required Future<SharedFitUploadResult> future,
  }) {
    return _FakeUploadService._(loadPlan: () async => plan, call: () => future);
  }

  factory _FakeUploadService.withPlanAndHandler({
    required FitUploadPlan plan,
    required Future<SharedFitUploadResult> Function() call,
  }) {
    return _FakeUploadService._(loadPlan: () async => plan, call: call);
  }

  @override
  Future<FitUploadPlan> loadUploadPlan() async {
    return _loadPlan();
  }

  @override
  Future<SharedFitUploadResult> uploadDraft(SharedFitDraft draft) {
    return _call();
  }
}

FitUploadPlan _stravaPlan({bool missingConfiguration = false}) {
  return FitUploadPlan(
    targets: const <FitUploadPlatform>[FitUploadPlatform.strava],
    hasMissingConfiguration: missingConfiguration,
    targetLabel: 'Strava',
  );
}

FitUploadPlan _xingzhePlan({bool missingConfiguration = false}) {
  return FitUploadPlan(
    targets: const <FitUploadPlatform>[FitUploadPlatform.xingzhe],
    hasMissingConfiguration: missingConfiguration,
    targetLabel: '行者',
  );
}

FitUploadPlan _dualPlan({bool missingConfiguration = false}) {
  return FitUploadPlan(
    targets: const <FitUploadPlatform>[
      FitUploadPlatform.strava,
      FitUploadPlatform.xingzhe,
    ],
    hasMissingConfiguration: missingConfiguration,
    targetLabel: 'Strava 和行者',
  );
}
