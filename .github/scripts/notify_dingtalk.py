#!/usr/bin/env python3

import base64
import hashlib
import hmac
import json
import os
import time
import urllib.parse
import urllib.request


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def signed_webhook(webhook: str, secret: str) -> str:
    if not secret:
        return webhook

    timestamp = str(round(time.time() * 1000))
    string_to_sign = f"{timestamp}\n{secret}".encode("utf-8")
    digest = hmac.new(secret.encode("utf-8"), string_to_sign, hashlib.sha256).digest()
    sign = base64.b64encode(digest).decode("utf-8")
    separator = "&" if "?" in webhook else "?"
    return f"{webhook}{separator}{urllib.parse.urlencode({'timestamp': timestamp, 'sign': sign})}"


def display_result(value: str) -> str:
    labels = {
        "success": "✅ 成功",
        "failure": "❌ 失败",
        "cancelled": "⚪ 已取消",
        "skipped": "⏭️ 已跳过",
    }
    return labels.get(value, value or "未知")


def main() -> None:
    webhook = env("DINGTALK_WEBHOOK")
    if not webhook:
        print("DINGTALK_WEBHOOK is not configured; skipping DingTalk notification.")
        return

    results = {
        "Windows x64": env("WINDOWS_RESULT", "unknown"),
        "macOS ARM64": env("MACOS_RESULT", "unknown"),
        "Linux x64": env("LINUX_RESULT", "unknown"),
        "GitHub Release": env("RELEASE_RESULT", "unknown"),
    }
    required_results = list(results.values())[:3]
    if env("IS_RELEASE").lower() == "true":
        required_results.append(results["GitHub Release"])

    succeeded = all(result == "success" for result in required_results)
    status_text = "成功" if succeeded else "失败"
    status_icon = "✅" if succeeded else "❌"
    title = f"{status_icon} Log4App CI {status_text}"
    short_sha = env("COMMIT_SHA")[:7]

    result_lines = "\n".join(
        f"- {name}：{display_result(result)}" for name, result in results.items()
    )
    markdown = "\n".join(
        [
            f"### {title}",
            "",
            f"- 仓库：{env('REPOSITORY')}",
            f"- 触发：{env('EVENT_NAME')} / {env('REF_NAME')}",
            f"- 提交：`{short_sha}`",
            f"- 操作者：{env('ACTOR')}",
            "",
            result_lines,
            "",
            f"[查看 GitHub Actions 运行详情]({env('RUN_URL')})",
        ]
    )
    payload = {
        "msgtype": "markdown",
        "markdown": {
            "title": title,
            "text": markdown,
        },
    }
    request = urllib.request.Request(
        signed_webhook(webhook, env("DINGTALK_SECRET")),
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={"Content-Type": "application/json; charset=utf-8"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        response_body = json.loads(response.read().decode("utf-8"))

    if response_body.get("errcode") != 0:
        raise RuntimeError(
            f"DingTalk notification failed: {response_body.get('errmsg', response_body)}"
        )
    print("DingTalk notification sent successfully.")


if __name__ == "__main__":
    main()
