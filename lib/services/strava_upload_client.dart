import 'dart:io';

abstract class StravaUploadClient {
  Future<int> uploadFit(File file);
  Future<Map<String, dynamic>> pollUpload(int uploadId);
  Future<bool> activityExists(int activityId);
  Future<void> ensureAccessToken();
}
