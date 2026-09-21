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
    digest = hmac.new(
        secret.encode("utf-8"),
        string_to_sign,
        hashlib.sha256,
    ).digest()

    sign = base64.b64encode(digest).decode("utf-8")
    separator = "&" if "?" in webhook else "?"

    return (
        f"{webhook}{separator}"
        f"{urllib.parse.urlencode({'timestamp': timestamp, 'sign': sign})}"
    )


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
        print(
            "DINGTALK_WEBHOOK is not configured; "
            "skipping DingTalk notification."
        )
        return

    is_release = env("IS_RELEASE").lower() == "true"

    results = {
        "Windows x64": env("WINDOWS_RESULT", "unknown"),
        "macOS ARM64": env("MACOS_RESULT", "unknown"),
        "Linux x64": env("LINUX_RESULT", "unknown"),
        "GitHub Release": env("RELEASE_RESULT", "unknown"),
    }

    # 三个平台构建结果始终参与 CI 成败判断
    required_results = [
        results["Windows x64"],
        results["macOS ARM64"],
        results["Linux x64"],
    ]

    # 只有 Tag Release 时才要求 GitHub Release 成功
    if is_release:
        required_results.append(results["GitHub Release"])

    succeeded = all(result == "success" for result in required_results)

    status_text = "成功" if succeeded else "失败"
    status_icon = "✅" if succeeded else "❌"
    title = f"{status_icon} Log4App CI {status_text}"

    repository = env("REPOSITORY")
    event_name = env("EVENT_NAME")
    ref_name = env("REF_NAME")
    commit_sha = env("COMMIT_SHA")
    actor = env("ACTOR")
    run_url = env("RUN_URL")
    release_url = env("RELEASE_URL")

    short_sha = commit_sha[:7]

    result_lines = "\n".join(
        f"- {name}：{display_result(result)}"
        for name, result in results.items()
    )

    # 链接区域
    link_lines = []

    if run_url:
        link_lines.append(
            f"[🔍 查看 GitHub Actions 运行详情]({run_url})"
        )

    # 只有正式 Tag Release 才显示安装包下载地址
    if is_release and release_url:
        link_lines.append(f"\n")
        link_lines.append(
            f"[📦 下载 {ref_name} Release 安装包]({release_url})"
        )

    markdown_lines = [
        f"### {title}",
        "",
        f"- 仓库：{repository}",
        f"- 触发：{event_name} / {ref_name}",
        f"- 提交：`{short_sha}`",
        f"- 操作者：{actor}",
        "",
        result_lines,
    ]

    if link_lines:
        markdown_lines.extend(
            [
                "",
                "### 🔗 相关链接",
                "",
                *link_lines,
            ]
        )

    markdown = "\n".join(markdown_lines)

    payload = {
        "msgtype": "markdown",
        "markdown": {
            "title": title,
            "text": markdown,
        },
    }

    request = urllib.request.Request(
        signed_webhook(
            webhook,
            env("DINGTALK_SECRET"),
        ),
        data=json.dumps(
            payload,
            ensure_ascii=False,
        ).encode("utf-8"),
        headers={
            "Content-Type": "application/json; charset=utf-8"
        },
        method="POST",
    )

    with urllib.request.urlopen(
        request,
        timeout=20,
    ) as response:
        response_body = json.loads(
            response.read().decode("utf-8")
        )

    if response_body.get("errcode") != 0:
        raise RuntimeError(
            "DingTalk notification failed: "
            f"{response_body.get('errmsg', response_body)}"
        )

    print("DingTalk notification sent successfully.")


if __name__ == "__main__":
    main()