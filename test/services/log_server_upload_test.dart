import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:log4app/services/log_server.dart';
import 'package:log4app/services/log_storage_service.dart';
import 'package:log4app/services/network_service.dart';

void main() {
  late Directory tempDirectory;
  late LogStorageService storage;
  late LogServer server;
  late int port;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('log4app_test_');
    storage = LogStorageService(
      rootDirectory: Directory('${tempDirectory.path}/logs'),
      videoRootDirectory: Directory('${tempDirectory.path}/videos'),
    );

    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    port = probe.port;
    await probe.close();

    server = LogServer(
      storage: storage,
      network: NetworkService(),
      serverVersion: 'test',
      port: port,
    );
    await server.start();
  });

  tearDown(() async {
    await server.stop();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('log and MP4 uploads use independent endpoints and storage', () async {
    final logResponse = await _postMultipart(
      port: port,
      path: '/api/log/upload',
      fileName: 'logs.zip',
      contentType: 'application/zip',
      bytes: utf8.encode('test log archive'),
    );

    expect(logResponse.statusCode, HttpStatus.ok);
    expect(logResponse.body['success'], isTrue);
    expect(logResponse.body.containsKey('artifactType'), isFalse);
    expect(server.totalUploads, 1);
    expect(server.totalVideoUploads, 0);

    final videoResponse = await _postMultipart(
      port: port,
      path: '/api/video/upload',
      fileName: 'screen_recording.mp4',
      contentType: 'video/mp4',
      bytes: <int>[0, 0, 0, 24, 102, 116, 121, 112, 109, 112, 52, 50],
    );

    expect(videoResponse.statusCode, HttpStatus.ok);
    expect(videoResponse.body['success'], isTrue);
    expect(videoResponse.body['artifactType'], 'screen_recording');
    expect(server.totalUploads, 1);
    expect(server.totalVideoUploads, 1);

    final logs = await storage.listLogs();
    final videos = await storage.listVideos();
    expect(logs, hasLength(1));
    expect(videos, hasLength(1));
    expect(logs.single.fileName, endsWith('_logs.zip'));
    expect(videos.single.fileName, endsWith('_screen_recording.mp4'));
    expect(logs.single.path, startsWith(storage.rootDirectory.path));
    expect(videos.single.path, startsWith(storage.videoRootDirectory.path));
  });

  test('video endpoint rejects a non-MP4 file without affecting logs',
      () async {
    final response = await _postMultipart(
      port: port,
      path: '/api/video/upload',
      fileName: 'screen_recording.mov',
      contentType: 'video/quicktime',
      bytes: <int>[1, 2, 3],
    );

    expect(response.statusCode, HttpStatus.unsupportedMediaType);
    expect(server.totalVideoUploads, 0);
    expect(await storage.listVideos(), isEmpty);
    expect(await storage.listLogs(), isEmpty);
  });
}

Future<_HttpResult> _postMultipart({
  required int port,
  required String path,
  required String fileName,
  required String contentType,
  required List<int> bytes,
}) async {
  final client = HttpClient();
  try {
    final request =
        await client.post(InternetAddress.loopbackIPv4.host, port, path);
    final boundary = 'log4app-test-${DateTime.now().microsecondsSinceEpoch}';
    request.headers.contentType = ContentType(
      'multipart',
      'form-data',
      parameters: <String, String>{'boundary': boundary},
    );

    void addField(String name, String value) {
      request.add(
        utf8.encode(
          '--$boundary\r\n'
          'Content-Disposition: form-data; name="$name"\r\n\r\n'
          '$value\r\n',
        ),
      );
    }

    addField('deviceId', 'TEST_001');
    addField('deviceName', 'Upload Test Device');
    addField('appVersion', '1.0.0');
    addField('platform', 'Android');
    addField('platformVersion', '15');
    request.add(
      utf8.encode(
        '--$boundary\r\n'
        'Content-Disposition: form-data; name="file"; filename="$fileName"\r\n'
        'Content-Type: $contentType\r\n\r\n',
      ),
    );
    request.add(bytes);
    request.add(utf8.encode('\r\n--$boundary--\r\n'));

    final response = await request.close();
    final responseBody = await utf8.decoder.bind(response).join();
    return _HttpResult(
      statusCode: response.statusCode,
      body: Map<String, Object?>.from(jsonDecode(responseBody) as Map),
    );
  } finally {
    client.close(force: true);
  }
}

class _HttpResult {
  const _HttpResult({required this.statusCode, required this.body});

  final int statusCode;
  final Map<String, Object?> body;
}
