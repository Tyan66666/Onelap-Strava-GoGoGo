import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/shared_fit_event.dart';
import '../screens/settings_screen.dart';
import '../screens/share_confirm_screen.dart';
import 'share_intake_service.dart';
import 'shared_fit_upload_service.dart';

class ShareFlowUploadActivity {
  bool _isUploadActive = false;

  bool get isUploadActive => _isUploadActive;

  void startUpload() {
    _isUploadActive = true;
  }

  void finishUpload() {
    _isUploadActive = false;
  }
}

class ShareNavigationCoordinator {
  ShareNavigationCoordinator({
    required GlobalKey<NavigatorState> navigatorKey,
    ShareIntakeService? shareIntakeService,
    SharedFitUploadService? uploadService,
    ShareFlowUploadActivity? uploadActivity,
    Duration successFeedbackDuration = const Duration(milliseconds: 1200),
  }) : _navigatorKey = navigatorKey,
       _shareIntakeService = shareIntakeService ?? ShareIntakeService(),
       _uploadService = uploadService ?? SharedFitUploadService(),
       _uploadActivity = uploadActivity ?? ShareFlowUploadActivity(),
       _successFeedbackDuration = successFeedbackDuration;

  final GlobalKey<NavigatorState> _navigatorKey;
  final ShareIntakeService _shareIntakeService;
  final SharedFitUploadService _uploadService;
  final ShareFlowUploadActivity _uploadActivity;
  final Duration _successFeedbackDuration;

  StreamSubscription<SharedFitEvent>? _eventsSubscription;
  bool _started = false;
  bool _showingShareRoute = false;
  bool _loadingInitialEvent = false;
  bool _showedLiveEventDuringStartup = false;
  int _routeToken = 0;

  void start() {
    if (_started) {
      return;
    }
    _started = true;
    _startAsync();
  }

  Future<void> dispose() async {
    await _eventsSubscription?.cancel();
  }

  Future<void> _startAsync() async {
    _loadingInitialEvent = true;
    _eventsSubscription = _shareIntakeService.events.listen((
      SharedFitEvent event,
    ) {
      final bool didShowEvent = _showEvent(event);
      if (_loadingInitialEvent && didShowEvent) {
        _showedLiveEventDuringStartup = true;
      }
    }, onError: (_) {});

    try {
      final SharedFitEvent? initialEvent = await _shareIntakeService
          .loadInitialEvent();
      if (initialEvent != null && !_showedLiveEventDuringStartup) {
        _showEvent(initialEvent);
      }
    } on MissingPluginException {
      // Share intake is optional outside the native share entrypoint.
    } on PlatformException {
      // Ignore platform startup failures and keep the app usable.
    } finally {
      _loadingInitialEvent = false;
    }
  }

  bool _showEvent(SharedFitEvent event) {
    if (_uploadActivity.isUploadActive) {
      return false;
    }

    final NavigatorState? navigator = _navigatorKey.currentState;
    if (navigator == null) {
      return false;
    }

    final Route<void> route = MaterialPageRoute<void>(
      builder: (_) => ShareConfirmScreen(
        event: event,
        uploadService: _uploadService,
        uploadActivity: _uploadActivity,
        successFeedbackDuration: _successFeedbackDuration,
        onOpenSettings: _openSettingsFromMissingConfiguration,
        onDismissToHome: _dismissToHome,
      ),
    );

    if (_showingShareRoute) {
      _trackShareRoute(navigator.pushReplacement<void, void>(route));
      return true;
    }

    _trackShareRoute(navigator.push<void>(route));
    return true;
  }

  void _trackShareRoute(Future<dynamic> routeFuture) {
    _showingShareRoute = true;
    final int token = ++_routeToken;
    routeFuture.whenComplete(() {
      if (_routeToken != token) {
        return;
      }
      _showingShareRoute = false;
    });
  }

  void _dismissToHome() {
    final NavigatorState? navigator = _navigatorKey.currentState;
    if (navigator == null) {
      return;
    }

    navigator.popUntil((Route<dynamic> route) => route.isFirst);
  }

  void _openSettingsFromMissingConfiguration() {
    final NavigatorState? navigator = _navigatorKey.currentState;
    if (navigator == null) {
      return;
    }

    _showingShareRoute = false;
    _routeToken += 1;

    navigator.pushReplacement<void, void>(
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
  }
}
