import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/update_info.dart';

class UpdateChecker {
  static const _owner = 'Tyan66666';
  static const _repo = 'Onelap-Strava-GoGoGo';
  static const _apiUrl =
      'https://api.github.com/repos/$_owner/$_repo/releases/latest';

  static int compareVersions(String current, String latest) {
    try {
      final c = current.split('.').map((s) => int.tryParse(s) ?? 0).toList();
      final l = latest.split('.').map((s) => int.tryParse(s) ?? 0).toList();
      for (var i = 0; i < 3; i++) {
        final cv = i < c.length ? c[i] : 0;
        final lv = i < l.length ? l[i] : 0;
        if (lv > cv) return 1;
        if (lv < cv) return -1;
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  static bool _hasPlatformAsset(List<dynamic> assets) {
    for (final asset in assets) {
      final name = (asset as Map<String, dynamic>)['name'] as String? ?? '';
      final lower = name.toLowerCase();
      if (Platform.isAndroid && lower.endsWith('.apk')) return true;
      if (Platform.isIOS && lower.endsWith('.ipa')) return true;
      if (Platform.isMacOS &&
          (lower.endsWith('.dmg') ||
              lower.endsWith('.pkg') ||
              lower.endsWith('.zip'))) {
        return true;
      }
    }
    return false;
  }

  static Future<UpdateInfo> check({Dio? dio, String? currentVersion}) async {
    final ver = currentVersion ?? (await PackageInfo.fromPlatform()).version;

    try {
      final d =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
              headers: {
                'Accept': 'application/vnd.github.v3+json',
                'User-Agent': 'OnelapStravaSync/$ver',
              },
              validateStatus: (_) => true,
            ),
          );

      final response = await d.get(_apiUrl);
      if (response.statusCode != 200) {
        return UpdateInfo.noUpdate(ver);
      }

      final data = response.data as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      final latestVersion = tagName.startsWith('v')
          ? tagName.substring(1)
          : tagName;
      final body = data['body'] as String? ?? '';
      final assets = data['assets'] as List<dynamic>? ?? [];

      final comparison = compareVersions(ver, latestVersion);
      if (comparison != 1) {
        return UpdateInfo.noUpdate(ver);
      }

      if (!_hasPlatformAsset(assets)) {
        return UpdateInfo.noUpdate(ver);
      }

      return UpdateInfo(
        hasUpdate: true,
        latestVersion: latestVersion,
        currentVersion: ver,
        releaseNotes: body,
        downloadUrl: 'https://github.com/$_owner/$_repo/releases/tag/$tagName',
      );
    } catch (_) {
      return UpdateInfo.noUpdate(ver);
    }
  }
}
