# Log4App — Flutter Desktop V2.1

![图](image.png)

Windows、macOS、Linux 跨平台局域网 App 日志收集工具。

使用文档：[Log4App 使用说明](docs/LOG4APP_USER_GUIDE.md) · [业务流程图与 App 交互](docs/LOG4APP_FLOW.md)

V2.1 服务端重点：

- Flutter Desktop 单进程运行
- `dart:io HttpServer` 监听 `0.0.0.0:9090`。
- 自动检测局域网 IPv4。
- 根据当前 IP 动态生成采集端 App 扫码二维码。
- IP 改变后二维码自动刷新。
- 采集端 App `POST /api/device/ping` 后桌面登记并显示设备。
- 设备 90 秒内有通信显示“已连接”。
- App 日志 Multipart 上传。
- 最大上传包默认 500 MB。
- 上传后显示设备最后上传时间/大小。
- 最近日志列表。
- 保留 `GET /api/log/ping` 兼容旧测试。
- macOS Release 自动检查 Incoming Network entitlement。

## 二维码协议

二维码内容示例：

```json
{
  "type": "android-log-center",
  "serviceName": "Log4App",
  "version": 1,
  "scheme": "http",
  "host": "172.16.50.167",
  "port": 9090,
  "baseUrl": "http://172.16.50.167:9090"
}
```

采集端 App 扫码后应调用：

```text
POST {baseUrl}/api/device/ping
```

Ping 成功后桌面端会出现该设备。

> `android-log-center` 是 V2.1 已发布的协议兼容标识，不再作为产品品牌展示；
> 已接入的 Android 客户端无需因本次改名而调整扫码判断。

完整协议见：`docs/SERVER_API.md`。

## macOS 首次启动

```bash
cd Log4App
./scripts/bootstrap.sh
flutter run -d macos
```

第一次有采集端 App 访问时，macOS 防火墙可能提示是否允许入站连接，应选择允许。

验证：

```bash
curl http://127.0.0.1:9090/api/server/info
```

模拟设备连接：

```bash
curl -X POST \
  -H 'Content-Type: application/json' \
  -d '{"deviceId":"TEST_001","deviceName":"Test Device","appVersion":"1.0.0","platform":"Android","platformVersion":"14"}' \
  http://127.0.0.1:9090/api/device/ping
```

此时桌面“已登记设备”区域应出现 `Test Device` 并显示“已连接”。

## macOS Release

```bash
./scripts/build-macos.sh
```

输出：

```text
build/macos/Build/Products/Release/
```

V2.1 的 bootstrap 会把以下 entitlement 写入 Debug/Profile 和 Release：

```xml
<key>com.apple.security.network.server</key>
<true/>
```

这是因为应用本身需要监听 9090 接受采集端设备的入站 TCP 连接。

## 桌面平台构建说明

Flutter 桌面程序不能从 macOS 直接交叉编译 Windows 或 Linux 安装包：

- macOS 安装包在 macOS 构建；
- Windows 安装包在 Windows 10/11 x64 构建；
- Linux 安装包在 Linux x64/arm64 构建。

项目已经包含三个平台的 Runner。Dart 业务层共用同一份代码，`path_provider`、
局域网 IP 检测和“打开日志目录”均已覆盖 Windows/macOS/Linux。

应用图标的源文件是：

```text
packaging/branding/scan_upload_logo.svg
```

Windows `.ico`、Linux PNG 和 macOS AppIcon 均由该 SVG 生成。

## Windows 安装包

构建机需要：

- Windows 10/11 x64；
- Flutter stable，并启用 Windows Desktop；
- Visual Studio 2022（不是 VS Code），安装“使用 C++ 的桌面开发”；
- Inno Setup 6，用于生成 `.exe` 安装器。

检查环境：

```powershell
flutter doctor -v
flutter config --enable-windows-desktop
```

构建：

```powershell
.\scripts\build-windows.ps1
```

输出：

```text
dist/windows/Log4App-2.1.0-windows-x64-setup.exe
dist/windows/Log4App-2.1.0-windows-x64-portable.zip
```

安装器会创建开始菜单入口、可选桌面快捷方式，并为应用添加仅限“专用网络”的
TCP 9090 入站防火墙规则；卸载时会删除该规则。如果构建机暂未安装 Inno Setup，
脚本仍会先生成便携 ZIP，然后提示安装 Inno Setup。只需要便携 ZIP 时可执行：

```powershell
.\scripts\build-windows.ps1 -SkipInstaller
```

## Linux 安装包

推荐在 Ubuntu 22.04/24.04 或对应发行版的真实机器/虚拟机上构建。先安装 Flutter
Linux Desktop 所需工具：

```bash
sudo apt-get update
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
flutter config --enable-linux-desktop
flutter doctor -v
```

构建：

```bash
chmod +x scripts/build-linux.sh
./scripts/build-linux.sh
```

输出（x64 示例）：

```text
dist/linux/log4app_2.1.0_amd64.deb
dist/linux/Log4App-2.1.0-linux-x64.tar.gz
```

安装并启动 `.deb`：

```bash
sudo apt install ./dist/linux/log4app_2.1.0_amd64.deb
log4app
```

也可以从桌面应用菜单启动。如果系统启用了 UFW，并且采集端设备无法连接，
需要显式允许同一局域网访问 9090，例如：

```bash
sudo ufw allow from 192.168.0.0/16 to any port 9090 proto tcp
```

请根据部署现场的真实网段收窄该规则，不要无条件开放到公网。

## 日志存储

使用 Flutter `path_provider` 的 Application Documents Directory，再创建：

```text
Log4AppLogs/
└── DEVICE_ID/
    └── yyyy-MM-dd/
        └── timestamp_appVersion_originalName.zip
```

首次启动时，如果只检测到旧版 `AndroidDeviceLogs` 目录，Log4App 会优先将它迁移为
`Log4AppLogs`；如果系统阻止重命名，则继续使用旧目录，避免已有日志不可见。

这样 macOS App Sandbox 下也能稳定写入，而不是硬编码真实 `~/Documents`。

桌面程序提供“打开日志目录”按钮。

## 主要 API

```text
GET  /api/server/info
GET  /api/log/ping        # V2.0 兼容
POST /api/device/ping
GET  /api/device/list
POST /api/log/upload
GET  /api/log/list
```

## 依赖

```yaml
mime: ^2.0.0
path: ^1.9.0
path_provider: ^2.1.4
qr_flutter: ^4.1.0
```

## 服务端一键冒烟测试

桌面程序运行后执行：

```bash
./scripts/test-server.sh
```

如果测试的是另一台电脑上的服务端：

```bash
./scripts/test-server.sh http://172.16.50.167:9090
```

脚本会依次验证：

```text
/api/server/info
/api/device/ping
/api/log/upload
/api/device/list
```

全部成功后输出 `PASS`，同时桌面端会出现一台 `Smoke Test Device` 设备和一条测试日志。
