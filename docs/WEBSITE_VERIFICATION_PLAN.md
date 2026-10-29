# 网站验证实现方案：手动验证 → 自动识别

日期：2026-10-29（北京时间）
状态：手动与自动恢复代码已接入，自动功能在设备首次手动验证成功后激活；验证结果与剩余事项见 [实施进度](WEBSITE_VERIFICATION_PROGRESS.md)；用户已反馈交付 IPA 真机测试可用，后续使用独立开发分支 `codex/website-verification-dev`，不合并 `main`。
代码基线：Aidoku `main`，`ceee58b2`；AidokuRunner 锁定版本 `2ed3f0d395be0c3ee9ebe238e2ffcead0094613f`。

## 1. 目标与范围

包子漫画 1 v6 的解析修复已经发布，但用户设备访问首页仍遇到 HTTP 403。图源仓库的诊断记录显示，站点返回 `challenge_required`，验证入口为 `/__gatekeeper_challenge/start`，页面需要 JavaScript。当前 App 只自动识别特定 Cloudflare 响应，无法直接处理这个自建 Gatekeeper 流程。

本功能让用户在 App 内完成网站提供的正常浏览器验证，并将可复用的验证状态用于图源请求。分两阶段交付：

| 阶段 | 用户行为 | App 行为 | 完成标准 |
| --- | --- | --- | --- |
| 一：手动验证 | 主动打开“网站验证”，完成网页流程，点击“完成并重试” | 保存站点状态、同步 Cookie、通过原网络通道检查列表 API、刷新页面 | 真机恢复包子漫画列表，并验证搜索、详情、章节与首图 |
| 二：自动识别 | 浏览时收到验证提示，必要时操作网页 | 识别验证响应、合并并发任务、打开同一验证页面、确认后恢复请求 | 到期后可再次完成验证，无重复弹窗或无限重试 |

“自动”指自动识别、引导和恢复请求；涉及点击或人工验证时仍由用户完成。第一阶段通过之后才推进第二阶段。

方案阶段已结束；用户已授权实施，手动与自动阶段代码均已接入，运行时仍以设备首次手动成功作为自动功能启用门槛。图源版本与发布产物不变；App 已从独立构建分支生成 IPA，用户确认真机可用，开发继续保留在独立分支。先以包子漫画为适配对象，接口允许添加其他站点；不把所有 403 当作验证，不全局替换请求引擎。

## 2. 本地源码核对与复用结论

| 已有位置 | 已确认行为 | 对本方案的影响 |
| --- | --- | --- |
| `Aidoku/Features/Source/NewSourceViewController.swift` | 当前图源页面通过 `SFSafariViewController` 打开网站，并进入 `SourceSettingsView` | 新增独立“网站验证”菜单项，保留正常浏览网站功能 |
| `Aidoku/Features/Source/Settings/SourceSettingsView.swift` | 已有 Cookie 和 WebKit 数据清理功能 | 放置永久手动入口；清理缓存时同步清理新功能状态 |
| `Aidoku/Core/Sources/Legacy/LegacySource.swift` | 旧图源由 `LegacySourceRunner` 适配为新 Source 接口 | 旧 WASM 不代表只走 Legacy 界面；主入口优先接当前新界面 |
| `Aidoku/Core/Sources/Legacy/Wasm/Imports/WasmNet.swift` | `performRequest` 使用 URLSession，调用 CloudflareHandler；`modifyRequest` 手工追加 Cookie | 包子漫画旧 SDK 的必要网络接入点，可从 `globalStore.id` 取得源标识 |
| `Aidoku/Extensions/AidokuRunner/AidokuRunner.swift` | 新 SDK 的 `requestHandler` 同样处理 Cloudflare；`Source.modify` 添加 Cookie 和 UA | 新旧请求统一接入协调器，避免仅修复一条路径 |
| `Aidoku/Core/Sources/Cloudflare/CloudflareHandler.swift` | 识别依赖 Server 标记和特定 HTML；完成判断依赖 `cf_clearance` | Gatekeeper 使用独立策略，不能只放宽 Server 检测 |
| `Aidoku/Core/Sources/Legacy/Wasm/Imports/WebView/WebViewViewController.swift` | 已有弹窗与导航代理封装 | 参考弹窗生命周期，新增完整工具栏、失败处理和重试反馈 |
| `Aidoku/App/Common/Settings/WebView.swift` | 已有 Cookie 观察器，可选 `.forSource(key:)` 数据存储 | 复用交互模式；验证页面必须明确选择并始终读取同一数据存储 |
| `Aidoku/Extensions/WebKit/WKWebView.swift` | Cookie 辅助方法将结果转换为名称和值，并用字符串 contains 筛域名 | 不直接用于 Cookie 桥接；会丢失路径等属性，域名匹配也不足够精确 |

