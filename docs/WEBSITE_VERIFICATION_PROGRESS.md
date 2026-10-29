# 网站验证实施进度

日期：2026-10-29（北京时间）。代码基线：`ceee58b2`。方案见 [实现方案](WEBSITE_VERIFICATION_PLAN.md)。

## 当前交付

手动验证与第二阶段自动恢复代码已接入。自动流程需要该设备先在同一站点、同一 UA 下通过一次手动列表 API 检查才会激活；已通过隔离 iOS 模拟器中的手动界面与原生列表探测，并完成 Xcode 27 云端完整设备构建；用户已确认交付 IPA 真机测试可用。

用户入口：包子漫画 1 的源页面右上角菜单 →“网站验证”，或源设置 →“网站验证”。旧界面也提供盾牌按钮。完成网页流程后点击“完成并重试”；只有原生列表 API 返回正确 JSON 结构时才关闭页面并刷新当前源。验证窗口显示当前主机，支持重载、关闭、取消和会话超时。

实现内容：

- 系统 WKWebView 持久化存储与正常 JavaScript，初始化前导入站点 Cookie；保留更近的 WebKit 会话值。
- 从实际 WebView 存储同步完整 Cookie 到原生仓库，传播删除，保留路径、Secure 和过期信息，限定本站域名。
- 新旧网络入口统一构建 Cookie 头，使用系统按 URL 筛选的 Cookie，并避免新旧会话值重复追加。同名有效存储值优先于请求残留值，保留不同路径的有效 Cookie。
- 有效 UA 一致后才开始验证；通过 URLSession 发出只读列表探测，不递归调用 WASM 或自动验证处理器。
- 探测要求成功状态、正确主机/路径、JSON 类型与 `items` 数据结构，明确排除网页 200、挑战 JSON 及错误对象。不会把无效响应变成空列表成功。
- 验证成功的刷新事件包含 sourceKey，当前源的首页与搜索响应，其他源忽略；原有无 sourceKey 的全局刷新保持兼容。
- 清理源缓存时等待 WebKit 数据删除完成，再继续清理和刷新。
- 增加英文、简体中文和繁体中文文案；其他语言沿用工程既有英文回退机制。

关键文件：

- `Aidoku/Core/Sources/Verification/`：站点策略、Cookie 头构建和桥接。
- `Aidoku/Features/Source/Verification/`：验证界面、源适配和 SwiftUI 包装。
- `Aidoku/Core/Sources/Legacy/Wasm/Imports/WasmNet.swift`、`Aidoku/Extensions/AidokuRunner/AidokuRunner.swift`：请求 Cookie 构建接入。
- `Aidoku/Features/Source/` 下现有源页面、设置、首页和搜索：入口、清理与定向刷新。
- `AidokuTests/WebsiteVerificationTests.swift`、`AidokuTests/VerificationCookieBridgeTests.swift`：测试。
- `tools/test-website-verification.py`：独立运行实际模块测试，无需解析 App 的全部第三方包。

## 初期验证记录与环境限制（云端构建前）

- 重新读取真实公开 API，响应字段确认为 `error: challenge_required` 与 `challenge_url`；没有运行验证脚本或保存真实站点凭据。
- Foundation 核心测试 5 组通过：源/主机边界、挑战识别和非法入口、API 成功判断、Cookie 旧值去重、路径/Secure/域名约束。
- 真实 WebKit 存储桥接测试通过，完整套件 6 组通过：保留浏览器较新 Cookie、限定域名、保留 Secure/路径/有效期，并传播网页删除。
- 新增验证页、Cookie 桥和策略通过 iOS 15 Simulator 目标的 Swift 类型检查。仅对既有 UserAgentProvider 使用同签名隔离替身，并包含工程真实本地化辅助函数；该结果不代表整个 App 构建通过。
- 变更 Swift 文件通过语法检查；三种语言的 `.strings` 通过 `plutil -lint`。
- 完整 Xcode 依赖解析受阻：本机 Xcode 16.4 的 Swift 为 6.1，仓库锁定的 `hoshidicts` 包声明 Swift tools 6.2。未降低依赖要求、变更锁文件、关闭工程检查或修改签名配置。
- 本机未发现 SwiftLint，可用时仍需运行工程现有规则。未声称通过 SwiftLint 或 Sonar。
- 尚无安装包、设备恢复访问证据、浏览器环境可迁移性结论、Cloudflare 设备回归或图片域验证结论。

