# 当前进度与交接

更新时间：2026-10-29 17:12（北京时间）。

## 当前任务

将包含包子漫画网站验证功能的 Aidoku 打包为 IPA。尚未产出 IPA，云端构建配置已准备，用户已明确授权将当前修改提交、推送到公开仓库的独立构建分支，正在准备首次推送。

## 已完成与验证

- 手动网站验证、Cookie 桥接、自动识别、会话合并、取消与超时、一次 GET/HEAD 重放已实现，详见 `WEBSITE_VERIFICATION_PROGRESS.md`。
- Swift 6.2.4 独立测试 19 组通过；隔离 iOS 18.5 模拟器中的实际验证页和原生列表 API 检查通过。
- 本机仍为 macOS 15.5、Xcode 16.4，独立 Swift 升级不能补齐当前工程需要的新 iOS SDK，无法在此环境生成完整安装包。
- 新增 `.github/workflows/build-verification-ipa.yml`：使用 GitHub 托管 macos-26 环境，先测试，再编译设备 archive、生成未签名 IPA 及 SHA-256，保留 Actions 产物 7 天；失败上传构建日志。
- 现有 nightly 工作流的 runner 为 `xcode-27`，本轮不更改原工作流，不混用模拟器测试壳作为真实安装包。

## 发布状态与下一步

- 尚未提交、推送或发布；尚无构建成功链接。
- 拟使用分支：`codex/website-verification-ipa`。已获得推送授权；提交当前功能、测试、构建配置及交接，推送触发构建，处理完整编译错误，下载并检查真正的 IPA。
- 产物为未签名 IPA，供用户用侧载工具重新签名安装；不会发布 App Store 或创建公开 Release。
- 本机无 GitHub CLI 或已配置的 GitHub API token，后续可能需通过已登录浏览器检查 Actions 与下载产物。
- 图源仓库和 `public/` 无需同步；设备端完整阅读及自动流程仍待安装后验收。

推送前配置验证：构建工作流 YAML 解析通过，差异空白检查通过；完整设备 archive 将由云端执行。
