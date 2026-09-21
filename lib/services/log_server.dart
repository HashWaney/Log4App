import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mime/mime.dart';

import '../models/connected_device.dart';
import '../models/log_entry.dart';
import 'log_storage_service.dart';
import 'network_service.dart';

class LogServer {
  LogServer({
    required LogStorageService storage,
    required NetworkService network,
    this.port = 9090,
    this.maxUploadBytes = 500 * 1024 * 1024,
    this.onlineTimeout = const Duration(seconds: 90),
  })  : _storage = storage,
        _network = network;

  // V2 protocol identifier retained so already-shipped scanner clients work.
  static const String serviceType = 'android-log-center';
  static const String serviceName = 'Log4App';
  static const int protocolVersion = 1;
  static const String serverVersion = '2.1.0';

  final LogStorageService _storage;
  final NetworkService _network;
  final int port;
  final int maxUploadBytes;
  final Duration onlineTimeout;

  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;
  final Map<String, ConnectedDevice> _devices = <String, ConnectedDevice>{};

  bool get isRunning => _server != null;
  int totalUploads = 0;
  int totalBytes = 0;
  String? lastError;
  LogEntry? lastUpload;

  List<ConnectedDevice> get devices {
    final items = _devices.values.toList()
      ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    return List.unmodifiable(items);
  }

  List<ConnectedDevice> get onlineDevices => devices
      .where((device) => device.isOnline(onlineTimeout))
      .toList(growable: false);

  Future<void> start() async {
    if (isRunning) return;
    await _storage.ensureReady();
    try {
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        port,
        shared: true,
      );
      _subscription = _server!.listen(
        _handleRequest,
        onError: (Object error, StackTrace stackTrace) {
          lastError = error.toString();
        },
      );
      lastError = null;
    } catch (e) {
      _server = null;
      lastError = e.toString();
      rethrow;
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    _addCorsHeaders(request.response);
    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    try {
      if (request.method == 'GET' && request.uri.path == '/api/server/info') {
        await _handleServerInfo(request);
        return;
      }

      // Backward-compatible connectivity endpoint used by V2.0 clients.
      if (request.method == 'GET' && request.uri.path == '/api/log/ping') {
        await _json(request.response, HttpStatus.ok, {
          'success': true,
          'message': '$serviceName online',
          'serviceName': serviceName,
          'serviceType': serviceType,
          'protocolVersion': protocolVersion,
          'serverVersion': serverVersion,
          'port': port,
          'time': DateTime.now().toIso8601String(),
        });
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/api/device/ping') {
        await _handleDevicePing(request);
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/api/device/list') {
        await _json(request.response, HttpStatus.ok, {
          'success': true,
          'items': devices
              .map((e) => e.toJson(onlineTimeout: onlineTimeout))
              .toList(),
        });
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/api/log/list') {
        final logs = await _storage.listLogs();
        await _json(request.response, HttpStatus.ok, {
          'success': true,
          'items': logs.map((e) => e.toJson()).toList(),
        });
        return;
      }

      if (request.method == 'POST' && request.uri.path == '/api/log/upload') {
        await _handleUpload(request);
        return;
      }

      await _json(request.response, HttpStatus.notFound, {
        'success': false,
        'message': 'Not found',
      });
    } catch (e, stackTrace) {
      lastError = '$e\n$stackTrace';
      try {
        await _json(request.response, HttpStatus.internalServerError, {
          'success': false,
          'message': e.toString(),
        });
      } catch (_) {
        try {
          await request.response.close();
        } catch (_) {}
      }
    }
  }

