# Log4App 与采集端 App 业务流程

本图描述推荐的扫码接入与日志上传协议流程。Log4App 运行在电脑上，采集端 App 运行在需要导出日志的设备上；两端须处于可互访的局域网。具体采集端按钮名称以其实际版本为准。接口细节见 [Server API](SERVER_API.md)。

## 业务流程图

```mermaid
flowchart LR
    subgraph Desktop["电脑端：Log4App"]
        Start["启动应用，自动监听 TCP 9090"] --> Address{"检测到局域网 IPv4？"}
        Address -- "否" --> Wait["显示等待网络地址"]
        Wait --> Address
        Address -- "是" --> QR["生成含 baseUrl 的二维码"]
        Registered["登记设备，更新最后通信时间"]
        Save["按设备和日期保存日志包"] --> Refresh["更新上传统计与最近日志"]
    end

    subgraph Client["采集端 App"]
        Scan["扫码并解析服务地址"] --> Ping["POST /api/device/ping"]
        PingResult{"Ping 成功？"}
        PingResult -- "否" --> Check["检查服务状态、网络和地址后重试"]
        Collect["采集并打包日志"] --> Upload["POST /api/log/upload"]
        UploadResult{"请求有效且文件未超限？"}
        UploadResult -- "否" --> Retry["提示失败，可重试上传"]
        Done["显示上传成功"]
    end

    QR --> Scan
    Ping --> PingResult
    PingResult -- "是" --> Registered --> Collect
    Upload --> UploadResult
    UploadResult -- "是" --> Save
    Refresh --> Done
```

## 请求时序

```mermaid
sequenceDiagram
    actor User as 现场人员
    participant App as 采集端 App
    participant Server as 电脑端 Log4App
    participant Disk as 电脑本地日志目录

    User->>Server: 启动应用
    Server-->>User: 显示服务状态、局域网 IP 和二维码
    User->>App: 扫描二维码
    App->>App: 解析 JSON，取得 baseUrl
    App->>Server: POST /api/device/ping（含 deviceId）
    Server-->>App: success: true，返回设备信息
    Server-->>User: 已登记设备；最近 90 秒有通信显示已连接
    User->>App: 发起日志上传
    App->>App: 生成日志包
    App->>Server: POST /api/log/upload（multipart：file、deviceId 等）
    Server->>Disk: 保存到设备与日期目录
    Disk-->>Server: 保存完成
    Server-->>App: success: true，返回日志记录
    Server-->>User: 刷新上传统计与最近日志
```

扫码取得地址后，推荐先调用设备 Ping，方便桌面端立即显示设备。上传接口本身也会登记或更新设备；旧接口 `GET /api/log/ping` 只检查连通性，不会登记设备。设备列表和本次上传统计保存在当前运行会话中，日志文件会持久化到电脑本地。
