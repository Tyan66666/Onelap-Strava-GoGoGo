import 'dart:io';

import 'strava_upload_client.dart';
import 'strava_web_client.dart';

class StravaWebSyncAdapter implements StravaUploadClient {
  final StravaWebClient _webClient;

  StravaWebSyncAdapter({required String cookies})
    : _webClient = StravaWebClient(cookies: cookies);

  @override
  Future<int> uploadFit(File file) async {
    final result = await _webClient.uploadFit(file);
    return result['upload_id'] as int;
  }

  @override
  Future<Map<String, dynamic>> pollUpload(int uploadId) {
    return _webClient.pollUpload(uploadId);
  }

  @override
  Future<bool> activityExists(int activityId) async => true;

  @override
  Future<void> ensureAccessToken() async {}
}
