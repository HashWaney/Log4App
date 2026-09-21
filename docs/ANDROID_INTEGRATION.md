# Android 接入示例

## 1. 权限

```xml
<uses-permission android:name="android.permission.INTERNET" />

<application
    android:usesCleartextTraffic="true"
    ... />
```

局域网 V2 默认使用 HTTP。若以后上线公网，再切 HTTPS。

## 2. OkHttp Multipart 上传

```kotlin
suspend fun uploadLogs(
    serverBaseUrl: String,
    zipFile: File,
    deviceId: String,
    appVersion: String,
): String = withContext(Dispatchers.IO) {
    val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .writeTimeout(10, TimeUnit.MINUTES)
        .readTimeout(2, TimeUnit.MINUTES)
        .build()

    val body = MultipartBody.Builder()
        .setType(MultipartBody.FORM)
        .addFormDataPart("deviceId", deviceId)
        .addFormDataPart("appVersion", appVersion)
        .addFormDataPart("platform", "Android")
        .addFormDataPart("platformVersion", Build.VERSION.RELEASE)
        .addFormDataPart(
            "file",
            zipFile.name,
            zipFile.asRequestBody("application/zip".toMediaType()),
        )
        .build()

    val request = Request.Builder()
        .url("$serverBaseUrl/api/log/upload")
        .post(body)
        .build()

    client.newCall(request).execute().use { response ->
        if (!response.isSuccessful) {
            error("Upload failed: ${response.code} ${response.body?.string()}")
        }
        response.body?.string().orEmpty()
    }
}
```

服务器地址例如：

```text
http://192.168.31.52:9090
```

## 3. Ping

```text
GET http://192.168.31.52:9090/api/log/ping
```

## 4. Multipart 字段

| 字段 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| file | File | 是 | ZIP 或其他日志包 |
| deviceId | String | 是 | 稳定设备标识 |
| appVersion | String | 否 | App 版本 |
| platform | String | 否 | 平台名称；Android 客户端填写 `Android` |
| platformVersion | String | 否 | 系统版本 |

V2 最大单文件默认 500 MB。
