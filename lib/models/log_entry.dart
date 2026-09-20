class LogEntry {
  const LogEntry({
    required this.deviceId,
    required this.appVersion,
    required this.fileName,
    required this.path,
    required this.sizeBytes,
    required this.uploadedAt,
  });

  final String deviceId;
  final String appVersion;
  final String fileName;
  final String path;
  final int sizeBytes;
  final DateTime uploadedAt;

  Map<String, Object?> toJson() => {
        'deviceId': deviceId,
        'appVersion': appVersion,
        'fileName': fileName,
        'path': path,
        'sizeBytes': sizeBytes,
        'uploadedAt': uploadedAt.toIso8601String(),
      };
}
