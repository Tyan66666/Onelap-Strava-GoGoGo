import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onelap_strava_sync/screens/home_screen.dart';
import 'package:onelap_strava_sync/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  group('sync credential validation', () {
    testWidgets(
      'web mode does not block sync when Strava API credentials are empty',
      (WidgetTester tester) async {
        FlutterSecureStorage.setMockInitialValues(<String, String>{
          SettingsService.keyOneLapUsername: 'user@test.com',
          SettingsService.keyOneLapPassword: 'pass',
          SettingsService.keyUploadToStrava: 'true',
          SettingsService.keyStravaUploadMode: 'web',
        });

        await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
        await tester.pumpAndSettle();

        await tester.tap(find.text('立即同步'));
        await tester.pumpAndSettle();

        expect(find.text('请先在设置中填写 Strava 凭证'), findsNothing);
      },
    );

    testWidgets('api mode blocks sync when Strava API credentials are empty', (
      WidgetTester tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        SettingsService.keyOneLapUsername: 'user@test.com',
        SettingsService.keyOneLapPassword: 'pass',
        SettingsService.keyUploadToStrava: 'true',
        SettingsService.keyStravaUploadMode: 'api',
      });

      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('立即同步'));
      await tester.pumpAndSettle();

      expect(find.text('请先在设置中填写 Strava 凭证'), findsOneWidget);
    });

    testWidgets(
      'blocks sync when Intervals.icu is enabled but credentials are empty',
      (WidgetTester tester) async {
        FlutterSecureStorage.setMockInitialValues(<String, String>{
          SettingsService.keyOneLapUsername: 'user@test.com',
          SettingsService.keyOneLapPassword: 'pass',
          SettingsService.keyUploadToIntervalsIcu: 'true',
        });

        await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
        await tester.pumpAndSettle();

        await tester.tap(find.text('立即同步'));
        await tester.pumpAndSettle();

        expect(find.text('请先在设置中填写 Intervals.icu 凭证'), findsOneWidget);
      },
    );

    testWidgets('blocks sync when no platform is selected', (
      WidgetTester tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues(<String, String>{
        SettingsService.keyOneLapUsername: 'user@test.com',
        SettingsService.keyOneLapPassword: 'pass',
        SettingsService.keyUploadToStrava: 'false',
        SettingsService.keyUploadToXingzhe: 'false',
        SettingsService.keyUploadToIntervalsIcu: 'false',
      });

      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('立即同步'));
      await tester.pumpAndSettle();

      expect(find.text('请至少选择一个上传平台'), findsOneWidget);
    });
  });
}