选型：采用系统 WebKit + Foundation，复用仓库已有 SwiftUI/UIKit、源标识和网络钩子，不引入新的浏览器依赖。已有实现足以提供展示和网络扩展点，缺口主要是通用验证策略、Cookie 桥接及生命周期协调。现有 Cloudflare 功能先保留，通过回归再考虑迁移到统一协调器，不在首版重写。

第一版为旧图源验证明确使用 `WKWebsiteDataStore.default()`，与现有 Cloudflare 存储方式一致。新 SDK 接入同一验证存储；现有设置登录所用的 `.forSource(key:)` 不自动视为相同存储。其实现来自依赖，需要实施时核对，避免隐式混用。跨源同站会话共享沿用现有 App 行为，不在本轮宣称已实现按源隔离。

## 3. 共用模块与职责

建议新增 `Aidoku/Core/Sources/Verification/` 和 `Aidoku/Features/Source/Verification/`，文件按实际实现规模适当合并。

| 模块 | 职责 |
| --- | --- |
| `WebsiteVerificationCoordinator`（actor） | 管理验证任务、来源、同域等待者、结果、取消和重试额度；将 UI 工作切换至 MainActor |
| `WebsiteVerificationPolicy` + `BaozimhGatekeeperPolicy` | 判断响应是否为本站验证、解析入口、提供只读探测请求和成功响应检查 |
| `VerificationCookieBridge` | 原生与 WebKit 双向同步完整 HTTPCookie，处理过期、作用域和重试 Cookie 构建 |
| `WebsiteVerificationViewController`（MainActor） | 持有 WKWebView，展示域名、加载状态、关闭、重载和“完成并重试” |
| `VerificationContext` / `VerificationResult` | 传递 sourceKey、实际失败 URL、原始请求、UA、存储、触发方式及结果 |

上下文保留原始请求与已添加会话头的请求的区别，重试始终从原始请求重新构建。结果至少区分：已验证、仍需验证、用户取消、网络失败、超时、当前网络通道不兼容。错误透传到源页面，不能降级为空列表并显示成功。

## 4. 第一阶段：手动验证

### 4.1 入口与页面

在当前源页面菜单及 `SourceSettingsView` 增加“网站验证”。按钮不依赖列表成功加载，用户遇到首页 403 时仍能进入。Legacy 页面如仍有可达路由，补同一入口，不维护另一套验证逻辑。

验证页面展示当前站点域名、网页与加载反馈；工具栏提供“关闭”“重新加载”“完成并重试”。成功前不展示“已通过”。点击完成时禁用重复操作，显示“正在检查访问”；失败保留页面并给出可重试说明。用户关闭、交互式下拉关闭和程序关闭分别处理，防止成功结束后又被 disappearance 回调覆盖为取消。

默认打开该源实际使用的首页。对于手动入口，包子漫画先使用配置允许的站点地址；对于第二阶段的自动入口，优先使用失败响应所对应的实际站点。多域名不得仅取 manifest 第一个地址；自定义地址只有匹配已支持域名策略时才启用自动流程。

### 4.2 验证状态与 User-Agent

1. 在加载网页前等待该站已有原生 Cookie 导入完成，再发起加载；读取和观察的都是该 WebView 实际配置的数据存储。
2. 保持 WebKit 的持久化存储，让网页自行使用 Cookie、localStorage 等；不预设验证 Cookie 名称，不提取全部 localStorage 到原生层。
3. WebView 与后续 URLSession 请求使用一致的有效 UA。优先沿用源已明确设置且适合浏览器验证的 UA；未设置时复用 `UserAgentProvider`。若某源设置与正常浏览器不兼容的 UA，明确记录该源兼容问题，调整时须同时覆盖两条路径。
4. Cookie 桥接保留 domain、path、secure、expires 等属性，以 `(name, domain, path)` 作为存储身份。实际发请求时按目标 URL 过滤适用 Cookie，遵守 host-only/domain、路径、HTTPS 和过期约束，不用 contains，也不能只按名称粗暴去重。
5. 重试从未注入会话 Cookie 的原始请求构建一次，保留图源明确提供的必要 Cookie。对自动 Cookie 与显式 Cookie 同名冲突制定固定规则并测试；不得通过“新值 + 已注入的旧值”追加导致验证 Cookie 重复。当前 `allCookies(for:)` 只做域名过滤，不直接作为完整 URL 作用域判断。
6. 只同步当前允许站点的 Cookie；不导出完整 Cookie 仓库，不在日志记录 Cookie 值、Authorization 或带凭据的 URL。