独立测试（macOS、Swift 6.0+）：

```sh
python3 tools/test-website-verification.py
```

该命令在临时 Swift 包中编译仓库实际模块与测试，使用随机标识的原生 Cookie 仓库和非持久化 WebKit 存储，不读取用户浏览器的 Cookie。测试失败会以非零状态退出。WebKit 存储测试需要可运行系统 WebKit 服务的 macOS 环境。

## 下一步

1. 使用带 Swift 6.2 或以上且兼容工程的 Xcode，解析锁定依赖，完成整 App 构建与测试，保持依赖锁文件不变。
2. 安装到设备，打开包子漫画 1 v6 →“网站验证”→完成网页验证→“完成并重试”。逐项记录列表、搜索、详情、章节和首图，以及取消、重开、缓存清理和重启后的行为。
3. 若网页通过但原生仍失败，先检查 Cookie 头、URL 作用域、UA 与数据存储，再做同源 WebKit 请求 spike；不直接将全部请求切换到 WebView。
4. 手动链路通过后真机验收自动流程：同域并发、取消重开、前后台切换、验证过期、一次 GET/HEAD 重放；完整阅读继续按列表、搜索、章节和图片分别记录。

尚未提交、推送或发布；图源仓库及其安装包未修改。


## Swift 工具链升级记录

2026-10-29（北京时间）：已按用户要求安装 Swift.org 官方 Swift 6.2.4 用户级工具链。安装包通过 Apple 开发者签名与公证校验，签名方为 `Swift Open Source (V9AUD2URP3)`；保留原 Xcode 和命令行工具。终端启动配置已备份并配置优先使用新工具链，新登录/交互终端均确认 `swift --version` 为 6.2.4。

使用 Swift 6.2.4 重新执行 `python3 tools/test-website-verification.py`，6 组测试全部通过，包括真实 WebKit Cookie 存储桥接。工程锁文件未修改。

整 App 构建限制仍存在：在 Xcode 16.4 中通过 `-toolchain` 及 `TOOLCHAINS` 显式选择新工具链后，Xcode 包解析仍报告内置 Swift tools 6.1，并出现 legacy driver 调用错误。独立工具链升级不等于 Xcode 的 SwiftPM 与 iOS SDK 已升级，不据此宣称已解除整 App 构建阻塞。

