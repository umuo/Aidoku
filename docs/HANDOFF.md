# 当前进度与交接

更新时间：2026-10-29 17:33（北京时间）。

## 当前状态

用户已反馈本轮交付 IPA 真机测试可用。开发工作独立保存在新分支 `codex/website-verification-dev`，从已推送的构建分支 `codex/website-verification-ipa` 接续；按用户要求不合并 `main`，不创建 Release。

- 产物对应源码提交：`76f634987d5f2a6ffffcda6d7fc36c1b765610a6`。
- [已成功的 Xcode 27 构建](https://github.com/umuo/Aidoku/actions/runs/40848173879)，原有 nightly 工作流，耗时约 6 分 35 秒。
- IPA：`build/Aidoku-website-verification-76f6349-unsigned.ipa`，14,594,485 字节，版本 0.9 / build 4，Bundle ID `app.aidoku.Aidoku`，最低 iOS 15.0。
- SHA-256：`2fba498076bd83070870c6530b37c911003d2bc792e27f4b225d50dbacbfa185`。本地同时保存 `.ipa.sha256` 与 `.ipa.json` 校验记录；`build/` 不纳入 Git。
- ZIP 完整性、Actions 外层产物摘要、arm64 Mach-O / LC_BUILD_VERSION 的 iOS 设备平台、验证功能存在性均通过。交付产物未签名，需要侧载工具重新签名；用户已确认真机测试可用。该反馈未逐项描述自动过期、并发和网络切换场景，不把这些场景单独记为设备验收通过。

## 已完成与环境要求

- 手动验证、Cookie 桥接、自动识别、会话合并、取消/超时、一次 GET/HEAD 重放均已实现。自动流程须同设备先手动通过一次列表 API 检查才激活。
- 独立测试 19 组在本地和新增云端测试步骤均通过；隔离 iOS 18.5 模拟器中，真实验证页及 URLSession 列表检查通过。详见 `WEBSITE_VERIFICATION_PROGRESS.md`。
- 本机仍为 macOS 15.5、Xcode 16.4；Swift 6.2.4 独立工具链已安装，但不能补齐完整 SDK。
- 首次新增构建流程使用 Xcode 26.6，19 组测试通过，但完整归档因上游 `ContentBuilder`、`submitTaskRequest` 等 Xcode 27 接口失败：[失败记录](https://github.com/umuo/Aidoku/actions/runs/40848173888)。同提交的原有 Xcode 27 流程成功，无需修改业务源码降级兼容。
- 此前修正 `.github/workflows/build-verification-ipa.yml`，与已验证的原有流程一致使用 `xcode-27`，继续测试、归档设备 App、打包未签名 IPA 与校验和；修正后的[新流程正在运行](https://github.com/umuo/Aidoku/actions/runs/40850030602)，尚无最终结果，不声称已成功。
- 公开产物来自 Actions artifact，不是 GitHub Release；图源仓库及其 `public/` 无需同步。

## 本轮变更与验证

- 用户明确要求保留独立开发分支并允许推送；新建 `codex/website-verification-dev`，保留原构建分支，`main` 仍为 `ceee58b2`。
- 将用户真机测试可用反馈同步到交接、实现方案与实施进度。没有修改 App 功能、图源或安装包，不重跑与纯文档变更无关的测试。
- 推送前执行文档差异与空白检查；已有自动化、模拟器和云端构建证据按前文保留。当前提交和开发分支将在本轮推送，不提前声明推送结果。

## 后续待办

无当前阻塞或必须继续的功能待办。后续功能迭代使用 `codex/website-verification-dev`，未经用户要求不合并 `main`。自动验证到期及其他未单独反馈的设备场景可在后续迭代补充验证。
