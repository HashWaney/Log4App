# Log4App V2.1 — Server API

默认监听：`0.0.0.0:9090`

所有接口均为局域网 HTTP。V2.1 协议版本：`1`。

## 1. 二维码协议

桌面端二维码内容不是裸 URL，而是 JSON：

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

采集端 App 扫码后应校验：

- `type == android-log-center`（V2.1 兼容标识）
- `version == 1`
- `scheme == http`
- `host` 非空
- `port` 合法

然后使用 `baseUrl` 调用 `POST /api/device/ping`。

---

## 2. GET /api/server/info

用于读取服务端能力和当前监听信息。

响应：

```json
{
  "success": true,
  "serviceName": "Log4App",
  "serviceType": "android-log-center",
  "protocolVersion": 1,
  "serverVersion": "2.1.0",
  "port": 9090,
  "addresses": ["172.16.50.167"],
  "onlineDeviceCount": 1,
  "time": "2026-09-20T16:30:00.000"
}
```

---

## 3. GET /api/log/ping

兼容 V2.0 的简单连通性接口。

V2.1 采集端 App 应优先使用 `/api/device/ping`，因为只有设备 Ping 才会在桌面端登记设备。

---

## 4. POST /api/device/ping

Content-Type：`application/json`

请求：

```json
{
  "deviceId": "ROBOT_001",
  "deviceName": "N2N-001",
  "appVersion": "3.2.1",
  "platform": "Android",
  "platformVersion": "14"
}
```

`deviceId` 必填，其余字段可选。

成功响应：

```json
{
  "success": true,
  "message": "device connected",
  "serviceName": "Log4App",
  "serviceType": "android-log-center",
  "protocolVersion": 1,
  "serverVersion": "2.1.0",
  "serverTime": "2026-09-20T16:30:00.000",
  "device": {
    "deviceId": "ROBOT_001",
    "deviceName": "N2N-001",
    "appVersion": "3.2.1",
    "platform": "Android",
    "platformVersion": "14",
    "androidVersion": "14",
    "lastSeen": "2026-09-20T16:30:00.000",
    "lastUploadAt": null,
    "lastUploadBytes": 0,
    "online": true
  }
}
```

桌面端以最后通信时间计算设备状态。V2.1 默认 90 秒内有通信显示为“已连接”。

---

## 5. POST /api/log/upload

推荐使用 `multipart/form-data`。

字段：

| 字段 | 必填 | 含义 |
|---|---:|---|
| `deviceId` | 是 | 稳定设备标识 |
| `deviceName` | 否 | 设备显示名称 |
| `appVersion` | 否 | 采集端 App 版本 |
| `platform` | 否 | 平台名称，如 Android、iOS、Flutter |
| `platformVersion` | 否 | 平台或系统版本 |
| `androidVersion` | 否 | 旧 Android 客户端兼容字段；新接入请使用 `platformVersion` |
| `file` | 是 | ZIP/日志文件 |

最大上传大小默认为 500 MB。

成功后服务端会：

1. 保存日志到本地；
2. 更新上传计数；
3. 更新该设备 `lastSeen`；
4. 更新 `lastUploadAt/lastUploadBytes`；
5. 桌面 UI 最迟约 2 秒内刷新。

---

## 6. GET /api/device/list

返回本次桌面程序运行期间登记的设备。

设备连接状态目前保存在内存中，程序重启后重新通过设备 Ping 登记；日志文件本身持久化保存。

---

## 7. GET /api/log/list

返回电脑端最近日志记录。

---

## 8. curl 验证

### Server info

```bash
curl http://127.0.0.1:9090/api/server/info
```

### 模拟设备 Ping

```bash
curl -X POST \
  -H 'Content-Type: application/json' \
  -d '{"deviceId":"TEST_001","deviceName":"Test Device","appVersion":"1.0.0","platform":"Android","platformVersion":"14"}' \
  http://127.0.0.1:9090/api/device/ping
```

### 模拟日志上传

```bash
curl -X POST \
  -F 'deviceId=TEST_001' \
  -F 'deviceName=Test Device' \
  -F 'appVersion=1.0.0' \
  -F 'platform=Android' \
  -F 'platformVersion=14' \
  -F 'file=@./test.zip' \
  http://127.0.0.1:9090/api/log/upload
```