本机系统为 macOS 15.5；[Apple 兼容表](https://developer.apple.com/xcode/system-requirements)列出的 Xcode 26.3 支持 macOS 15.6 起，包含 Swift 6.2.3 与 iOS 26.2 SDK。后续需先升级到兼容的 macOS，再升级完整 Xcode。当前未升级操作系统、未替换 Xcode，也未生成安装包。


## 自动恢复代码接入记录

2026-10-29（北京时间）：继续使用已安装的 Swift 6.2.4 完成第二阶段代码。当前会话复核仍为 macOS 15.5、Xcode 16.4、iOS 18.5 SDK；独立 Swift 已升级，完整 Xcode 并未升级。沿用前述整 App 构建限制，不将模块类型检查描述为整 App 编译成功。

新增与接入：

- `WebsiteVerificationService` 接入新 SDK requestHandler 与旧 SDK WasmNet，明确匹配本站 `challenge_required` 及受信任的 `challenge_url`，保留现有 Cloudflare 路径。
- `VerificationEligibility` 记录首次手动探测成功的站点及 UA；未经该设备验证时返回“请先打开网站验证”，不会自动弹窗。清理源缓存会重置这个启用条件；记录不等于当前 Cookie 有效。
- `VerificationSessionQueue` 按主机与 UA 合并等待者，其他会话串行排队。取消单个等待请求保留其他请求；取消最后一个等待者会取消验证。排队中的取消不会展示页面。
- `VerificationRequestRecovery` 从原始请求重建 Cookie 与 UA，只对 GET/HEAD 执行一次重放。POST 不重放，取消或验证失败不发送原请求，重试仍遇 403 则明确失败。
- 验证失败/取消后冷却 60 秒，成功后的 10 秒内晚到的旧挑战只重试一次，避免刚关闭又弹窗；重试仍受阻时撤销成功宽限并进入冷却。
- `WebsiteVerificationPresenter` 只在 App 前台且当前展示该源页面时自动弹出，其他页面/后台返回需验证状态。进入后台时释放自动等待；独立 5 分钟截止任务保证即使窗口未成功展示也不永久等待。
- 手动与自动共用一个验证页。自动成功后恢复挂起请求，不再额外刷新同一列表；手动成功仍按源定向刷新。失败或取消不依赖关闭动画结束才释放请求。

验证结果：Swift 6.2.4 独立测试共 19 组全部通过，涵盖原有 Cookie 与策略测试，以及合并、单请求取消、排队取消、最后一个等待者取消、共享验证失败释放全部等待者、异域串行、超时错误与冷却、晚到响应、防重复窗口、设备启用条件、HEAD 原请求保留、POST 禁止重放、取消不重放和受阻仅重试一次。测试使用可控验证闭包与传输闭包，不替代真实站点设备测试。

新增核心模块、验证 UI 和服务接入层通过 iOS 15 Simulator 目标类型检查（外部 App/Runner 类型使用同签名隔离替身）；变更源码语法检查和三种语言字符串校验通过。未对整个工程做设备级运行验证，也未发布安装包。隔离 UIKit 运行检查见下文。


## 隔离 iOS 模拟器运行检查

2026-10-29（北京时间）：使用 iOS 18.5 / iPhone 16 的独立临时模拟器，将实际 `WebsiteVerificationViewController`、策略、Cookie 桥接、启用条件模块与工程实际 `UserAgentProvider` 编译链接为隔离测试壳。测试壳只替代 App 入口与日志设施，不依赖完整工程第三方包。

实际观察：

1. 验证页面成功展示，主机、关闭、重载与“完成并重试”按钮显示正常，真实包子漫画主页和封面能够加载。
2. 点击 App 的“完成并重试”后显示正在检查状态，经过实际 URLSession 列表 API 检查，收到有效列表 JSON，页面自动关闭并发出按源刷新事件。
3. 测试壳通过该刷新事件写入 `native-api-verified` 标记，已单独读取确认。未读取或导出真实 Cookie 值，未人工操作验证码。

边界：这是隔离测试壳中的真实网页与原生 API 结果，未做该模拟器内验证前 403 与验证后成功的同环境对照，不能据此断言所有环境均可迁移验证状态。没有运行完整 Aidoku、自动弹窗、搜索/章节/图片链路，也不能替代用户设备验收。完整工程依然受旧 Xcode/SDK 限制。


## 完整 IPA 构建完成

2026-10-29（北京时间）：用户授权推送到独立构建分支，提交 `76f6349` 的[原有 Xcode 27 nightly 构建成功](https://github.com/umuo/Aidoku/actions/runs/40848173879)。完整 IPA 已下载到 `build/Aidoku-website-verification-76f6349-unsigned.ipa`；版本 0.9 / build 4，14,594,485 字节，最低 iOS 15.0，未签名。ZIP、Actions 产物摘要、arm64 真机平台和验证功能存在性均通过；SHA-256 为 `2fba498076bd83070870c6530b37c911003d2bc792e27f4b225d50dbacbfa185`。

同提交新增流程在 Xcode 26.6 下测试 19 组通过，但因上游 Xcode 27 接口归档失败；已将新流程 runner 修正为 `xcode-27`，无需改动业务源码。当前安装包取自已成功的原有流程，不能把失败流程描述为成功。产物需要用户重新签名安装，设备阅读与自动验证尚未验收。


## 用户真机反馈与开发分支

2026-10-29（北京时间）：用户明确反馈“真机测试了是可以的”，并要求不合并 `main`、单独建立开发分支并推送。本轮从原构建分支接续创建 `codex/website-verification-dev`；保留原构建分支与已验证 IPA，业务代码和安装包未改动。

当前可用性结论包含用户真机反馈。用户没有逐项说明自动过期、并发、取消和网络切换结果，这些设备边界保留原测试范围，不扩大反馈含义。早期小节中的待验收/未推送描述为当时状态，以本节和 `HANDOFF.md` 的当前记录为准。
