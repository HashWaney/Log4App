import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/connected_device.dart';
import '../models/log_entry.dart';
import '../services/log_server.dart';
import '../services/log_storage_service.dart';
import '../services/network_service.dart';
import '../widgets/stat_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    required this.serverVersion,
    super.key,
  });

  final String serverVersion;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final LogStorageService _storage;
  late final LogServer _server;
  final NetworkService _network = NetworkService();

  Timer? _timer;
  List<String> _addresses = const [];
  List<LogEntry> _logs = const [];
  List<LogEntry> _videos = const [];
  List<ConnectedDevice> _devices = const [];
  String? _uiError;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _storage = LogStorageService();
    _server = LogServer(
      storage: _storage,
      network: _network,
      serverVersion: widget.serverVersion,
    );
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await _storage.ensureReady();
      await _server.start();
      await _refresh();
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    } catch (e) {
      _uiError = e.toString();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    try {
      final addresses = await _network.getLanIpv4Addresses();
      final logs = await _storage.listLogs(limit: 50);
      final videos = await _storage.listVideos(limit: 50);
      if (!mounted) return;
      setState(() {
        _addresses = addresses;
        _logs = logs;
        _videos = videos;
        _devices = _server.devices;
        _uiError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _uiError = e.toString());
    }
  }

  String? get _primaryAddress => _addresses.isEmpty ? null : _addresses.first;

  String get _serverBaseUrl => _primaryAddress == null
      ? 'http://<电脑IP>:${_server.port}'
      : 'http://$_primaryAddress:${_server.port}';

  String get _uploadUrl => '$_serverBaseUrl/api/log/upload';
  String get _videoUploadUrl => '$_serverBaseUrl/api/video/upload';

  String? get _qrPayload {
    final address = _primaryAddress;
    if (!_server.isRunning || address == null) return null;

    return jsonEncode({
      'type': LogServer.serviceType,
      'serviceName': LogServer.serviceName,
      'version': LogServer.protocolVersion,
      'scheme': 'http',
      'host': address,
      'port': _server.port,
      'baseUrl': 'http://$address:${_server.port}',
    });
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  String _relativeTime(DateTime value) {
    final diff = DateTime.now().difference(value);
    if (diff.inSeconds < 10) return '刚刚';
    if (diff.inSeconds < 60) return '${diff.inSeconds} 秒前';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return _formatDateTime(value);
  }

  Future<void> _toggleServer() async {
    setState(() => _busy = true);
    try {
      if (_server.isRunning) {
        await _server.stop();
      } else {
        await _server.start();
      }
      await _refresh();
    } catch (e) {
      _uiError = e.toString();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openLogFolder() async {
    await _openInSystem(_storage.rootDirectory.path, '日志目录');
  }

  Future<void> _openVideoFolder() async {
    await _openInSystem(_storage.videoRootDirectory.path, '录屏目录');
  }

  Future<void> _openVideo(String path) async {
    await _openInSystem(path, '录屏文件');
  }

  Future<void> _openInSystem(String path, String label) async {
    try {
      ProcessResult? result;
      if (Platform.isMacOS) {
        result = await Process.run('open', [path]);
      } else if (Platform.isWindows) {
        result = await Process.run('explorer', [path]);
      } else if (Platform.isLinux) {
        result = await Process.run('xdg-open', [path]);
      }

      if (result != null && result.exitCode != 0) {
        throw FileSystemException('无法打开$label', path);
      }
    } catch (e) {
      await Clipboard.setData(ClipboardData(text: path));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法自动打开$label，路径已复制：$path')),
      );
    }
  }

  Future<void> _copyText(String value, String message) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _server.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onlineCount = _devices
        .where((device) => device.isOnline(_server.onlineTimeout))
        .length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log4App'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text(
                'V${_server.serverVersion}',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _busy && _logs.isEmpty && _videos.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SelectionArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildTopSection(),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: StatCard(
                                title: '已连接设备',
                                value: '$onlineCount',
                                subtitle: '90 秒内有通信',
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: StatCard(
                                title: '本次上传',
                                value: '${_server.totalUploads}',
                                subtitle: '个日志包',
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: StatCard(
                                title: '本次流量',
                                value: _formatBytes(_server.totalBytes),
                                subtitle: '已接收',
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: StatCard(
                                title: '本地日志',
                                value: '${_logs.length}',
                                subtitle: '最近 50 条',
                              ),
                            ),
                          ],
                        ),
                        if (_uiError != null || _server.lastError != null) ...[
                          const SizedBox(height: 18),
                          _buildErrorCard(_uiError ?? _server.lastError!),
                        ],
                        const SizedBox(height: 18),
                        _buildDevicesCard(),
                        const SizedBox(height: 18),
                        _buildVideosCard(),
                        const SizedBox(height: 18),
                        _buildLogsCard(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildTopSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _buildServerCard()),
              const SizedBox(width: 18),
              Expanded(flex: 2, child: _buildQrCard()),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildServerCard(),
            const SizedBox(height: 18),
            _buildQrCard(),
          ],
        );
      },
    );
  }

  Widget _buildServerCard() {
    final running = _server.isRunning;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  running ? Icons.check_circle : Icons.pause_circle,
                  color: running ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    running ? '日志服务运行中' : '日志服务已停止',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : _toggleServer,
                  icon: Icon(running ? Icons.stop : Icons.play_arrow),
                  label: Text(running ? '停止服务' : '启动服务'),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _InfoLine(label: '本机局域网 IP', value: _primaryAddress ?? '未发现'),
            const SizedBox(height: 10),
            _InfoLine(label: '监听地址', value: '0.0.0.0:${_server.port}'),
            const SizedBox(height: 10),
            _InfoLine(label: '服务器地址', value: _serverBaseUrl),
            const SizedBox(height: 10),
            _InfoLine(label: 'App 上传', value: _uploadUrl),
            const SizedBox(height: 10),
            _InfoLine(label: '录屏上传', value: _videoUploadUrl),
            const SizedBox(height: 10),
            _InfoLine(label: '日志目录', value: _storage.rootDirectory.path),
            const SizedBox(height: 10),
            _InfoLine(label: '录屏目录', value: _storage.videoRootDirectory.path),
            if (_addresses.length > 1) ...[
              const SizedBox(height: 10),
              _InfoLine(
                label: '其他候选 IP',
                value: _addresses.skip(1).join('  ·  '),
              ),
            ],
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _primaryAddress == null
                      ? null
                      : () => _copyText(_serverBaseUrl, '服务器地址已复制'),
                  icon: const Icon(Icons.copy),
                  label: const Text('复制服务器地址'),
                ),
                OutlinedButton.icon(
                  onPressed: _openLogFolder,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('打开日志目录'),
                ),
                OutlinedButton.icon(
                  onPressed: _openVideoFolder,
                  icon: const Icon(Icons.video_library_outlined),
                  label: const Text('打开录屏目录'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrCard() {
    final payload = _qrPayload;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('扫码连接', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '采集端 App 与电脑需处于可互访的同一局域网。电脑 IP 变化后二维码会自动刷新。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: payload == null
                  ? Container(
                      width: 220,
                      height: 220,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          '服务器未启动或未检测到局域网 IP',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(12),
                      child: QrImageView(
                        data: payload,
                        size: 220,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Colors.black,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Colors.black,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text(
                _primaryAddress == null
                    ? '等待网络地址'
                    : '$_primaryAddress:${_server.port}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '扫码后采集端 App 应先调用 POST /api/device/ping；Ping 成功后这里会显示已连接设备。',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDevicesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('已登记设备', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                Text('${_devices.length} 台已登记'),
              ],
            ),
            const SizedBox(height: 14),
            if (_devices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('暂无设备。请使用采集端 App 扫描上方二维码。'),
                ),
              )
            else
              ..._devices.map(_buildDeviceTile),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceTile(ConnectedDevice device) {
    final online = device.isOnline(_server.onlineTimeout);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.smartphone,
        color: online ? Colors.green : null,
      ),
      title: Row(
        children: [
          Flexible(child: Text(device.deviceName)),
          const SizedBox(width: 10),
          _StatusChip(online: online),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          'ID: ${device.deviceId}  ·  App ${device.appVersion}  ·  '
          '${device.platform} ${device.platformVersion}\n'
          '最后通信：${_relativeTime(device.lastSeen)}'
          '${device.lastUploadAt == null ? '' : '  ·  最后上传：${_relativeTime(device.lastUploadAt!)} (${_formatBytes(device.lastUploadBytes)})'}',
        ),
      ),
      isThreeLine: true,
    );
  }

  Widget _buildErrorCard(String error) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline),
            const SizedBox(width: 10),
            Expanded(child: Text(error)),
          ],
        ),
      ),
    );
  }

  Widget _buildLogsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('最近日志', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 14),
            if (_logs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: Text('还没有收到 App 日志')),
              )
            else
              ..._logs.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.description_outlined),
                  title: Text(item.fileName),
                  subtitle: Text(
                    '${item.deviceId}  ·  ${item.appVersion}  ·  '
                    '${_formatDateTime(item.uploadedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(_formatBytes(item.sizeBytes)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideosCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('最近录屏反馈', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                Flexible(
                  child: Text(
                    '本次 ${_server.totalVideoUploads} 个 / '
                    '${_formatBytes(_server.totalVideoBytes)} · '
                    '本地最近 ${_videos.length} 个',
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_videos.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: Text('还没有收到录屏反馈')),
              )
            else
              ..._videos.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.play_circle_outline),
                  title: Text(item.fileName),
                  subtitle: Text(
                    '${item.deviceId}  ·  ${item.appVersion}  ·  '
                    '${_formatDateTime(item.uploadedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(_formatBytes(item.sizeBytes)),
                  onTap: () => _openVideo(item.path),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: online
            ? Colors.green.withValues(alpha: 0.12)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        online ? '已连接' : '最近连接',
        style: TextStyle(
          color: online ? Colors.green.shade700 : null,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: SelectableText(value)),
      ],
    );
  }
}
