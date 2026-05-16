import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fit_tool/fit_tool.dart';

import 'coordinate_converter.dart';
import 'fit_coordinate_rewrite_service.dart';

/// Top-level function for Isolate.run: SHA-256 hash of bytes.
String computeSha256Hex(Uint8List bytes) {
  return sha256.convert(bytes).toString();
}

/// Top-level function for Isolate.run: compute fingerprint.
String _computeFingerprintSync(
  String filePath,
  String startTime,
  String recordKey,
) {
  final bytes = File(filePath).readAsBytesSync();
  final hash = computeSha256Hex(bytes);
  return '$recordKey|$hash|$startTime';
}

/// Runs SHA-256 fingerprint computation in a background isolate.
Future<String> computeFingerprintInIsolate(
  String filePath,
  String startTime,
  String recordKey,
) {
  return Isolate.run(
    () => _computeFingerprintSync(filePath, startTime, recordKey),
  );
}

/// Top-level function for Isolate.run: parse FIT session metadata.
FitSessionMeta _parseFitSessionMetaSync(String filePath) {
  try {
    final Uint8List bytes = File(filePath).readAsBytesSync();
    final FitFile fit = FitFile.fromBytes(bytes);

    double? distanceM;
    int? ascentM;
    String? sport;
    String? startTime;

    for (final record in fit.records) {
      final msg = record.message;
      if (msg is SessionMessage) {
        distanceM = msg.totalDistance;
        ascentM = msg.totalAscent;
        if (msg.sport != null) {
          sport = msg.sport!.name;
        }
        if (msg.startTime != null) {
          startTime = DateTime.fromMillisecondsSinceEpoch(
            msg.startTime!,
            isUtc: true,
          ).toIso8601String().replaceFirst(RegExp(r'\.\d+'), '');
        }
        break;
      }
    }

    return FitSessionMeta(
      distanceM: distanceM,
      ascentM: ascentM,
      sport: sport,
      startTime: startTime,
    );
  } catch (_) {
    return const FitSessionMeta();
  }
}

/// Runs FIT session metadata parsing in a background isolate.
Future<FitSessionMeta> parseFitSessionMetaInIsolate(String filePath) {
  return Isolate.run(() => _parseFitSessionMetaSync(filePath));
}

/// Top-level function for Isolate.run: rewrite FIT coordinates.
Uint8List _rewriteFitCoordinatesSync(String filePath) {
  final Uint8List bytes = File(filePath).readAsBytesSync();
  final FitFile fitFile = FitFile.fromBytes(bytes);

  for (final Record record in fitFile.records) {
    final Message message = record.message;
    if (message is RecordMessage) {
      _rewriteCoordinatePair(
        readLatitude: () => message.positionLat,
        readLongitude: () => message.positionLong,
        writeLatitude: (double? value) => message.positionLat = value,
        writeLongitude: (double? value) => message.positionLong = value,
      );
    } else if (message is LapMessage) {
      _rewriteCoordinatePair(
        readLatitude: () => message.startPositionLat,
        readLongitude: () => message.startPositionLong,
        writeLatitude: (double? value) => message.startPositionLat = value,
        writeLongitude: (double? value) => message.startPositionLong = value,
      );
      _rewriteCoordinatePair(
        readLatitude: () => message.endPositionLat,
        readLongitude: () => message.endPositionLong,
        writeLatitude: (double? value) => message.endPositionLat = value,
        writeLongitude: (double? value) => message.endPositionLong = value,
      );
    } else if (message is SessionMessage) {
      _rewriteCoordinatePair(
        readLatitude: () => message.startPositionLat,
        readLongitude: () => message.startPositionLong,
        writeLatitude: (double? value) => message.startPositionLat = value,
        writeLongitude: (double? value) => message.startPositionLong = value,
      );
      _rewriteCoordinatePair(
        readLatitude: () => message.necLat,
        readLongitude: () => message.necLong,
        writeLatitude: (double? value) => message.necLat = value,
        writeLongitude: (double? value) => message.necLong = value,
      );
      _rewriteCoordinatePair(
        readLatitude: () => message.swcLat,
        readLongitude: () => message.swcLong,
        writeLatitude: (double? value) => message.swcLat = value,
        writeLongitude: (double? value) => message.swcLong = value,
      );
    }
  }

  fitFile.crc = null;
  return fitFile.toBytes();
}

/// Runs FIT coordinate rewriting in a background isolate.
Future<Uint8List> rewriteFitCoordinatesInIsolate(String filePath) {
  return Isolate.run(() => _rewriteFitCoordinatesSync(filePath));
}

void _rewriteCoordinatePair({
  required double? Function() readLatitude,
  required double? Function() readLongitude,
  required void Function(double? value) writeLatitude,
  required void Function(double? value) writeLongitude,
}) {
  final double? latitude = readLatitude();
  final double? longitude = readLongitude();

  if (latitude == null || longitude == null) {
    return;
  }

  final (double convertedLatitude, double convertedLongitude) =
      CoordinateConverter.gcj02ToWgs84Exact(latitude, longitude);

  if (!_isValidLatitude(convertedLatitude) ||
      !_isValidLongitude(convertedLongitude)) {
    return;
  }

  writeLatitude(_roundToFitCoordinatePrecision(convertedLatitude));
  writeLongitude(_roundToFitCoordinatePrecision(convertedLongitude));
}

bool _isValidLatitude(double value) => value >= -90 && value <= 90;
bool _isValidLongitude(double value) => value >= -180 && value <= 180;

double _roundToFitCoordinatePrecision(double value) {
  final int semicircles = (value * 2147483648 / 180.0).round();
  return semicircles * 180.0 / 2147483648;
}