  Future<void> _handleServerInfo(HttpRequest request) async {
    final addresses = await _network.getLanIpv4Addresses();
    await _json(request.response, HttpStatus.ok, {
      'success': true,
      'serviceName': serviceName,
      'serviceType': serviceType,
      'protocolVersion': protocolVersion,
      'serverVersion': serverVersion,
      'port': port,
      'addresses': addresses,
      'baseUrls': addresses.map((address) => 'http://$address:$port').toList(),
      'onlineDeviceCount': onlineDevices.length,
      'time': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _handleDevicePing(HttpRequest request) async {
    final contentType = request.headers.contentType;
    if (contentType?.mimeType != 'application/json') {
      await _json(request.response, HttpStatus.unsupportedMediaType, {
        'success': false,
        'message': 'Content-Type must be application/json',
      });
      return;
    }

    final bytes = request.map<List<int>>((chunk) => chunk);
    final body = await utf8.decoder.bind(bytes).join();

    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      await _json(request.response, HttpStatus.badRequest, {
        'success': false,
        'message': 'invalid JSON',
      });
      return;
    }

    if (decoded is! Map) {
      await _json(request.response, HttpStatus.badRequest, {
        'success': false,
        'message': 'JSON object required',
      });
      return;
    }

    final payload = Map<String, dynamic>.from(decoded);
    final deviceId = _stringValue(payload['deviceId']);
    if (deviceId.isEmpty) {
      await _json(request.response, HttpStatus.badRequest, {
        'success': false,
        'message': 'deviceId is required',
      });
      return;
    }

    final legacyAndroidVersion = _stringValue(payload['androidVersion']);
    final platform = _stringValue(payload['platform']);
    final platformVersion = _stringValue(payload['platformVersion']);
    final device = _touchDevice(
      deviceId: deviceId,
      deviceName: _stringValue(payload['deviceName']),
      appVersion: _stringValue(payload['appVersion']),
      platform: platform.isEmpty
          ? (legacyAndroidVersion.isEmpty ? 'unknown' : 'Android')
          : platform,
      platformVersion:
          platformVersion.isEmpty ? legacyAndroidVersion : platformVersion,
    );

    lastError = null;
    await _json(request.response, HttpStatus.ok, {
      'success': true,
      'message': 'device connected',
      'serviceName': serviceName,
      'serviceType': serviceType,
      'protocolVersion': protocolVersion,
      'serverVersion': serverVersion,
      'serverTime': DateTime.now().toIso8601String(),
      'device': device.toJson(onlineTimeout: onlineTimeout),
    });
  }

  Future<void> _handleUpload(HttpRequest request) async {
    final contentType = request.headers.contentType;
    if (contentType?.mimeType == 'multipart/form-data') {
      await _handleMultipartUpload(request, contentType!);
      return;
    }

    await _handleRawUpload(request);
  }

  Future<void> _handleMultipartUpload(
    HttpRequest request,
    ContentType contentType,
  ) async {
    final boundary = contentType.parameters['boundary'];
    if (boundary == null || boundary.isEmpty) {
      await _json(request.response, HttpStatus.badRequest, {
        'success': false,
        'message': 'multipart boundary missing',
      });
      return;
    }

    String deviceId = '';
    String deviceName = '';
    String appVersion = '';
    String platform = '';
    String platformVersion = '';
    String legacyAndroidVersion = '';
    String originalFileName = 'logs.zip';
    File? tempFile;
    int fileBytes = 0;

    final byteStream = request.map<List<int>>((chunk) => chunk);
    final parts = MimeMultipartTransformer(boundary).bind(byteStream);

    await for (final MimeMultipart part in parts) {
      final disposition = part.headers['content-disposition'] ?? '';
      final fieldName = _dispositionValue(disposition, 'name') ?? '';
      final fileName = _dispositionValue(disposition, 'filename');

      if (fieldName == 'file' || fileName != null) {
        originalFileName = fileName ?? originalFileName;
        tempFile ??= File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}'
          'log4app_${DateTime.now().microsecondsSinceEpoch}.upload',
        );
        final sink = tempFile.openWrite();
        await for (final List<int> chunk in part) {
          fileBytes += chunk.length;
          if (fileBytes > maxUploadBytes) {
            await sink.close();
            await _safeDelete(tempFile);
            await _json(request.response, HttpStatus.requestEntityTooLarge, {
              'success': false,
              'message': 'Upload exceeds $maxUploadBytes bytes',
            });
            return;
          }
          sink.add(chunk);
        }
        await sink.close();
      } else {
        final value = await utf8.decoder.bind(part).join();
        if (fieldName == 'deviceId') deviceId = value.trim();
        if (fieldName == 'deviceName') deviceName = value.trim();
        if (fieldName == 'appVersion') appVersion = value.trim();
        if (fieldName == 'platform') platform = value.trim();
        if (fieldName == 'platformVersion') platformVersion = value.trim();
        if (fieldName == 'androidVersion') {
          legacyAndroidVersion = value.trim();
        }
      }
    }

    if (deviceId.trim().isEmpty) {
      await _safeDelete(tempFile);
      await _json(request.response, HttpStatus.badRequest, {
        'success': false,
        'message': 'deviceId is required',
      });
      return;
    }

    if (tempFile == null || !await tempFile.exists()) {
      await _json(request.response, HttpStatus.badRequest, {
        'success': false,
        'message': 'file part missing',
      });
      return;
    }

    final entry = await _storage.storeTempUpload(
      tempFile: tempFile,
      deviceId: deviceId,
      appVersion: appVersion,
      originalFileName: originalFileName,
      sizeBytes: fileBytes,
    );
    _recordUpload(
      entry,
      deviceName: deviceName,
      platform: platform.isEmpty
          ? (legacyAndroidVersion.isEmpty ? 'unknown' : 'Android')
          : platform,
      platformVersion:
          platformVersion.isEmpty ? legacyAndroidVersion : platformVersion,
    );

    await _json(request.response, HttpStatus.ok, {
      'success': true,
      'item': entry.toJson(),
    });
  }

