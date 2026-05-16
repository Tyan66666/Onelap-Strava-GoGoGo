import 'dart:io';
import 'isolate_helpers.dart';

Future<String> makeFingerprint(
  File file,
  String startTime,
  String recordKey,
) async {
  return computeFingerprintInIsolate(file.path, startTime, recordKey);
}
