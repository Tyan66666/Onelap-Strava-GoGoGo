import 'dart:io';
import 'dart:typed_data';

import 'package:fit_tool/fit_tool.dart';
import 'package:path_provider/path_provider.dart';

import 'coordinate_converter.dart';

/// FIT 文件 session 元数据（距离、爬升、运动类型）
class FitSessionMeta {
  final double? distanceM;
  final int? ascentM;
  final String? sport;
  const FitSessionMeta({this.distanceM, this.ascentM, this.sport});
}

/// 从 FIT 文件解析 session metadata（不修改文件）。
Future<FitSessionMeta> parseFitSessionMeta(File fitFile) async {
  try {
    final Uint8List bytes = await fitFile.readAsBytes();
    final FitFile fit = FitFile.fromBytes(bytes);

    double? distanceM;
    int? ascentM;
    String? sport;

    for (final record in fit.records) {
      final msg = record.message;
      if (msg is SessionMessage) {
        distanceM = msg.totalDistance;
        ascentM = msg.totalAscent;
        if (msg.sport != null) {
          sport = msg.sport!.name;
        }
        break; // 只取第一个 session
      }
    }

    return FitSessionMeta(distanceM: distanceM, ascentM: ascentM, sport: sport);
  } catch (_) {
    return const FitSessionMeta();
  }
}

typedef CacheDirectoryLoader = Future<Directory> Function();

/// Rewrite options passed to [rewrite].
class RewriteOptions {
  /// The activity's start time in ISO8601 format, used to derive the output filename.
  /// If omitted, falls back to 'rewritten'.
  final String? startTime;

  /// Optional source filename to preserve extension.
  final String? sourceFilename;

  const RewriteOptions({this.startTime, this.sourceFilename});
}

class FitCoordinateRewriteService {
  FitCoordinateRewriteService({CacheDirectoryLoader? loadCacheDirectory})
    : _loadCacheDirectory = loadCacheDirectory ?? getApplicationCacheDirectory;

  final CacheDirectoryLoader _loadCacheDirectory;

  /// Rewrites the FIT file, converting GCJ-02 coordinates to WGS-84.
  ///
  /// [inputFile] - the original FIT file.
  /// [options] - optional rewrite parameters (startTime for naming).
  Future<File> rewrite(File inputFile, {RewriteOptions? options}) async {
    final Uint8List bytes = await inputFile.readAsBytes();
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

    final Directory cacheDirectory = await _loadCacheDirectory();
    final File outputFile = await _createOutputFile(
      cacheDirectory,
      startTime: options?.startTime,
      sourceFilename: options?.sourceFilename,
    );
    await outputFile.writeAsBytes(fitFile.toBytes());
    return outputFile;
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

  /// Builds a filename from startTime like '2024-01-15.fit', falling back to
  /// the source filename extension or plain 'rewritten.fit'.
  String _deriveOutputFilename({String? startTime, String? sourceFilename}) {
    if (startTime != null && startTime.length >= 10) {
      final datePart = startTime.substring(0, 10); // 'YYYY-MM-DD'
      return '$datePart.fit';
    }
    if (sourceFilename != null) {
      final trimmed = sourceFilename.trim();
      if (trimmed.isNotEmpty) {
        final hasFitExt = trimmed.toLowerCase().endsWith('.fit');
        if (hasFitExt) return trimmed;
        return '$trimmed.fit';
      }
    }
    return 'rewritten.fit';
  }

  Future<File> _createOutputFile(
    Directory cacheDirectory, {
    String? startTime,
    String? sourceFilename,
  }) async {
    await cacheDirectory.create(recursive: true);
    final Directory outputDirectory = await cacheDirectory.createTemp(
      'fit-coordinate-rewrite-',
    );
    final filename = _deriveOutputFilename(
      startTime: startTime,
      sourceFilename: sourceFilename,
    );
    return File('${outputDirectory.path}/$filename');
  }
}
