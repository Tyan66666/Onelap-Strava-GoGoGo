import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';

void main() async {
  final sessionId = Platform.environment['OUTBASE_SESSION_ID'] ?? '';
  if (sessionId.isEmpty) {
    stderr.writeln('ERROR: Set OUTBASE_SESSION_ID environment variable');
    exit(1);
  }

  final fitPath =
      '/Users/yintianan/Library/Containers/com.tencent.xinWeChat/Data/Documents/'
      'xwechat_files/wxid_ah9fv86bqsu621_9c7b/msg/file/2026-07/'
      'MAGENE_C706_2025-09-30_183310_677767.fit';
  final fileBytes = await File(fitPath).readAsBytes();
  print('FIT file size: ${fileBytes.length} bytes');

  final guid = generateGuid();
  final dateTagVal = dateTagNow();
  final guidHex = guid.replaceAll('-', '');
  final prefix1 = guidHex.substring(0, 2);
  final prefix2 = guidHex.substring(2, 4);

  print('\n=== GUID formats ===');
  print('guid (with hyphens): $guid');
  print('guidHex (no hyphens): $guidHex');
  print('dateTag: $dateTagVal');

  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  // Test 1: Current implementation (no hyphens in id and uri)
  print('\n=== Test 1: Current implementation (no hyphens) ===');
  final url1 =
      'https://melon-gateway.immomo.com/zeusfit/resource/upload'
      '?source=zeusfit'
      '&id=$guidHex$dateTagVal'
      '&uri=/resource/$prefix1/$prefix2/$guidHex.fit'
      '&momoid=0';
  print('URL: $url1');
  await _tryUpload(dio, url1, fileBytes, fitPath, sessionId);

  // Test 2: Spec format (hyphens in id, hyphens in uri) — WRONG
  print('\n=== Test 2: Spec format (hyphens in id and uri) ===');
  final url2 =
      'https://melon-gateway.immomo.com/zeusfit/resource/upload'
      '?source=zeusfit'
      '&id=$guid$dateTagVal'
      '&uri=/resource/$prefix1/$prefix2/$guid.fit'
      '&momoid=0';
  print('URL: $url2');
  await _tryUpload(dio, url2, fileBytes, fitPath, sessionId);

  // Test 3: Browser format (hyphens in id, hyphens+dateTag in uri)
  print('\n=== Test 3: Browser format (hyphens+dateTag in uri) ===');
  final url3 =
      'https://melon-gateway.immomo.com/zeusfit/resource/upload'
      '?source=zeusfit'
      '&id=$guid$dateTagVal'
      '&uri=/resource/$prefix1/$prefix2/$guid$dateTagVal.fit'
      '&momoid=0&';
  print('URL: $url3');
  await _tryUpload(dio, url3, fileBytes, fitPath, sessionId);

  // Test 4: Browser format without trailing &
  print('\n=== Test 4: Browser format without trailing & ===');
  final url4 =
      'https://melon-gateway.immomo.com/zeusfit/resource/upload'
      '?source=zeusfit'
      '&id=$guid$dateTagVal'
      '&uri=/resource/$prefix1/$prefix2/$guid$dateTagVal.fit'
      '&momoid=0';
  print('URL: $url4');
  await _tryUpload(dio, url4, fileBytes, fitPath, sessionId);

  // Test 5: With trailing & (like spec shows)
  print('\n=== Test 5: With trailing & ===');
  final url5 =
      'https://melon-gateway.immomo.com/zeusfit/resource/upload'
      '?source=zeusfit'
      '&id=$guid$dateTagVal'
      '&uri=/resource/$prefix1/$prefix2/$guid.fit'
      '&momoid=0'
      '&';
  print('URL: $url5');
  await _tryUpload(dio, url5, fileBytes, fitPath, sessionId);

  // Test 6: Try with Dio's queryParameters to check encoding behavior
  print('\n=== Test 6: Dio queryParameters (hyphens) ===');
  final uri6 = '/resource/$prefix1/$prefix2/$guid.fit';
  print('uri parameter value: $uri6');
  print('uri parameter URL-encoded: ${Uri.encodeComponent(uri6)}');
  try {
    final resp = await dio.post(
      'https://melon-gateway.immomo.com/zeusfit/resource/upload',
      queryParameters: {
        'source': 'zeusfit',
        'id': '$guid$dateTagVal',
        'uri': uri6,
        'momoid': '0',
      },
      options: Options(
        headers: {'Cookie': 'sessionId=$sessionId'},
        validateStatus: (s) => true,
      ),
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(fileBytes, filename: 'test.fit'),
      }),
    );
    print('Status: ${resp.statusCode}');
    print('Response: ${resp.data}');
  } catch (e) {
    print('Error: $e');
  }
}

Future<void> _tryUpload(
  Dio dio,
  String url,
  List<int> fileBytes,
  String fitPath,
  String sessionId,
) async {
  try {
    final resp = await dio.post(
      url,
      options: Options(
        headers: {'Cookie': 'sessionId=$sessionId'},
        validateStatus: (s) => true,
      ),
      data: FormData.fromMap({
        'file': MultipartFile.fromBytes(
          fileBytes,
          filename: fitPath.split('/').last,
        ),
      }),
    );
    print('Status: ${resp.statusCode}');
    print('Response: ${resp.data}');
  } catch (e) {
    print('Error: $e');
  }
}

String generateGuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
}

String dateTagNow() {
  final now = DateTime.now();
  return '${now.year}'
      '${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}';
}