  Future<void> _handleRawUpload(HttpRequest request) async {
    final deviceId = request.headers.value('x-device-id')?.trim() ?? '';
    if (deviceId.isEmpty) {
      await _json(request.response, HttpStatus.badRequest, {
        'success': false,
        'message': 'X-Device-Id header is required',
      });
      return;
    }

    final deviceName = request.headers.value('x-device-name') ?? '';
    final appVersion = request.headers.value('x-app-version') ?? 'unknown';
    final legacyAndroidVersion =
        request.headers.value('x-android-version') ?? '';
    final platform = request.headers.value('x-platform') ?? '';
    final platformVersion =
        request.headers.value('x-platform-version') ?? legacyAndroidVersion;
    final fileName = request.headers.value('x-file-name') ?? 'logs.zip';
    final tempFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'log4app_${DateTime.now().microsecondsSinceEpoch}.upload',
    );
    final sink = tempFile.openWrite();
    var size = 0;

    await for (final chunk in request) {
      size += chunk.length;
      if (size > maxUploadBytes) {
        await sink.close();
        await _safeDelete(tempFile);
        await _json(request.response, HttpStatus.requestEntityTooLarge, {
          'success': false,
          'message': 'Upload exceeds $maxUploadBytes bytes',
        });
        return;
      }
      sink.add(chunk);
    }
    await sink.close();

    final entry = await _storage.storeTempUpload(
      tempFile: tempFile,
      deviceId: deviceId,
      appVersion: appVersion,
      originalFileName: fileName,
      sizeBytes: size,
    );
    _recordUpload(
      entry,
      deviceName: deviceName,
      platform: platform.isEmpty
          ? (legacyAndroidVersion.isEmpty ? 'unknown' : 'Android')
          : platform,
      platformVersion: platformVersion,
    );

    await _json(request.response, HttpStatus.ok, {
      'success': true,
      'item': entry.toJson(),
    });
  }

  ConnectedDevice _touchDevice({
    required String deviceId,
    String deviceName = '',
    String appVersion = '',
    String platform = '',
    String platformVersion = '',
    DateTime? lastUploadAt,
    int? lastUploadBytes,
  }) {
    final now = DateTime.now();
    final existing = _devices[deviceId];

    final item = existing == null
        ? ConnectedDevice(
            deviceId: deviceId,
            deviceName: deviceName.isEmpty ? deviceId : deviceName,
            appVersion: appVersion.isEmpty ? 'unknown' : appVersion,
            platform: platform.isEmpty ? 'unknown' : platform,
            platformVersion:
                platformVersion.isEmpty ? 'unknown' : platformVersion,
            lastSeen: now,
            lastUploadAt: lastUploadAt,
            lastUploadBytes: lastUploadBytes ?? 0,
          )
        : existing.copyWith(
            deviceName: deviceName.isEmpty ? existing.deviceName : deviceName,
            appVersion: appVersion.isEmpty ? existing.appVersion : appVersion,
            platform: platform.isEmpty ? existing.platform : platform,
            platformVersion: platformVersion.isEmpty
                ? existing.platformVersion
                : platformVersion,
            lastSeen: now,
            lastUploadAt: lastUploadAt,
            lastUploadBytes: lastUploadBytes,
          );

    _devices[deviceId] = item;
    return item;
  }

  void _recordUpload(
    LogEntry entry, {
    String deviceName = '',
    String platform = '',
    String platformVersion = '',
  }) {
    totalUploads += 1;
    totalBytes += entry.sizeBytes;
    lastUpload = entry;
    lastError = null;

    _touchDevice(
      deviceId: entry.deviceId,
      deviceName: deviceName,
      appVersion: entry.appVersion,
      platform: platform,
      platformVersion: platformVersion,
      lastUploadAt: entry.uploadedAt,
      lastUploadBytes: entry.sizeBytes,
    );
  }

  String _stringValue(Object? value) => value?.toString().trim() ?? '';

  String? _dispositionValue(String disposition, String key) {
    final pattern = RegExp('$key="([^"]*)"');
    return pattern.firstMatch(disposition)?.group(1);
  }

  Future<void> _safeDelete(File? file) async {
    if (file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  void _addCorsHeaders(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set(
      'Access-Control-Allow-Headers',
      'Content-Type, X-Device-Id, X-Device-Name, X-App-Version, '
          'X-Platform, X-Platform-Version, X-Android-Version, X-File-Name',
    );
    response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  }

  Future<void> _json(
    HttpResponse response,
    int status,
    Object value,
  ) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(value));
    await response.close();
  }
}