会话 Cookie 不强行转成永久 Cookie。App 重启后尝试复用系统实际保留的状态，并重新探测；无法复用时允许重新验证。

### 4.3 成功判定与刷新

用户点击“完成并重试”后：

1. 等待相关 Cookie 同步完成。
2. 使用与图源相同的 URLSession 通道、有效 UA、Cookie 与必要请求头，发出一次只读列表探测；绕过验证触发器，避免探测递归打开验证窗口。
3. 包子漫画探测复用当前源默认列表 API：`/api/bzmhq/amp_comic_list`，参数以图源实际请求为准。检查状态码、响应类型和列表 JSON 结构；合法空列表可成立，返回验证 JSON、HTML 验证页或错误对象均不算成功。
4. 探测通过后关闭页面，向当前 sourceKey 对应的源页面发刷新事件；清理本次验证错误和失败显示状态，刷新列表及必要的失败封面请求，保留搜索条件、筛选与书架。
5. 手动验证没有挂起的原请求时仅执行页面刷新；不要既重放原调用又重复刷新相同列表。若从错误页面携带上下文，明确由哪一层恢复。

探测只判断原生通道可访问，不递归调用被阻塞的 WASM。在第二阶段尤其不能在 `WasmNet` 等待验证期间，再调用同一源 actor 读取 base URL 或执行列表，否则可能互相等待。

### 4.4 第一阶段的停止条件

如果网页正常、Cookie 已正确同步、UA 一致，但原生列表仍被拒绝，界面说明“网页验证已完成，但图源请求仍受限制”。此时先查重复 Cookie、作用域、所用数据存储、实际请求头和代理出口，再判断是否存在浏览器环境绑定。

若证据确认需要 WebKit 环境，另做小规模 spike：在保留验证会话的 WebView 内对同源 API 发请求，验证响应能否稳定回传。只有该通道也通过列表、搜索、章节验证，才修订范围推进。跨域 API/CORS、图片二进制与缓存、后台下载均需独立评估；不默认可以用 WebView fetch 替代全部网络请求。

在该分支解决之前，第一阶段标记为“验证入口已实现，恢复访问未通过”，第二阶段不以自动弹窗掩盖问题。

## 5. 第二阶段：自动识别与恢复

### 5.1 接入与识别

在 `WasmNet.performRequest` 与 `InterpreterConfiguration.defaultConfig(for:)` 的 requestHandler 接入相同检测入口。Gatekeeper 策略优先匹配明确支持的源和实际响应域名，再检查 403 响应中的 `error == challenge_required` 等已确认结构。原 Cloudflare 路径保留，不对任意 403 开启通用验证。

实施前重新采集一份脱敏的真实响应，确定验证入口字段名称和列表成功 JSON 结构，不凭诊断摘要编造字段。入口 URL 按响应 URL 解析，只接受 HTTPS 的同源地址或策略明确允许的验证域；拒绝脚本协议、任意外域和未经确认的跨域跳转。失效入口支持回到本站首页重新加载。

### 5.2 并发与生命周期

状态流转为：`idle → detected → awaitingPresentation → presenting → checking → resolved / failed / canceled`。

- 相同验证存储、主机与 UA 会话的并发失败加入同一任务；不同域串行展示。每个等待请求保留自己的取消与重放状态。
- App 前台且页面具备展示条件时才自动展示；后台刷新或下载只记录“需要网站验证”，不在后台弹窗，也不长期悬挂网络任务。回前台后提供入口。
- 第二阶段初版仍由用户点击“完成并重试”；后续可在导航完成或 Cookie 变化时防抖执行只读探测，成功后自动关闭。不能单凭 didFinish 或 Cookie 变化宣告通过。
- 每个原请求最多验证恢复一次；刷新、手动再次打开可开始新流程。取消后短暂抑制同域自动提示（建议 60 秒），手动入口不受影响。
- 建议加载和探测分别设 30 秒、15 秒超时；展示期间提供用户控制，验证会话总体上限建议 5 分钟并允许重开。取消、超时、导航失败和销毁均恰好完成一次 continuation，释放 UI 和所有等待者。
- Legacy 同步网络桥只允许在其既有工作队列等待；UI 和探测使用独立异步路径，不在 MainActor 上执行 semaphore.wait，也不新增跨 actor 反向调用。

### 5.3 重放边界

