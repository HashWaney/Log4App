import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/log_entry.dart';

class LogStorageService {
  LogStorageService({Directory? rootDirectory, Directory? videoRootDirectory})
      : _rootDirectory = rootDirectory,
        _videoRootDirectory = videoRootDirectory;

  Directory? _rootDirectory;
  Directory? _videoRootDirectory;

  Directory get rootDirectory {
    final value = _rootDirectory;
    if (value == null) {
      throw StateError('Log storage has not been initialized yet.');
    }
    return value;
  }

  Directory get videoRootDirectory {
    final value = _videoRootDirectory;
    if (value == null) {
      throw StateError('Video storage has not been initialized yet.');
    }
    return value;
  }

  Future<void> ensureReady() async {
    if (_rootDirectory == null) {
      final documents = await getApplicationDocumentsDirectory();
      final preferred = Directory(p.join(documents.path, 'Log4AppLogs'));
      final legacy = Directory(p.join(documents.path, 'AndroidDeviceLogs'));

      if (!await preferred.exists() && await legacy.exists()) {
        try {
          _rootDirectory = await legacy.rename(preferred.path);
        } on FileSystemException {
          // Keep existing logs accessible if an in-place migration is blocked.
          _rootDirectory = legacy;
        }
      }
      _rootDirectory ??= preferred;
    }
    _videoRootDirectory ??= Directory(
      p.join(_rootDirectory!.parent.path, 'Log4AppVideos'),
    );
    await _rootDirectory!.create(recursive: true);
    await _videoRootDirectory!.create(recursive: true);
  }

  Future<LogEntry> storeTempUpload({
    required File tempFile,
    required String deviceId,
    required String appVersion,
    required String originalFileName,
    required int sizeBytes,
  }) async {
    await ensureReady();
    return _storeTempUpload(
      root: rootDirectory,
      tempFile: tempFile,
      deviceId: deviceId,
      appVersion: appVersion,
      originalFileName: originalFileName,
      sizeBytes: sizeBytes,
      defaultFileName: 'logs.zip',
    );
  }

  Future<LogEntry> storeTempVideoUpload({
    required File tempFile,
    required String deviceId,
    required String appVersion,
    required String originalFileName,
    required int sizeBytes,
  }) async {
    await ensureReady();
    return _storeTempUpload(
      root: videoRootDirectory,
      tempFile: tempFile,
      deviceId: deviceId,
      appVersion: appVersion,
      originalFileName: originalFileName,
      sizeBytes: sizeBytes,
      defaultFileName: 'screen_recording.mp4',
    );
  }

  Future<LogEntry> _storeTempUpload({
    required Directory root,
    required File tempFile,
    required String deviceId,
    required String appVersion,
    required String originalFileName,
    required int sizeBytes,
    required String defaultFileName,
  }) async {
    await ensureReady();

    final now = DateTime.now();
    final safeDevice =
        _sanitize(deviceId.isEmpty ? 'unknown-device' : deviceId);
    final safeVersion = _sanitize(appVersion.isEmpty ? 'unknown' : appVersion);
    final safeOriginal = _sanitizeFileName(
      originalFileName.isEmpty ? defaultFileName : originalFileName,
    );
    final day = _yyyyMmDd(now);
    final dir = Directory(p.join(root.path, safeDevice, day));
    await dir.create(recursive: true);

    final timestamp = _timestamp(now);
    final fileName = '${timestamp}_${safeVersion}_$safeOriginal';
    final targetPath = p.join(dir.path, fileName);

    File target;
    try {
      target = await tempFile.rename(targetPath);
    } on FileSystemException {
      // Cross-volume renames can fail on Windows/macOS temp directories.
      // Fall back to copy + delete so uploads are still durable.
      target = await tempFile.copy(targetPath);
      await tempFile.delete();
    }

    return LogEntry(
      deviceId: deviceId.trim().isEmpty ? 'unknown-device' : deviceId.trim(),
      appVersion: safeVersion,
      fileName: fileName,
      path: target.path,
      sizeBytes: sizeBytes,
      uploadedAt: now,
    );
  }

  Future<List<LogEntry>> listLogs({int limit = 100}) async {
    await ensureReady();
    return _listEntries(rootDirectory, limit: limit);
  }

  Future<List<LogEntry>> listVideos({int limit = 100}) async {
    await ensureReady();
    return _listEntries(videoRootDirectory, limit: limit);
  }

  Future<List<LogEntry>> _listEntries(
    Directory root, {
    required int limit,
  }) async {
    final result = <LogEntry>[];

    await for (final entity in root.list(recursive: true)) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      final relative = p.relative(entity.path, from: root.path);
      final parts = p.split(relative);
      final deviceId = parts.isNotEmpty ? parts.first : 'unknown-device';
      result.add(
        LogEntry(
          deviceId: deviceId,
          appVersion: _extractVersion(entity.path),
          fileName: p.basename(entity.path),
          path: entity.path,
          sizeBytes: stat.size,
          uploadedAt: stat.modified,
        ),
      );
    }

    result.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
    return result.take(limit).toList();
  }

  String _extractVersion(String filePath) {
    final name = p.basename(filePath);
    final match = RegExp(r'^\d{8}_\d{6}_\d{3}_([^_]+)_').firstMatch(name);
    return match?.group(1) ?? 'unknown';
  }

  String _sanitize(String value) => value
      .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
      .replaceAll(RegExp(r'_+'), '_');

  String _sanitizeFileName(String value) =>
      _sanitize(p.basename(value)).replaceAll('..', '.');

  String _yyyyMmDd(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  String _timestamp(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}'
      '${value.month.toString().padLeft(2, '0')}'
      '${value.day.toString().padLeft(2, '0')}_'
      '${value.hour.toString().padLeft(2, '0')}'
      '${value.minute.toString().padLeft(2, '0')}'
      '${value.second.toString().padLeft(2, '0')}_'
      '${value.millisecond.toString().padLeft(3, '0')}';
}
