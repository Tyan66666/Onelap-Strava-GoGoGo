import 'package:flutter/material.dart';

import 'services/fit_coordinate_rewrite_service.dart';
import 'services/share_navigation_coordinator.dart';
import 'services/shared_fit_upload_service.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const OneLapStravaApp());
}

class OneLapStravaApp extends StatefulWidget {
  const OneLapStravaApp({super.key});

  @override
  State<OneLapStravaApp> createState() => _OneLapStravaAppState();
}

class _OneLapStravaAppState extends State<OneLapStravaApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final SharedFitUploadService _sharedFitUploadService =
      SharedFitUploadService(rewriteService: FitCoordinateRewriteService());
  late final ShareNavigationCoordinator _shareNavigationCoordinator =
      ShareNavigationCoordinator(
        navigatorKey: _navigatorKey,
        uploadService: _sharedFitUploadService,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shareNavigationCoordinator.start();
    });
  }

  @override
  void dispose() {
    _shareNavigationCoordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'WanSync',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrange,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
