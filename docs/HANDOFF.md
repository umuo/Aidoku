# 当前进度与交接

更新时间：2026-10-29 17:29（北京时间）。

## 当前状态

包含包子漫画网站验证功能的完整 Aidoku 已通过云端设备归档，IPA 已下载并校验。当前构建分支为 `codex/website-verification-ipa`，`main` 未改动，未创建 Release。

- 产物对应源码提交：`76f634987d5f2a6ffffcda6d7fc36c1b765610a6`。
- [已成功的 Xcode 27 构建](https://github.com/umuo/Aidoku/actions/runs/40848173879)，原有 nightly 工作流，耗时约 6 分 35 秒。
- IPA：`build/Aidoku-website-verification-76f6349-unsigned.ipa`，14,594,485 字节，版本 0.9 / build 4，Bundle ID `app.aidoku.Aidoku`，最低 iOS 15.0。
- SHA-256：`2fba498076bd83070870c6530b37c911003d2bc792e27f4b225d50dbacbfa185`。本地同时保存 `.ipa.sha256` 与 `.ipa.json` 校验记录；`build/` 不纳入 Git。
- ZIP 完整性、Actions 外层产物摘要、arm64 Mach-O / LC_BUILD_VERSION 的 iOS 设备平台、验证功能存在性均通过。产物未签名，需要侧载工具重新签名；尚未完成真实设备安装和完整阅读验收。

## 已完成与环境要求

- 手动验证、Cookie 桥接、自动识别、会话合并、取消/超时、一次 GET/HEAD 重放均已实现。自动流程须同设备先手动通过一次列表 API 检查才激活。
- 独立测试 19 组在本地和新增云端测试步骤均通过；隔离 iOS 18.5 模拟器中，真实验证页及 URLSession 列表检查通过。详见 `WEBSITE_VERIFICATION_PROGRESS.md`。
- 本机仍为 macOS 15.5、Xcode 16.4；Swift 6.2.4 独立工具链已安装，但不能补齐完整 SDK。
- 首次新增构建流程使用 Xcode 26.6，19 组测试通过，但完整归档因上游 `ContentBuilder`、`submitTaskRequest` 等 Xcode 27 接口失败：[失败记录](https://github.com/umuo/Aidoku/actions/runs/40848173888)。同提交的原有 Xcode 27 流程成功，无需修改业务源码降级兼容。
- 本轮修正 `.github/workflows/build-verification-ipa.yml`，与已验证的原有流程一致使用 `xcode-27`，继续测试、归档设备 App、打包未签名 IPA 与校验和；修正后的新流程结果尚未确认，不声称已成功。
- 公开产物来自 Actions artifact，不是 GitHub Release；图源仓库及其 `public/` 无需同步。

## 后续待办

1. 用户重新签名安装 IPA 后，验证包子漫画 1 v6 的列表、搜索、详情、章节、首图及自动验证到期流程。
2. 如需后续新包，在当前分支推送触发 Xcode 27 构建，或手动运行 IPA 工作流。保持源码提交与下载产物对应。
3. 下一次推送前继续更新本交接。不要将隔离测试壳或模拟器二进制混作真实 IPA。