第一版自动重放仅覆盖 GET/HEAD。保留原始 method、URL、正文和必要头；POST、登录、支付等可能产生副作用的请求不自动重放，提示完成验证后重做操作。探测及已重试请求带内部标记，避免再次进入验证分支。

同一任务的等待请求在验证成功后分别重建 Cookie 并各重试一次；任何一个仍受验证限制时返回明确错误，不重新开启窗口。

图片请求是独立链路。`getModifiedImageRequest` 目前只构建请求，不能在那里判断响应 403。第二阶段先完成文档/API 请求；若实测封面或阅读图片也需要单独验证，再在实际图片加载器的响应/失败层接入识别和前台提示，并保留 Nuke 缓存和取消语义。后台下载遇验证时暂停/失败并标明原因。API 恢复不代表图片和后台下载已完成适配。

## 6. 验证与验收

| 验证层 | 必须覆盖 | 通过证据 |
| --- | --- | --- |
| 单元测试 | Gatekeeper 正例、普通 403 反例、畸形 JSON、非法入口、域名边界、Cookie 路径/过期/同名、重复注入、任务合并、取消、超时、重试上限 | XCTest 固定脱敏样本，不访问真实站点 |
| 可控集成测试 | 页面设置 Cookie 后原生 API 从拒绝变正常；网页 200/API 403；重定向、无 Cookie、合法空列表、网络失败 | 测试服务或受控 fixture 页面；验证 UI 与探测结果一致 |
| 现有能力回归 | 新旧 SDK 正常站点、现有 Cloudflare、打开网站、源设置、清缓存 | 现有测试及模拟器交互；失败不靠关闭检查处理 |
| 真机第一阶段 | 首次访问→手动验证→列表、搜索、详情、章节、至少一张真实图片 | 同一设备和网络的实际结果，分别记录每层状态 |
| 真机第二阶段 | 验证到期、多请求并发、取消、重开、切后台、返回前台、网络切换 | 无重复窗口、无限重试、死锁或伪成功 |
| 持久化与清理 | App 重启尝试复用；清缓存后能够重新验证 | 不承诺 session Cookie 跨进程存活；等待相关清理完成后刷新 |

清缓存需复核现有逻辑：其 WebKit removeData 是异步调用，目前 continuation 并未等待所有删除结束。新增流程要等待相关 Cookie、WebKit 数据及协调器状态清理完成，避免清理与验证互相覆盖。

设备测试优先记录 App 版本、iOS 版本、源版本、网络类型、请求主机、状态码、挑战类型和各步骤结果；不记录会话秘密。编译通过、WebView 打开成功或 API 成功均不能单独标记完整阅读通过。

## 7. 实施顺序与交付

1. 采集脱敏验证响应与正常列表样本；确认实际页面路由、UA 和数据存储，完成 Cookie→原生请求的最小真机 spike。
2. 实现策略、Cookie 桥接、手动验证页及现有源页面/设置入口，完成第一阶段自动化与真机验收。
3. 第一阶段通过后，给新旧网络入口接入自动识别、同域任务合并和一次重放；补前后台、取消及过期场景测试。
4. 根据真机结果决定是否增加自动完成探测、图片验证或 WebKit 请求通道；每项单独定义验收，不混入已完成结论。

实施时使用 4 空格缩进、控制语句多行花括号，运行相关 XCTest、SwiftLint 和差异检查。功能默认保留手动入口；自动行为可按站点策略关闭，以便回退。Cookie 本身不等于已验证状态，内存成功标记只作提示优化，每次实际失败仍以响应为准。

本仓库当前没有文档站；本次为独立实现方案，先交付单份 Markdown，不为一个方案引入文档构建系统。

## 8. 证据与待确认项

- 本地源码核对：本文件第 2 节中的相对路径；代码基线见文件开头。
- 图源诊断依据：图源仓库 `docs/HANDOFF.md`、`docs/SOURCE_AUDIT.md` 的包子漫画 1 设备反馈修正，以及 `src/rust/zh.baozimh1/src/lib.rs` 的实际请求。
- [Apple：WKHTTPCookieStore](https://developer.apple.com/documentation/webkit/wkhttpcookiestore)：Cookie 存储 API 参考。
- [Aidoku 上游问题 #1034](https://github.com/Aidoku/Aidoku/issues/1034)：用户报告 WebKit 成功而 URLSession 仍失败，用作风险线索；不据此断言包子漫画存在同一问题。

尚未确认：Gatekeeper 的实际状态字段与有效期、验证是否只依赖 Cookie、设备环境下 URLSession 是否接受验证结果、图片域是否另设验证。这些通过第一步 spike 和真机链路验收解决；不预先承诺手动验证页上线即可恢复阅读。
