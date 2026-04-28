import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/models/shared_fit_draft.dart';
import 'package:onelap_strava_sync/models/shared_fit_event.dart';
import 'package:onelap_strava_sync/services/share_intake_service.dart';
import 'package:onelap_strava_sync/services/share_navigation_coordinator.dart';
import 'package:onelap_strava_sync/services/settings_service.dart';
import 'package:onelap_strava_sync/services/shared_fit_upload_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  testWidgets('routes the initial shared draft through the root navigator', (
    WidgetTester tester,
  ) async {
    final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
    final _FakeShareIntakeService intakeService = _FakeShareIntakeService(
      initialEvent: const SharedFitEvent.draft(
        SharedFitDraft(
          localFilePath: '/tmp/first.fit',
          displayName: 'first.fit',
        ),
      ),
    );
    final ShareNavigationCoordinator coordinator = ShareNavigationCoordinator(
      navigatorKey: navigatorKey,
      shareIntakeService: intakeService,
      uploadService: _FakeUploadService.withResult(
        const SharedFitUploadResult(status: SharedFitUploadStatus.success),
      ),
      uploadActivity: ShareFlowUploadActivity(),
      successFeedbackDuration: Duration.zero,
    );

    addTearDown(coordinator.dispose);
    addTearDown(intakeService.dispose);

    await tester.pumpWidget(
      _CoordinatorHost(navigatorKey: navigatorKey, coordinator: coordinator),
    );
    await tester.pumpAndSettle();

    expect(find.text('first.fit'), findsOneWidget);
    expect(find.text('上传到 Strava'), findsOneWidget);
  });

  testWidgets(
    'subscribes before loading the initial event to avoid dropping startup events',
    (WidgetTester tester) async {
      final GlobalKey<NavigatorState> navigatorKey =
          GlobalKey<NavigatorState>();
      final Completer<SharedFitEvent?> initialEventCompleter =
          Completer<SharedFitEvent?>();
      final _FakeShareIntakeService intakeService = _FakeShareIntakeService(
        initialEventFuture: initialEventCompleter.future,
      );
      final ShareNavigationCoordinator coordinator = ShareNavigationCoordinator(
        navigatorKey: navigatorKey,
        shareIntakeService: intakeService,
        uploadService: _FakeUploadService.withResult(
          const SharedFitUploadResult(status: SharedFitUploadStatus.success),
        ),
        uploadActivity: ShareFlowUploadActivity(),
        successFeedbackDuration: Duration.zero,
      );

      addTearDown(coordinator.dispose);
      addTearDown(intakeService.dispose);

      await tester.pumpWidget(
        _CoordinatorHost(navigatorKey: navigatorKey, coordinator: coordinator),
      );
      await tester.pump();

      intakeService.add(
        const SharedFitEvent.draft(
          SharedFitDraft(
            localFilePath: '/tmp/stream.fit',
            displayName: 'stream.fit',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('stream.fit'), findsOneWidget);

      initialEventCompleter.complete(null);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'does not let a delayed initial event replace a newer live startup event',
    (WidgetTester tester) async {
      final GlobalKey<NavigatorState> navigatorKey =
          GlobalKey<NavigatorState>();
      final Completer<SharedFitEvent?> initialEventCompleter =
          Completer<SharedFitEvent?>();
      final _FakeShareIntakeService intakeService = _FakeShareIntakeService(
        initialEventFuture: initialEventCompleter.future,
      );
      final ShareNavigationCoordinator coordinator = ShareNavigationCoordinator(
        navigatorKey: navigatorKey,
        shareIntakeService: intakeService,
        uploadService: _FakeUploadService.withResult(
          const SharedFitUploadResult(status: SharedFitUploadStatus.success),
        ),
        uploadActivity: ShareFlowUploadActivity(),
        successFeedbackDuration: Duration.zero,
      );

      addTearDown(coordinator.dispose);
      addTearDown(intakeService.dispose);

      await tester.pumpWidget(
        _CoordinatorHost(navigatorKey: navigatorKey, coordinator: coordinator),
      );
      await tester.pump();

      intakeService.add(
        const SharedFitEvent.draft(
          SharedFitDraft(
            localFilePath: '/tmp/live.fit',
            displayName: 'live.fit',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('live.fit'), findsOneWidget);

      initialEventCompleter.complete(
        const SharedFitEvent.draft(
          SharedFitDraft(
            localFilePath: '/tmp/initial.fit',
            displayName: 'initial.fit',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('live.fit'), findsOneWidget);
      expect(find.text('initial.fit'), findsNothing);
    },
  );

  testWidgets('replaces the current confirmation route when idle', (
    WidgetTester tester,
  ) async {
    final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
    final _RecordingNavigatorObserver observer = _RecordingNavigatorObserver();
    final _FakeShareIntakeService intakeService = _FakeShareIntakeService(
      initialEvent: const SharedFitEvent.draft(
        SharedFitDraft(
          localFilePath: '/tmp/first.fit',
          displayName: 'first.fit',
        ),
      ),
    );
    final ShareNavigationCoordinator coordinator = ShareNavigationCoordinator(
      navigatorKey: navigatorKey,
      shareIntakeService: intakeService,
      uploadService: _FakeUploadService.withResult(
        const SharedFitUploadResult(status: SharedFitUploadStatus.success),
      ),
      uploadActivity: ShareFlowUploadActivity(),
      successFeedbackDuration: Duration.zero,
    );

    addTearDown(coordinator.dispose);
    addTearDown(intakeService.dispose);

    await tester.pumpWidget(
      _CoordinatorHost(
        navigatorKey: navigatorKey,
        coordinator: coordinator,
        observer: observer,
      ),
    );
    await tester.pumpAndSettle();

    intakeService.add(
      const SharedFitEvent.draft(
        SharedFitDraft(
          localFilePath: '/tmp/second.fit',
          displayName: 'second.fit',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('first.fit'), findsNothing);
    expect(find.text('second.fit'), findsOneWidget);
    expect(observer.didReplaceCount, greaterThanOrEqualTo(1));
  });

  testWidgets('ignores new share events while an upload is active', (
    WidgetTester tester,
  ) async {
    final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
    final Completer<SharedFitUploadResult> completer =
        Completer<SharedFitUploadResult>();
    final ShareFlowUploadActivity uploadActivity = ShareFlowUploadActivity();
    final _FakeShareIntakeService intakeService = _FakeShareIntakeService(
      initialEvent: const SharedFitEvent.draft(
        SharedFitDraft(
          localFilePath: '/tmp/first.fit',
          displayName: 'first.fit',
        ),
      ),
    );
    final ShareNavigationCoordinator coordinator = ShareNavigationCoordinator(
      navigatorKey: navigatorKey,
      shareIntakeService: intakeService,
      uploadService: _FakeUploadService.withFuture(completer.future),
      uploadActivity: uploadActivity,
      successFeedbackDuration: Duration.zero,
    );

    addTearDown(coordinator.dispose);
    addTearDown(intakeService.dispose);

    await tester.pumpWidget(
      _CoordinatorHost(navigatorKey: navigatorKey, coordinator: coordinator),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('上传到 Strava'));
    await tester.pump();
    expect(uploadActivity.isUploadActive, isTrue);

    intakeService.add(
      const SharedFitEvent.draft(
        SharedFitDraft(
          localFilePath: '/tmp/second.fit',
          displayName: 'second.fit',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('first.fit'), findsOneWidget);
    expect(find.text('second.fit'), findsNothing);

    completer.complete(
      const SharedFitUploadResult(status: SharedFitUploadStatus.success),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('routes native intake errors into the error-only flow', (
    WidgetTester tester,
  ) async {
    final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
    final _FakeShareIntakeService intakeService = _FakeShareIntakeService();
    final ShareNavigationCoordinator coordinator = ShareNavigationCoordinator(
      navigatorKey: navigatorKey,
      shareIntakeService: intakeService,
      uploadService: _FakeUploadService.withResult(
        const SharedFitUploadResult(status: SharedFitUploadStatus.success),
      ),
      uploadActivity: ShareFlowUploadActivity(),
      successFeedbackDuration: Duration.zero,
    );

    addTearDown(coordinator.dispose);
    addTearDown(intakeService.dispose);

    await tester.pumpWidget(
      _CoordinatorHost(navigatorKey: navigatorKey, coordinator: coordinator),
    );
    await tester.pumpAndSettle();

    intakeService.add(const SharedFitEvent.error('Share intent failed'));
    await tester.pumpAndSettle();

    expect(find.text('Share intent failed'), findsOneWidget);
    expect(find.text('返回首页'), findsOneWidget);
    expect(find.text('上传到 Strava'), findsNothing);
  });

  testWidgets(
    'going to settings from missing configuration replaces and discards the draft',
    (WidgetTester tester) async {
      final GlobalKey<NavigatorState> navigatorKey =
          GlobalKey<NavigatorState>();
      final _FakeShareIntakeService intakeService = _FakeShareIntakeService(
        initialEvent: const SharedFitEvent.draft(
          SharedFitDraft(
            localFilePath: '/tmp/first.fit',
            displayName: 'first.fit',
          ),
        ),
      );
      final ShareNavigationCoordinator coordinator = ShareNavigationCoordinator(
        navigatorKey: navigatorKey,
        shareIntakeService: intakeService,
        uploadService: _FakeUploadService.withResult(
          const SharedFitUploadResult(
            status: SharedFitUploadStatus.missingConfiguration,
          ),
        ),
        uploadActivity: ShareFlowUploadActivity(),
        successFeedbackDuration: Duration.zero,
      );

      addTearDown(coordinator.dispose);
      addTearDown(intakeService.dispose);

      await tester.pumpWidget(
        _CoordinatorHost(navigatorKey: navigatorKey, coordinator: coordinator),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('上传到 Strava'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('去设置'));
      await tester.pumpAndSettle();

      expect(find.text('设置'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('first.fit'), findsNothing);
    },
  );

  testWidgets('success dismissal returns to home from a secondary route', (
    WidgetTester tester,
  ) async {
    final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
    final _FakeShareIntakeService intakeService = _FakeShareIntakeService();
    final ShareNavigationCoordinator coordinator = ShareNavigationCoordinator(
      navigatorKey: navigatorKey,
      shareIntakeService: intakeService,
      uploadService: _FakeUploadService.withResult(
        const SharedFitUploadResult(status: SharedFitUploadStatus.success),
      ),
      uploadActivity: ShareFlowUploadActivity(),
      successFeedbackDuration: Duration.zero,
    );

    addTearDown(coordinator.dispose);
    addTearDown(intakeService.dispose);

    await tester.pumpWidget(
      _CoordinatorHost(
        navigatorKey: navigatorKey,
        coordinator: coordinator,
        initialRoute: '/details',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('DETAILS'), findsOneWidget);

    intakeService.add(
      const SharedFitEvent.draft(
        SharedFitDraft(
          localFilePath: '/tmp/first.fit',
          displayName: 'first.fit',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('上传到 Strava'));
    await tester.pumpAndSettle();

    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('DETAILS'), findsNothing);
  });
}

class _CoordinatorHost extends StatefulWidget {
  const _CoordinatorHost({
    required this.navigatorKey,
    required this.coordinator,
    this.observer,
    this.initialRoute = '/',
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final ShareNavigationCoordinator coordinator;
  final NavigatorObserver? observer;
  final String initialRoute;

  @override
  State<_CoordinatorHost> createState() => _CoordinatorHostState();
}

class _CoordinatorHostState extends State<_CoordinatorHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.coordinator.start();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: widget.navigatorKey,
      initialRoute: widget.initialRoute,
      navigatorObservers: widget.observer == null
          ? const <NavigatorObserver>[]
          : <NavigatorObserver>[widget.observer!],
      routes: <String, WidgetBuilder>{
        '/': (_) => const Scaffold(body: Center(child: Text('HOME'))),
        '/details': (_) => const Scaffold(body: Center(child: Text('DETAILS'))),
      },
    );
  }
}

class _FakeShareIntakeService extends ShareIntakeService {
  _FakeShareIntakeService({
    this.initialEvent,
    Future<SharedFitEvent?>? initialEventFuture,
  }) : _initialEventFuture = initialEventFuture;

  final SharedFitEvent? initialEvent;
  final Future<SharedFitEvent?>? _initialEventFuture;
  final StreamController<SharedFitEvent> _controller =
      StreamController<SharedFitEvent>.broadcast();

  @override
  Future<SharedFitEvent?> loadInitialEvent() async {
    if (_initialEventFuture != null) {
      return _initialEventFuture;
    }
    return initialEvent;
  }

  @override
  Stream<SharedFitEvent> get events => _controller.stream;

  void add(SharedFitEvent event) {
    _controller.add(event);
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}

class _FakeUploadService extends SharedFitUploadService {
  _FakeUploadService._({required Future<SharedFitUploadResult> Function() call})
    : _call = call,
      super(
        loadSettings: () async => <String, String>{
          SettingsService.keyUploadToStrava: 'true',
          SettingsService.keyStravaClientId: 'client-id',
          SettingsService.keyStravaClientSecret: 'client-secret',
          SettingsService.keyStravaRefreshToken: 'refresh-token',
        },
      );

  final Future<SharedFitUploadResult> Function() _call;

  factory _FakeUploadService.withResult(SharedFitUploadResult result) {
    return _FakeUploadService._(call: () async => result);
  }

  factory _FakeUploadService.withFuture(Future<SharedFitUploadResult> future) {
    return _FakeUploadService._(call: () => future);
  }

  @override
  Future<SharedFitUploadResult> uploadDraft(SharedFitDraft draft) {
    return _call();
  }
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  int didReplaceCount = 0;

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    didReplaceCount += 1;
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }
}
