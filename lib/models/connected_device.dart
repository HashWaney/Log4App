class ConnectedDevice {
  const ConnectedDevice({
    required this.deviceId,
    required this.deviceName,
    required this.appVersion,
    required this.androidVersion,
    required this.lastSeen,
    this.lastUploadAt,
    this.lastUploadBytes = 0,
  });

  final String deviceId;
  final String deviceName;
  final String appVersion;
  final String androidVersion;
  final DateTime lastSeen;
  final DateTime? lastUploadAt;
  final int lastUploadBytes;

  bool isOnline(Duration timeout, {DateTime? now}) {
    final current = now ?? DateTime.now();
    return current.difference(lastSeen) <= timeout;
  }

  ConnectedDevice copyWith({
    String? deviceName,
    String? appVersion,
    String? androidVersion,
    DateTime? lastSeen,
    DateTime? lastUploadAt,
    int? lastUploadBytes,
  }) {
    return ConnectedDevice(
      deviceId: deviceId,
      deviceName: deviceName ?? this.deviceName,
      appVersion: appVersion ?? this.appVersion,
      androidVersion: androidVersion ?? this.androidVersion,
      lastSeen: lastSeen ?? this.lastSeen,
      lastUploadAt: lastUploadAt ?? this.lastUploadAt,
      lastUploadBytes: lastUploadBytes ?? this.lastUploadBytes,
    );
  }

  Map<String, Object?> toJson({Duration? onlineTimeout}) => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'appVersion': appVersion,
        'androidVersion': androidVersion,
        'lastSeen': lastSeen.toIso8601String(),
        'lastUploadAt': lastUploadAt?.toIso8601String(),
        'lastUploadBytes': lastUploadBytes,
        if (onlineTimeout != null) 'online': isOnline(onlineTimeout),
      };
}
