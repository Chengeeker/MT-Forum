# MT论坛开发文档

更新：2026-10-28。当前版本：1.0.0+24。主文档同步至 `D:\App\开发文档\MT论坛.md`。

## 用户要求与边界
- Android 包名 `bbs.binmt.cc`，应用名 MT论坛，仅 ARM64-v8a。
- BKS 来源 `D:\Download\backup\infinitycm.bks`，密码不写入文档或受版本管理文件。
- 网站 https://bbs.binmt.cc/；UI 以本机 Review 当前源码及 M3 UI 复用规范为准。
- 用户指定启动器图标源文件时，按原始 PNG 字节使用，不裁切或编辑图像；Android 启动器按系统图标位显示。
- 保留网站权限、验证码、隐藏回复、附件访问限制；不能伪造成功/签到/未读/在线人数。

## TODO
- [x] 工程、包名、名称、ARM64 签名构建
- [x] 复用 Review 主题、磨砂栏、设置、触感、转场
- [x] 原生首页：快捷入口、官网专区图片、热门和最新帖子
- [x] 原生板块/导读列表、分页、筛选
- [x] 原生帖子阅读、楼层、链接、图片查看
- [x] 搜索、站点收藏入口、本地浏览历史
- [x] M3 原生登录和官网同源会话共享；回复、消息、账号等同源入口已原生适配，插件/附件/验证码边界见审计
- [x] 明暗/纯黑/动态取色/主题色/液态玻璃导航/触感偏好持久化
- [x] Review 字体大小/字重偏好、悬浮底栏与磨砂顶栏复用
- [x] Review 风格的共享元素图片打开动画、多图缩放画廊、原生视频播放
- [x] 用户提供启动器 icon
- [x] 解析、安全边界、界面测试与 analyze
- [x] ARM64 release APK 包名/版本/ABI/签名/哈希核验
- [ ] 真机与真实账号验收（需要可连接网站和账号）

## 已知问题与避免复发
1. 初始工程及 MT论坛开发文档均为空，没有旧 APK 或用户文件需要覆盖。
2. 本机 curl、移动 API 均收到 403，内置浏览器 ERR_HTTP_RESPONSE_CODE_FAILURE。网络失败必须显示原因及重试/官网入口，不能用“暂无数据”吞错。用户提示站点可能限制海外网络，需要核对本机代理路由。
3. Review 仅复制 UI 组件，不复制微博业务、Cookie、账号或整个设置页。主题及磨砂来自当前源码，设置页按论坛能力组合。
4. Review 画廊曾有分页/缩放手势问题。论坛版用 ExtendedImage 手势分页及 Hero 共享元素转场，关闭滑出手势；未迁移 Review 的手势仲裁、HDR、Live Photo 等微博专属逻辑，合入后仍需真机核对缩放与翻页冲突。
5. 返回首页和 Tab 切换保持已有内容与滚动位置；不在 resume 自动刷新。仅显式刷新重载非空列表。
6. 不关闭 TLS 验证，不将 Cookie 附到外站。登录会话由 Android WebView 私有 Cookie 存储维护；原生只按论坛 URL 读取。
7. 原生登录页不仅要绑定“登录 / 注册”按钮，所有需要账号的入口及官网登录重定向都必须经过统一导航；否则游客点消息等操作仍会看到网页登录。登录取消不得继续打开目标网页。

## 架构规划
- Flutter M3 原生首页、列表、阅读、搜索、设置；Dio 获取官网 HTML，html 解析 Discuz 页面，不依赖未核实的私有 API。
- 登录界面是 Flutter Material 3 原生表单；登录提交交给隐藏的同源 WebView 执行官网表单脚本，保留动态 formhash、自动登录和安全提问。只读取论坛 auth Cookie 来确认会话，不保存密码。当前注册、发帖和回复由原生表单控件承接官网协议；复杂插件、附件上传及验证码仍有适配限制。
- 本地仅保存显示偏好、浏览记录；不保存帖子正文到磁盘，避免账号切换泄露私密内容。
- 首次版本网站写操作仍为网站 UI，不能算全部页面完成原生 M3；后续需在可访问网站后核对表单才能替换。

## 来源
- https://bbs.binmt.cc/ 首页、板块与导读结构（公开网页检索可读，本机直连受阻）。
- Review：`D:\App\Review\lib\core\theme\app_theme.dart` 与共用组件，保留 MIT 授权 `docs/REVIEW_LICENSE`。

## 2026-10-25 实施进展与复盘
- [x] Flutter 工程、`bbs.binmt.cc`、MT论坛、Android 7.0+（minSdk 24），版本 1.0.1+2。
- [x] 直接迁移 Review 当前 AppTheme、ReviewFrostedAppBar、ReviewPreferenceTile/ReviewSwitchTile/ReviewChoiceTile、AppSectionCard、HapticFeedbackUtil、页面转场；保留 MIT 授权并加入应用许可证列表。
- [x] 原生首页四个快捷入口、12 个真实板块、官网首页热门/最新分区、服务器返回的在线人数。在线数为请求时快照，不是持续连接的实时状态。
- [x] 原生板块/导读、最新/热门/精华筛选、分页续载、正文 HTML、引用/代码/链接、楼层、用户资料入口、图片 InteractiveViewer。
- [x] 发现、原生搜索输入、官网搜索结果、本机最近 100 条浏览历史、官网收藏入口。
- [x] 个性化：跟随系统/浅色/深色、8 主题色、动态取色、纯黑、Review 同款液态玻璃底部导航、触感，设置持久化。玻璃默认关闭；关闭时使用 M3 NavigationBar。
- [x] 登录入口打开原生 M3 表单（用户名、密码、安全提问、自动登录）；隐藏 BrowserReader 读取当前官网表单并调用官网 JavaScript 提交，使用网站动态令牌和自身校验。密码不写入 SharedPreferences 或日志；登录成功必须读到论坛 auth Cookie，随后刷新账号内容。
- [x] 注册、发帖、回复、消息、个人资料、收藏仍使用同源 WebView；只对当前展示的官网流程做 M3 主题适配，没有声称为完整原生表单。
- [x] 官网文件上传接系统 ACTION_OPEN_DOCUMENT；无需全盘存储权限。站外主页面交给外部浏览器，由用户确认目的地址；第三方验证 iframe 保留原网站行为。
- [x] 官网 auth Cookie 改变后清除内存旧账号内容并重新请求；请求代次校验防止旧请求完成后覆盖新账号。Cookie 不落到 SharedPreferences，不写日志；Android 禁止应用备份和明文 HTTP。
- [x] 初版 icon 来自网站 favicon；用户随后指定以 `D:\Download\图片\icon16.png` 作为启动器图标，现用原始 2048×2048 RGB PNG 字节，未裁切、改色、加边距或重采样。旧站点 favicon 保存在 `build/rollback/site_icon_website_favicon_24x24.png`。
- [x] 静态分析通过（使用 `dart analyze --format=machine lib test`）；8 项测试通过（含账号切换时旧请求不能回填旧内容）。预览位于 docs/preview-dark.png、docs/preview-light.png，为真实公开首页 fixture 的 Flutter 布局渲染，不是真机截图。

### 网络与构建错误记录
1. 初始 curl 默认 User-Agent 返回 ESA 403，不能直接认定只支持国内网络。已通过本机现有代理核心的隔离 direct 实例及标准 Chrome User-Agent 取到首页 200；随后默认代理链路带标准浏览器 UA 也能取到首页。Chrome 能读取真实帖子。部分路径有网站 JS 浏览器验证；客户端 HTTP 解析失败后用按需 WebView 正常加载，让网站执行自己的验证，再读取同源 HTML。没有提取桌面浏览器账号 Cookie，也没有解算验证码。
2. `flutter analyze` 的 LSP 在中文路径出现 JSON 截断异常；`dart analyze --format=machine lib test` 可正常完成。不要把分析服务崩溃误记为代码通过。
3. AGP 拒绝中文路径：项目内 android.overridePathCheck=true 仅能通过目录检查，不能解决 AOT/JNI 原生工具找不到中文路径输出。实际发布通过 tool/build_release.ps1 在系统临时 ASCII 目录复制精确生产源码构建，成功后复制 APK 回项目根目录。临时源码路径写 build/release-source-path.txt，保留以复核/回退。
4. Flutter --target-platform android-arm64 和主 app 的 ABI 过滤不足以排除依赖 JNI 的额外 ABI。根 Gradle 对所有 Android library 的 NDK 过滤为 arm64-v8a，并在 app packaging 明确排除其他 ABI；交付必须再检查 ZIP lib/ 和 aapt 的 native-code。
5. 网站 HTML 声明 UTF-8，但有少量历史脚本注释为非法 UTF-8。生产 HTTP 使用 allowMalformed，真实页面 fixture 已替换非法注释字节，不引入 GBK 依赖。
6. 构建签名从指定 BKS 转换 PKCS12，保留原私钥身份。签名本地配置 android/signing.local.json 和转换密钥均被 .gitignore 排除；不需要再次输入别名和口令。密钥不写入文档。
7. 自动审批拒绝了按“签到”文字自动点击未知官网链接的方案，原因是可能未经明确目标核对就改变账户状态；该方案未执行。现为打开有签到入口的官网板块页，由用户明确点击网站签到按钮。
8. 带本地 Liquid Glass shader 的 Flutter 测试也会受中文目录影响，启动阶段出现 GLSL include not found；使用与 release 相同的 ASCII 源码快照运行检查，不删除 include 或禁用效果。`tool/build_release.ps1 -RunChecks` 在发布前从该快照运行论坛解析和 Widget 回归。

### 尚未验收/已知差异
- 未连接 Android 真机；真实账号登录、验证码、发帖、回复、签到、私信、附件上传/下载未作端到端验收，不能由编译通过推断成功。
- 签到快捷入口打开官网板块页后需手动点击签到；不显示伪造的“已签到”。
- 除账号密码登录表单外，注册、发帖、回复、搜索结果、账号/消息仍为主题适配后的官网界面，不能宣称所有页面已经完整原生 M3 或与 Review 一模一样。
- 液态玻璃仅用于 Review 同款悬浮底栏，设置可开启或关闭；未将玻璃材质扩展到整个应用。图库现在有 Hero 打开动画、多图滑动、双指缩放及双击缩放；不含 HDR、Live Photo 或 Review 的自定义拖拽手势。视频仅播放帖子正文中识别到的 HTTPS 直链（mp4/m3u8/m4v/mov/webm），含播放/暂停、拖动进度、倍速和重试；不含画质选择、画中画、下载管理或网页 iframe 播放。
- 无新增网络代理到 APK，用户设备仍需能访问论坛。没有后台轮询、自动发帖、自动刷新非空内容或全帖图片预加载。
- Root APK 只保留最新交付；构建中间版在 build/rollback，仅作为回退证据，不能作为最终交付。



## 历史交付核验（2026-10-25，v1.0.1+2）
- APK：`D:\App\MT论坛\MT论坛_v1.0.1_arm64.apk`，版本 `1.0.1+2`，包名 `bbs.binmt.cc`，应用名 MT论坛，minSdk 24、targetSdk 36。
- aapt 与 ZIP 双重检查：仅 `arm64-v8a`。首次中间包曾夹带依赖库额外 ABI，已经在最终包修复；build/rollback 中间包不作为交付。
- apksigner：Verifies，v2 验证通过；证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975`，与指定 BKS 转换出的同一私钥证书一致。
- zipalign `-c -P 16 4` 退出码 0。
- APK SHA-256：`29f58de55dfa9a15e80c3a475da000af014be00248af3041802ef6f566752ee`（1.0.1+2；仅图标的上一包哈希见 `build/rollback`，不作为交付）。
- 最终生产源码与 ASCII 临时构建目录 36 个文件哈希比对通过；APK 内的 2048×2048 icon PNG 解码像素与用户原图完全一致。核验记录 `build/release-verification.json`，签名记录 `build/final-apk-signature.txt`。
- 已结束本次创建的 17890 隔离网络探测实例；没有修改用户现有代理服务或全局路由。
- 没有推送远端、发布到应用商店或安装到设备。仍待真机验收，尤其官网复杂表单、验证码和附件；未实现原生下载管理器，认证附件下载兼容性尚未确认。


## 2026-10-25 用户指定图标更新
- 使用用户提供的 `D:\Download\图片\icon16.png` 覆盖 Android `drawable-nodpi/site_icon.png`。原文件 2048×2048、RGB，源资源复制字节保持一致；Android 打包器对 PNG 编码做了压缩优化，APK 内资源尺寸和像素逐点与原图一致。资源无密度限定，未另行缩放、裁切、换色、加白边或添加自适应图标背景。系统启动器会按自身图标显示区域渲染。
- 旧 24×24 网站 favicon 已存入 `build/rollback/site_icon_website_favicon_24x24.png` 供回退。
- 图标更新构建版本升至 1.0.1+2，构建脚本校验版本和输出文件名同步更新。
- 验收：输入 PNG 与源资源 SHA-256 完全一致；APK 中压缩后的 PNG 解码尺寸与 RGBA 像素逐点一致。签名/包名/版本/ARM64 ABI/对齐记录于 `build/release-verification.json`。


## 2026-10-25 专区图片修正
- 复查发现首版专区网格只使用本地 Material 图标，没有使用官网 `.fl` 板块项里的真实图片 URL；用户指出空占位问题。
- `parseForum` 现在为板块记录解析官网图片地址，只接受 HTTPS 的 `cdn.binmt.cc` 或论坛自身来源；不把论坛 Cookie 传给图片请求。首页按 fid 对应展示图片并裁切到现有圆形头像框；加载失败时保留图标回退。
- 解析回归用官网首页 fixture 核对 12 个板块均带图像 URL；不会额外抓取或预加载线程图片。
- 图标和专区图片修正合并到 1.0.1+2 最终构建，之前同版本的仅图标 APK 保存于 `build/rollback/MT论坛_v1.0.1_icon-only.apk`，不作为交付。

- 最终包增加专区真实图片；APK 大小 22,595,774 字节。通过 aapt 确认包名/版本/应用名及仅 ARM64-v8a；apksigner、zipalign 校验成功。


## 2026-10-25 原生登录与液态玻璃偏好
- 版本更新为 1.1.0+3；继续保留原包至 `build/rollback/MT论坛_v1.0.1_pre_login_glass.apk`。
- 登录入口改为 `ForumLoginPage` 原生 Material 3 表单，并复用 ReviewFrostedAppBar、ReviewSwitchTile、AppSectionCard。包含用户名、密码显示切换、Discuz 0–7 安全提问、自动登录开关和长度/必填校验。
- 登录请求只通过论坛同源隐藏 WebView 读取现行表单、保留网站动态 formhash 并提交；外部网页不会显示。登录提示不单独代表成功，必须从 Android CookieManager 读到论坛 auth Cookie。账号变化后清空旧账号内容并刷新。密码不保存、不写日志；表单提交后清空控件及 WebView 密码字段。
- 液态玻璃依赖固定为 Review 本机 `liquid_glass_widgets` 1.13.0（MIT/NOTICE 随包）；设置持久化 `liquidGlass`。开启时使用 `GlassTabBar.bottom` Review 配置，关闭时恢复 M3 NavigationBar。仅对导航栏启用，避免整页模糊和额外 GPU 消耗。
- 保留的失败边界：若官网以后增加验证码或新的登录字段，原生页当前不会显示新字段，服务端错误会回到原生页；需要届时扩展表单。当前真实账号登录和液态玻璃真机帧率/观感仍待设备验收。
- 本次变更采用 `dart format`、`dart analyze --format=machine lib test` 和 ARM64 release 构建做静态/打包核验；不以构建结果替代真实账号或设备验收。具体核验结果写在最终交付核验段。

## 2026-10-25 Review 设置与媒体交互复用
- 设置页继续使用 Review 的 M3 ChoiceTile、SwitchTile、PreferenceTile、SectionCard 和磨砂顶栏；新增 Review 风格的应用字体缩放/字重与悬浮底栏偏好，所有偏好写入 SharedPreferences。大字号下字重选择对话框可滚动。
- 论坛首页、发现/搜索、登录、个性化、论坛列表/正文、媒体画廊及视频页均使用 `ReviewFrostedAppBar`；保留系统状态栏与 M3 语义颜色。
- 帖子内图片使用 Hero 标签从原位置过渡到全屏画廊。画廊基于 `extended_image`，可左右翻页、双指缩放/双击缩放；关闭滑出关闭手势以免与缩放和分页抢事件。图片请求只允许 HTTPS；同站或 `cdn.binmt.cc` 带 Referer 和 UA，不携带 Cookie。
- 论坛视频页基于 Review 已用的 `video_player`，支持播放/暂停、进度拖动、0.5×–2×倍速、失败重试。解析只识别带标准文件扩展名的 HTTPS 直链；外站媒体不带论坛 Referer、UA 或 Cookie。签名帖子附件若依赖登录 Cookie，Flutter 原生播放器可能无法取回。
- Review 的微博画质/直播解析、画中画、HDR/Live Photo、下载管理依赖特定站点数据和服务，本次不复制。公开视频和真机上的画廊手势、播放器硬件解码及大字号布局尚未设备验收。
- Windows 上 Flutter 的 `.bat` 启动流程在受限目录中未进入 Dart 任务；标准构建脚本现直接调用已安装 SDK 的 `flutter_tools.snapshot`，仍在 ASCII 临时目录复制生产源码、离线解析依赖并构建同一 ARM64 release。调用前需允许 Flutter SDK 写入它自己的 `bin/cache` 锁文件。

## 历史交付核验（2026-10-25，v1.1.0+3）
- APK：`D:\App\MT论坛\MT论坛_v1.1.0_arm64.apk`，24,489,892 字节；包名 `bbs.binmt.cc`，应用名 MT论坛，版本 `1.1.0+3`，minSdk 24、targetSdk 36。
- `aapt` 与 APK ZIP 检查均确认包名/版本和唯一 ABI `arm64-v8a`；`apksigner verify --verbose` 通过 v2 签名；证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975`，与指定 BKS 对应证书一致。
- `zipalign -c -P 16 4` 退出码 0；APK SHA-256 `81e0d3a016699153de7fcfa4e29bae3ef61b17b1d9901965af6cf10f865e1db4`。
- 用户提供的 icon 与 `drawable-nodpi/site_icon.png` 源资源 SHA-256 一致；保持原 2048×2048 源图，不指定 density，不裁切或重采样。应用图标资源已在 APK manifest 指向 `@drawable/site_icon`。
- `dart format` 无待格式化文件；`dart analyze --format=machine lib` 退出码 0、无诊断。按任务约束未运行自动化测试；设备端未验收。
- 精确构建源码快照保存在 `build/release-source-path.txt` 指向的临时 ASCII 目录。构建时 Flutter 3.47.1 提示 AGP 8.11.1 与 Kotlin 2.2.20 后续将退出支持范围；本次构建成功，后续升级 Flutter 时再单独评估兼容版本。
- 旧根目录 APK 已移入 `build/rollback` 保留；根目录只保留本次最新交付。没有安装、发布或提交远端。
- 设备风险仍包括真实账号登录/验证码、液态玻璃性能、图片手势、不同视频编码器及依赖登录 Cookie 的论坛附件访问；构建成功不代表这些场景已完成端到端验收。

## 2026-10-25 游客消息入口登录修复（1.1.1+4）
- 用户反馈：未登录点击“消息”仍打开官网登录页。根因是上一版仅改了显式登录按钮，底栏和顶栏消息入口继续直接调用 `openWeb`，没有前置登录检查。
- 论坛网页入口统一经 `openForumWeb`：消息、自己的资料/帖子/收藏、收藏操作、发帖和回复在没有有效值的 auth Cookie 时先打开原生 `ForumLoginPage`；取消停留原页，成功后继续原目标。公开板块、帖子、他人资料和注册不强制前置登录。
- 官网导航到同源 `member.php?mod=logging&action=login` 时阻止网页跳转并改为原生登录；同源页面直接返回 Discuz 登录表单也会交给原生页。取消过期会话的登录时关闭被拦截的官网目标；登录成功重载原目标。注册仍为官网流程。
- auth Cookie 判定排除空值（如 `_auth=`），账号变更通知避免与嵌套原生登录重复触发。沿用站点正常登录验证，不改变密码保存策略。
- 修复版本 1.1.1+4，应用关于页与发布脚本同步更新；`dart analyze --format=machine lib test` 无诊断。ASCII 快照的论坛解析和 Widget 检查共 15 项通过，覆盖四种消息入口组合、取消登录、模拟登录成功、五项底栏点击尺寸、账号切换和大字号回归；真实账号和设备视觉仍未验收。最终 APK 核验见下方交付记录。
- 用户追加要求五项悬浮底栏更宽松：普通和液态玻璃统一使用安全区域宽度减 32dp（左右各 16dp）、上限 440dp，不再乘 2/3。保持 56dp 栏高和原选中效果；360/390dp 屏幕验证每个普通悬浮入口点击区至少 48×48dp。
- 既有大字号回归还发现窄胶囊底栏固定高度会使两倍字体溢出；有效 12sp 标签超过 16dp 时自动用标准 M3 NavigationBar，悬浮/玻璃偏好保留，恢复字体大小后恢复对应样式。

## 历史交付核验（2026-10-25，v1.1.1+4）
- APK：`D:\App\MT论坛\MT论坛_v1.1.1_arm64.apk`，24,555,428 字节；包名 `bbs.binmt.cc`，应用名 MT论坛，版本 `1.1.1+4`，minSdk 24、targetSdk 36。
- `dart analyze --format=machine lib test` 无诊断；`tool/build_release.ps1 -RunChecks` 在 ASCII 快照内完成 15 项测试，并成功构建同一生产包名的 ARM64 release。源码、许可证及配置共 26 个文件与构建快照哈希一致。
- `aapt`/APK ZIP 确认仅 `arm64-v8a`；`apksigner verify --verbose --print-certs` 验证 v2 签名通过，证书 SHA-256 仍为 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975`；`zipalign -c -P 16 4` 退出码 0。
- APK SHA-256：`f1572b72fbc9638d31fd408ae190b07986b28df2eef5048eea7f6a630401a376`。APK 的图标 PNG 字节与已验收上一版相同；未修改用户图标。
- 回退包 `build/rollback/MT论坛_v1.1.0_arm64.apk`，对应核验记录和签名记录也已归档。最新记录为 `build/release-verification.json` 和 `build/final-apk-signature.txt`。中文路径测试失败日志保存在 `build/diagnostics/flutter-test-chinese-path-20261025.log`。
- 未安装到设备，未提交真实账号登录。自动化覆盖游客入口和模拟登录，网站会话失效重定向、验证码及液态玻璃设备观感仍需真机确认；登录成功后的消息正文仍为官网内容，原生登录界面负责账号验证入口。

## 2026-10-25 登录响应与官方方式适配、首页密度（1.2.0+5）
- 用户反馈账号密码登录持续转圈，并要求核对全部官方方式。独立游客浏览器已核对用户名、Email 和 QQ 三个入口，详细字段/来源见 `docs/LOGIN_PROTOCOL.md`；不把未启用的通用 SMS 插件代码当作已支持手机号登录。
- 确定根因：官网 `returnmessage_<hash>` 在 form 外，旧桥接脚本在 form 内取节点导致所有 AJAX 错误均读不到。另外旧正文读取和登录共用串行队列，排队/加载时间不在原生超时范围内。
- 新桥接脚本 `assets/forum-login.js` 按 form hash 从 document 查响应，保留动态令牌与官网 onsubmit；Email 发送 loginfield=email，QQ 通过单独的官方授权界面。登录可抢占已有正文读取，35 秒桥接事务限时、45 秒原生看门狗、取消和请求代次防迟到回调；密码在响应/取消后清除。
- 用户提供两张尺寸对比图：仅收紧首页，不缩放整个应用或覆盖用户字体偏好。专区图像 46→36dp，网格项上下留白 12→4dp、图文间距 8→4dp；标题改用 titleMedium、网格与快捷标签改用 labelMedium；首页卡片圆角 24→12dp、分区间距 16→8dp，保留上轮加宽底栏。
- JavaScript 模拟官网表单外响应、Email select 转换、取消清理和站外 action 拦截共 4 项通过；Flutter 的 Email 参数、取消/超时停止转圈、迟到响应、紧凑首页尺寸及既有回归/预览共 20 项通过。静态分析无诊断；板块折叠标题保留至少 48dp 点击高度，缩小视觉元素不缩减此点击区。
- QQ iframe 所需第三方 Cookie 仅在专用授权视图启用。未提交真实账号或 QQ 授权，未代替用户确认验证码；当前没有实现动态验证码的原生输入，遇到时明确提示限制。核对协议已同步到 `D:\App\开发文档\MT论坛-登录协议核对.md`。

## 最终交付核验（2026-10-26，v1.2.0+5）
- APK：`D:\App\MT论坛\MT论坛_v1.2.0_arm64.apk`，24,557,185 字节；包名 `bbs.binmt.cc`，应用名 MT论坛，版本 `1.2.0+5`，minSdk 24、targetSdk 36，仅 `arm64-v8a`。
- 最终 ASCII 构建快照 `mt-forum-release-cf907b34` 与当前源码、资源及配置共 27 个文件哈希一致。重新执行静态分析、4 项生产 JS 桥接检查和该快照内的 20 项 Flutter 测试全部通过；明暗主题图片为自动化 fixture 预览，不是真机截图。
- `apksigner verify --verbose --print-certs` 通过 v2 签名；证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975`。`zipalign -c -P 16 4` 通过；aapt 与 ZIP 均确认包名、版本和单一 ARM64 架构。
- APK SHA-256：`e55035c9b880a116bcfe30b0b773fbbd0bca81176486a5ece1142b678463f036`。用户原图资源及 APK 图标 PNG 哈希均与上一版一致，没有缩放图标源文件。
- 上一版 1.1.1 APK 和核验记录归档于 `build/rollback`，根目录只保留最新包；最新核验信息见 `build/release-verification.json`、`build/final-apk-signature.txt`。
- 未安装到设备，未提交真实账号登录或 QQ 授权。真实账号成功、QQ 回调、动态验证码与设备上的视觉/玻璃性能仍待验收；不能用模拟表单和静态检查替代真实登录结论。

## 2026-10-26 已登录但原生页仍转圈与重复登录（1.2.1+6）
- 用户真机反馈 1.2.0 登录仍转圈，退出后官网资料页已登录，但客户端仍显示登录/注册。上一版模拟桥接通过不能证明服务端登录后的原生状态同步正确，不能将其标记为真实账号验收完成。
- 原生登录现在同时等待官网响应和 Android CookieManager 的新 auth Cookie；提交前记录基线，仅新建或变化的非空 auth Cookie 可提前完成本次登录，不接受旧 Cookie 充当新提交成功。500ms 检查只在提交期间运行，单次读取不重叠；完成、取消和销毁时停止，迟到响应不能改变新请求或已完成页面。
- showForumLogin 在展示前检查共享会话，已有会话直接返回；退出登录页后再次读取 Cookie，处理返回键与服务端成功的竞态。我的页面从同一 Cookie 读取结果显示已登录入口，并在启动、进入我的和网页返回时同步，避免静态登录按钮误导用户。
- 版本更新为 1.2.1+6，继续使用原包名、原签名和 ARM64；回归新增 Cookie 成功但桥接不返回、迟到错误、恢复已有会话和我的入口状态。构建和核验结果待完成后补充。

## 2026-10-26 原生功能入口审计（1.3.0+7）
- 用户追加反馈帖子回复仍打开网页，要求审计所有同类入口；尚未交付的 1.2.1 仅作为中间构建，不作为最终包。
- 全量调用点检查：回复/引用回复、发帖、作者资料、我的资料/帖子/收藏、收藏操作、消息/提醒、搜索结果、排行榜、签到、注册以及错误页“官网”入口此前均经过 openForumWeb，实际仍显示 ForumWebPage。签到按钮还错误指向版本发布版块，已改为官网 k_misign-sign.html。
- 正在将 openForumWeb 的同源目标统一分派到 NativeForumPage，M3 顶栏、原生表单控件及 Flutter HTML 内容渲染；没有可见 WebView。QQ 仍仅使用官方授权视图，站外链接经明确外部链接确认。
- 官方只读浏览器核对 postform 回复协议：formhash/posttime/noticeauthor/noticetrimstr/noticeauthormsg 动态值；subject/message；replysubmit；action 中 replysubmit=yes；onsubmit 是 validate2。原生 BBCode 编辑设置 wysiwyg=0，隐藏值来自当前页面，引用内容沿用 textarea。未发送测试回复/消息/帖子。
- 新增 ForumClient.source 原始只读 HTML 与 submit 原生表单提交，共享 Android CookieManager；同源每次跳转校验，服务端 Set-Cookie 通过原生 setCookie 写回。写提交失败不回退浏览器、不自动重试，防重复发布；仅只读请求可沿用现有隐藏验证 WebView。
- NativeForumDocument 移除脚本、网页布局样式和事件处理；form 由 NativeForumFormView 的 M3 输入/选择/开关/按钮接管。输入保留在原生控件，失败不替换文档。签到按官网 JD_sign 同源地址在用户点击后执行，不自动签到；只翻译已核对的签到排行 ajaxget 导航。
- 原生入口、引用字段、提交编码、Cookie 写回、302 后不重复 POST、站外拦截、搜索结果、编辑失败保留、成功返回和放弃确认均已有回归覆盖。通用 openWeb 函数及帖子/错误页的网页后备菜单已删除；生产源码只剩 QQ 授权一处可见 ForumWebPage 构造。清单与限制见 docs/NATIVE_UI_AUDIT.md。
- 原生表单提交前还核对页面加载时的账号会话；不将旧账号表单以另一个账号提交。文字编辑离开/刷新前需确认放弃；删除/退出等已识别动作使用原生确认。无法确认发帖结果时不当作成功，保留输入并提示先核实。
- 原生编辑器当前支持文字/BBCode，未完成官网附件上传与复杂脚本插件/验证的原生适配；禁止可见网页兜底，不以通用内容页替代全站行为验收。真实账号发布、私信、注册、验证码仍未执行。
- 正在构建 1.3.0+7；静态预览为合成数据，不含真实账号或表单令牌。最终 APK 核验待完成后补充。
- 最后检查修复同名复选框的独立选中状态及表单列表字段编码：只发送实际选中项，原始 items[] 名称不再被二次追加 []。回归覆盖取消某一项、保留另一项及 HTTP 正文编码；防止批量消息/收藏操作的 UI 与请求不一致。
- 官网游客会话再次核对发现“立即注册”的真实地址为 member.php?mod=register213，不能硬编码 mod=register；当前原生注册页会先读取现行官网登录页的同源注册链接。实际注册表单含邀请码以及随机字段名，显示标签从官网 label/for 读取，原样提交字段名；保留获取邀请码/协议等链接为原生按钮。未创建账户或提交注册。

## 最终交付核验（2026-10-26，v1.3.0+7）
- APK：`D:\App\MT论坛\MT论坛_v1.3.0_arm64.apk`，24,753,897 字节；包名 `bbs.binmt.cc`，应用名 MT论坛，版本 `1.3.0+7`，minSdk 24、targetSdk 36，仅 `arm64-v8a`。
- 当前 `lib`、`assets`、配置与 ASCII 构建目录 `mt-forum-release-8a1648cf` 共 29 个文件 SHA-256 相同；Android `MainActivity.kt` 的会话写回代码也单独匹配。静态分析无诊断，最终快照内 42 项 Flutter 检查与生产 JS 登录资产的 4 项检查全部通过。
- `apksigner verify --verbose --print-certs` 通过 v2；签名证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975`。aapt/ZIP 确认包名、版本和单一 ARM64；`zipalign -c -P 16 4` 通过。APK 图标资源哈希与原图已核验版本一致，未调整用户的应用图标。
- APK SHA-256：`2d5bb6f2f641dea3d19ce1a71cf997484f1c1cea93c8a941aced451a978a24c3`。根目录只保留此最终包；1.2.0、未交付 1.2.1 和注册修正前的 1.3.0 中间包都在 `build/rollback` 保留，旧核验记录另存。
- 最终构建遇到 Gradle 依赖仓库 TLS 握手等待；线程诊断确认不是源码编译报错。保留同一 ASCII 目录和 Flutter 生成的 `dart-defines` 等构建参数，改用 `gradlew.bat --offline ... assembleRelease`，13 秒成功。没有关闭 TLS 校验或改全局代理。以后重复此问题先检查网络元数据等待，再使用已有完整依赖缓存离线构建，不要反复清缓存或更换签名。构建日志见 `build/native-final-build.log`（42 项检查）及 `build/native-offline-build.log`（最终 APK）。
- 明暗首页及原生回复的图片为合成数据布局预览，测试字体不等同真机。未安装设备，未提交真实账号登录/注册、发帖、回复、私信或签到；这些服务端成功流程和设备视觉、玻璃性能仍需真机验收。附件上传、脚本专有插件和复杂验证码未完整适配，已列在原生入口审计中。

## 2026-10-26 账号资料黑屏与缺少退出（1.3.1+8）
- 用户真机反馈两个账号入口均黑屏且无法退出。上一版仅测试通用内容页路由，未检查账号资料的真实结构及原生可见字段，不应以“进入 NativeForumPage”代表资料适配成功。
- 独立只读浏览器核对官网 profile：#uhd h2 是昵称，#ct h2 含 UID，#ct li 的 em 为字段标签；.mn 中第一个子容器是空 DIY 区，资料实际在后续 .bm 中。未复制真实账号字段值、IP 或登录令牌到 fixture/文档。
- 新增 ForumAccount + ForumAccountPage 专门原生展示昵称/UID及资料字段，IP 字段不收集到展示模型；两个自身资料入口统一走此页。空资料显示可重试错误，不继续当成功页面。通用 HTML 内容也增加空内容检查与独立服务器提示。
- 资料页底部退出按钮始终存在，不依赖加载成功；我的页面另加退出入口。退出清除本机论坛 Cookie、取消旧 HTTP 与隐藏页面请求、清空隐藏验证文档，并通知首页清除旧账号内容；不调用全站 removeAllCookies，避免清理 QQ 或其他站点的登录。
- 原生清理只操作 bbs.binmt.cc 的 Cookie 名及官网常用 Path/Domain 作用域，完成后 flush；Dart 再核对 auth Cookie 为空才报告已退出。网络断开或资料解析失败也能退出。退出不代表注销账号或让所有设备下线。
- 修复还阻止已取消请求在退出后写回 Cookie 或转入旧页面读取后备，避免旧会话恢复。回归、布局预览和同签名 ARM64 APK 核验已完成，结果见下方；使用完整缓存的离线 Gradle，避免上轮仓库 TLS 等待。

## 最终交付核验（2026-10-26，v1.3.1+8）
- APK：`D:\App\MT论坛\MT论坛_v1.3.1_arm64.apk`，24,753,933 字节；包名 `bbs.binmt.cc`，应用名 MT论坛，版本 `1.3.1+8`，minSdk 24、targetSdk 36，仅 `arm64-v8a`。
- 48 项 Flutter 回归及 4 项生产 JS 登录桥接检查通过，覆盖真实结构的合成资料解析、空资料错误、加载失败仍可退出、取消退出保留会话、退出取消旧请求、旧页面内容失效。静态分析无错误或警告，保留一项花括号样式 info。日志见 `build/account-final-tests.log`；账号明暗预览为合成 fixture，不能当作真机视觉验收。
- 回归中发现退出确认框前启动无限进度动画会使等待界面稳定的测试超时；已改为确认后才启动退出进度，取消确认不触发会话清理。以后不能只验证路由类名，账号页必须断言昵称、UID、错误重试与退出按钮。
- 最终 ASCII 构建目录的 lib/assets/配置共 30 个文件与工程哈希一致，Android MainActivity.kt 单独核对一致；完整依赖缓存离线 Gradle 构建成功，耗时 30 秒，日志 `build/account-final-build.log`。
- v2 签名验证通过；证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975`；aapt/ZIP 核对包名、版本和单一 ARM64，`zipalign -c -P 16 4` 通过。用户图标源文件和 APK 图标资源均保持已核验版本的哈希。
- APK SHA-256：`c93c4ebb3e9b211f60496afd0507bc5878092c54726a48c11daeaa6edb8bedf0`。上一版包及签名/核验记录保留于 `build/rollback`，根目录只保留最新包；最新核验见 `build/release-verification.json` 和 `build/final-apk-signature.txt`。
- 本轮复用了临时 ASCII 目录 mt-forum-release-8a1648cf，该目录已是 1.3.1 源码，不能再充当 1.3.0 源码回退；上一版 APK 仍完整保留且哈希已核对。当前源码另存 `build/source-snapshots/v1.3.1`，不包含签名口令配置。
- 未安装到设备，未提交真实登录或退出请求；没有改变只读浏览器的账号会话。Android CookieManager 的真实清理、真实账号资料及重新登录仍需设备验收，自动化和签名校验不能替代这些结论。
## 2026-10-26 我的账号卡片与板块列表信息（1.3.2+9）
- 用户要求登录后顶部账号卡片展示头像、用户名与 UID，并删除下方重复的“已登录 · 账号资料”和“退出登录”；顶部卡片继续进入原生账号管理页，该页保留退出功能。未登录时顶部卡片显示登录/注册，只有一个入口。
- 我的卡片复用 ForumAccount 解析，补充官网 #uhd img 头像；进入我的时按当前会话读取，已有有效资料不重复请求，退出/账号变更清空，并忽略旧会话的迟到结果。失败显示明确提示，账号管理入口仍可使用。不把真实账号身份写入 fixture 或磁盘。
- 只读核对官网 forum-2-1.html：板块信息在 .comiis_listinfo/.comiis_infobox；置顶 tbody id 为 stickthread_；普通帖子 normalthread_，头像 .comiis_listtx img、作者 .km_user、浏览 .km_view、回复 .km_reply、发布日期在作者后 em span。原实现只取旧模板 .by，导致标题以外的信息全部遗漏。
- ForumDocument 增加板块信息，ForumLink 增加列表字段，原生 M3 板块头部显示图标、统计和简介；置顶分组紧凑显示，普通条目显示作者/头像/热度标记/日期/浏览/回复。按列表页真实数据展示，当前官网桌面模板没有提供摘要、点赞数及可靠身份标签，不伪造或逐帖抓取来补齐，避免每页额外几十次请求。
- 本轮同时限制板块链接只取 #threadlist，避免侧栏热帖混入；追加分页保留首屏板块信息，所有行在一次 build 中共用已过滤的普通帖列表，避免逐行重复筛选。仍沿用懒构建与现有分页/刷新。
- 新增当前模板合成 fixture、详情可见/分页、顶部昵称 UID/去重、退出后迟到身份检查；最终 51 项 Flutter 检查通过，明暗布局预览已核对；同签名 ARM64 APK 结果见下方。

## 最终交付核验（2026-10-26，v1.3.2+9）
- APK：`D:\App\MT论坛\MT论坛_v1.3.2_arm64.apk`，24,753,781 字节；包名 bbs.binmt.cc，应用名 MT论坛，版本 1.3.2+9；minSdk 24、targetSdk 36，仅 arm64-v8a。
- SHA-256：`fbdd3fe1b98b3194d131410ff5df0bab465438b6abadbb84e1c7a0386be0e297`。v2 签名通过，证书仍为 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975`；aapt/ZIP 包身份及单 ABI 校验通过，zipalign 16KB 校验通过。图标编译资源哈希保持原值。
- 51 项 Flutter 回归及 4 项生产 JS 登录检查通过，静态分析无错误/警告，仅既有一项花括号样式 info；测试日志 build/profile-board-tests.log。源码、资源、fixture 与配置 36 个文件和 ASCII 构建目录哈希匹配，Android MainActivity.kt 另外匹配；本次离线构建耗时 1 分 34 秒，日志 build/profile-board-build.log。
- 首页账号与板块明暗 fixture 预览：docs/preview-profile-dark.png、preview-profile-light.png、preview-board-dark.png、preview-board-light.png。使用合成身份和列表，不含真实账号数据；测试字体有部分缺字，不作为真机字体或图片加载验收。
- 上一版 APK 与核验/签名记录归档 build/rollback；根目录仅最新安装包。当前源码和工具快照另存 build/source-snapshots/v1.3.2，不含签名配置；临时 ASCII 目录已经复用为当前版本，旧版本回退依靠归档 APK 和对应稳定源码快照。
- 未安装到手机，未发送真实登录、退出、帖子或其他写请求。真实账号头像加载、资料返回以及设备布局仍需真机验收。官网当前桌面列表不含摘要/点赞数/可靠身份标签，本版不编造这些字段，也不逐帖额外抓取。
## 2026-10-26 首页排行榜与最新帖子遗漏（1.3.3+10）
- 用户指出上一轮只改板块，首页仍仅大号粗体标题、热帖无排名。首页热帖与最新不是相同信息层级：排行榜改为紧凑常规字重的带序号列表，显示官网前十顺序；更多进入官方排行榜。最新帖子复用板块 ThreadTile。
- 根因是首页 .boxbg_7ree 的 a[tips] 只取了标题，隐藏提示内的作者/时间/浏览/回复均丢弃。现在解析这些提示文本，不执行脚本；仅请求一次官方最新发表导读补充作者 UID 和详情，按线程 URL 合并到首页条目，不逐帖请求、不改变首页顺序。
- 已只读核对官方导读 tr/.by cite/.by em/.num 结构。修复原解析优先取 tbody 导致整个导读多行误用第一行作者的问题；板块置顶仍单独从 tbody id 判断。头像沿用已核对 UCenter CDN 的 UID 九位分段文件路径，缺失/加载失败使用原生头像后备，不保存身份到磁盘。
- 导读失败时保留首页提示中已有资料；异步结果沿用账号请求代次校验，旧账号不能覆盖新页面。新增导读逐行解析、首页排名/字号字重、最新详情、导读失败回归，并生成排行榜/最新明暗布局预览。
- 避免复发：共享列表模型或组件变化时，检索首页热帖、首页最新、板块及导读所有调用点；不能以板块预览通过替代首页可见内容验收。APK 与最终验证已完成，见下方。

## 最终交付核验（2026-10-26，v1.3.3+10）
- APK：`D:\App\MT论坛\MT论坛_v1.3.3_arm64.apk`，24,753,781 字节，包名 bbs.binmt.cc、版本 1.3.3+10，仅 arm64-v8a；SHA-256 `628fe4cc51847a49d84ddd9e1864f7bcd79ea1cadb30a42b1f4965d40ba6c27d`。
- 54 项 Flutter 回归及 4 项生产 JS 检查通过。静态分析无错误/警告，仅既有 native_forum_page.dart 花括号样式 info。源码/资源/fixture/配置 37 个文件和构建快照哈希一致，Android 源码单独匹配；离线构建 49 秒成功，日志 build/home-feed-tests.log、home-feed-build.log。
- aapt 核对包名、版本；ZIP 核对单 ABI；apksigner v2 和 zipalign 16KB 校验通过；原证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975` 与应用图标资源哈希不变。
- 首页排行榜和最新帖子的明暗 fixture 预览已生成并核对：docs/preview-ranking-dark.png、preview-ranking-light.png、preview-latest-dark.png、preview-latest-light.png；截图为合成数据与测试字体，不作为真机图片加载验收。
- 1.3.2 包与核验/签名记录归档 build/rollback，根目录仅新包；当前源码和工具归档 build/source-snapshots/v1.3.3，不含签名口令。主开发文档和入口审计同步到 D:\App\开发文档。
- 未在设备安装或执行真实登录等写操作。头像 CDN 加载和实际网络下的导读补充仍需真机验收；官网未返回正文摘要时不会虚构摘要。
## 2026-10-26 通用网页内容排版复盘与原生页面整理（1.3.4+11）
- 用户指出签到、消息、回复等页面只是把网页内容塞进原生容器，仍混有网页列表、下划线链接、CSS 图片数字和大量空白。上一轮“无可见 WebView”的检查只能证明渲染路径，不能证明已完成原生信息架构；以后必须核对各入口的可见排版、动作和状态。
- 只读核对官网签到 .lineB/.paiming/.qdright/.countqian/#ranklist 与消息页 .mn/.tb/.emp、侧栏 .appl .tbn；没有提交真实签到、私信或回复，不把真实身份/消息写入 fixture。
- 签到新增 ForumSignIn 语义模型和专用 M3 布局：账号/状态/操作、两列统计（大字号单列）、今日人数/站点信息/规则、原生排行导航和数据行。隐藏动画数字不参与展示，CSS 数字合并为 124天 等语义值；保留当次动态签到地址，失败不自动重试，账号变更阻断旧操作，按重新读取的服务器状态显示结果。
- 通用页把可识别的网页标签、分页、空状态、通知条目、资料字段、有表头且无表单控件的数据表格转成 M3 控件。消息补回原先丢失的通知分类，面包屑与重复网页标题移除；普通正文保留正常链接，表单动态字段/隐藏令牌和权限仍保留。保留资料条目的全部链接，不以只取一个链接丢失操作。
- 回复/引用回复重排：隐藏普通回复标题输入但保留原始 subject 提交值，引用用独立原生预览并可移除，编辑区只写新回复；提交时还原原引用 BBCode，不改服务器引用元数据。缩减输入框初始高度、去掉隐藏/提交控件造成的空白、主操作改为发送回复。普通发帖、注册、搜索继续共用原生表单。
- 新增签到语义与请求、成功/失败/大字号、消息导航空状态以及引用回复保留/移除相关回归；明暗签到/消息/引用预览纳入发布检查。原附件上传和复杂脚本验证码边界仍在；非空私信会话和每个插件的所有布局不能仅凭通用控件宣称完成验收。

## 最终交付核验（2026-10-26，v1.3.4+11）
- APK：`D:\App\MT论坛\MT论坛_v1.3.4_arm64.apk`，24,884,869 字节；bbs.binmt.cc，1.3.4+11，minSdk 24、targetSdk 36，仅 arm64-v8a。SHA-256 `bd735f0e2b65feef5f53833cce790732eabceadf38bac88ef0759b81d4be10f9`。
- 最终 60 项 Flutter 回归与 4 项生产 JS 登录检查通过；静态分析无诊断。最终预览又发现消息空卡宽度和分类层级不足，修正为通栏卡、带选中状态的分段导航及独立主操作，并重新验证。日志 build/native-layout-tests.log，离线 Gradle 构建 44 秒，日志 build/native-layout-build.log。
- 最终 lib/assets/test/配置与 ASCII 构建快照一致，Android MainActivity.kt 另外一致。aapt、APK ZIP、apksigner v2、zipalign 16KB 全部通过。证书仍为 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975`，用户图标资源哈希未变。
- 签到、消息、引用回复的明暗 fixture 布局预览已逐张检查：docs/preview-sign-*.png、preview-messages-*.png、preview-quote-*.png；含合成状态及测试字体，部分测试字形缺失，不能代替真机字体/图片加载验收。360dp 双倍字体的签到与消息无布局溢出。
- 1.3.3 APK 和核验/签名记录归档 build/rollback；根目录只保留本版。源码和工具快照 build/source-snapshots/v1.3.4，不含签名口令；发布脚本已同步版本和预览清单。主文档与入口审计同步 D:\App\开发文档。
- 未连接手机安装；未执行真实私信、回复或签到。已只读核对官网签到与消息空页，非空真实私信会话、未识别的不规则插件表格仍需逐页设备验收，不以此次通用排版转换宣称全站布局完成。未知表格保留原内容而不丢信息，附件上传和复杂验证码限制不变。
## 2026-10-26 帖子列表、快捷回复、收藏与历史（1.4.0+12）
- 用户要求帖子作者头像和论坛默认头像正确展示；回复不再跳转单独页面，而在帖子底部展开工具栏/输入/发送；板块对齐参考图的信息密度、小红色置顶标记、摘要与身份等信息。
- 已只读核对官网帖子 .avtm img、.pls 用户组链接、#recommendv_add 和正常回复/引用 URI。帖子详情此前根本未解析头像，UI 只显示用户名首字；默认头像加载失败也变成通用人形。新增共用 ForumAvatar，读取真实头像，官网 noavatar 或加载失败时显示下载的原始 noavatar_middle.gif（120×120、单帧 GIF，未经修改），扩展到列表/帖子/账号/签到。新图只用于用户头像，不改变用户指定应用图标。
- 找到官网 forum.js 的 previewThread 只读预览实现，但 preview 响应包含整页回复且不包含用户组和点赞；列表摘要使用受会话保护的首楼读取。仅可见/缓存范围内条目按需请求，最多两个并发，不预取全部帖子；每页最多 60 个轻量摘要 Future，仅内存，账号变更/显式刷新失效。摘要请求仅走 HTTP，不占用隐藏浏览器，避免阻塞用户导航和登录；无法读取时保留已有列表信息，不虚构内容或绕过隐藏回复。
- 板块缩小卡片圆角、外边距和正文留白，置顶用小红色非交互标签和紧凑行；四个筛选按钮等宽胶囊。帖子条目显示真实作者/头像/角色、两行摘要、浏览/回复/点赞与日期；数据不足时不填假值。仍保留至少 48dp 的整行点击区域与大字号换行。
- 快捷回复复用 NativeForumFormView 的动态字段、验证和 BBCode 组合，使用帖子底部原生编辑栏，带表情/加粗/链接/引用/代码/网络图片工具；图片插入是 HTTPS 网络图片地址，尚未实现本地附件上传。收起不丢草稿，换引用/离开时确认放弃，发送失败保留输入，不自动重发；提交前核对账号会话、只在服务器确认后清草稿并刷新。
- 帖子头像及默认头像、作者/角色/UID/摘要、快捷回复草稿/引用/失败处理与窄屏键盘预览均已实现。帖子详情头像仍需在可访问论坛网络的设备上实际加载验证。
- 同轮追加收藏/历史与冗余入口：删除“我的”中底栏已覆盖的“论坛首页”，检查账号/设置页未发现另一个同目的首页入口；账号资料与退出仍集中在账号管理页，既有去重不回退。
- 收藏根因是通用表单转换把 #delform 的 favorite[] 当用户字段，正文链接又脱离表单。现在按 #favorite_ul > li 配对收藏 ID 和同一行帖子/板块链接，排除删除链接；专用列表保留分类/分页与管理模式，默认不显示复选框，管理时选择后原生确认，携带当前隐藏令牌/按钮值删除。失败保留选择，不自动重试；服务端确认成功才重读列表。未识别模板显示读取失败，不把它伪装为空收藏。
- 首页最新、收藏帖子、历史均复用 ThreadTile，首楼摘要增加作者与 UID，用同一套头像/角色/标题/两行摘要排版；收藏当前页条目和历史按需补充，HTTP 最多两个并发。历史磁盘格式保持标题/地址/副标题，不持久化账号身份或私密正文；重新打开按当前会话补全。无权读取或离线时保留原有标题，不伪造内容。
- 预览复盘：ThreadTile 外层列没有拉伸导致只有标题的条目居中，改为通栏左对齐；作者/角色/UID 改可换行布局。快捷回复链接对话框最初在路由退出动画前释放控制器，引发 used after dispose；改为对话框 State 自行持有并随路由卸载释放，回归覆盖关闭后继续输入。
- 摘要并发测试最初仅等待一个零时长事件，Dio 拦截器尚未进入适配器导致误判 0 请求；改为适配器真实就绪信号，不放宽并发上限断言。首页增加摘要后补齐 FakeClient 桩，避免 widget 测试触发真实 HTTP/遗留超时定时器。
- 最终 71 项 Flutter 检查通过，包含收藏同一行解析、原生卡片、删除确认/失败保留/成功重读、迟到响应账号隔离、历史重新打开不存正文、明暗预览与账号失效；静态分析无诊断，4 项生产登录 JS 检查通过。

## 最终交付核验（2026-10-27，v1.4.0+12）
- APK：[MT论坛_v1.4.0_arm64.apk](../MT论坛_v1.4.0_arm64.apk)，25,020,552 字节。包名 bbs.binmt.cc、版本 1.4.0+12、minSdk 24、targetSdk 36，仅 arm64-v8a；SHA-256 `7fc476aa4d4cdd17d1321b61f936ccfc0be6433ad234c87a21767478970e7f48`。
- aapt 包信息、apksigner v2、证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975` 和 16KB zipalign 全通过。原 icon16.png 源及 APK 原编译图标资源哈希不变；论坛默认头像 GIF 资源与项目原文件哈希一致。
- 同步源码静态分析无诊断，71 项 Flutter 自动化及 4 项生产登录 JS 检查通过。Gradle 离线 ARM64 release 构建成功，耗时约 1 分 10 秒。日志：build/thread-collection-final-tests.log、build/thread-collection-final-build.log；核验清单：build/release-verification.json。
- 已逐张检查版块、帖子、快捷回复、收藏、历史明暗预览：docs/preview-board-*.png、preview-thread-*.png、preview-composer-*.png、preview-favorites-*.png、preview-history-*.png。预览为合成账号内容；字体缺失的图只作为几何检查，不能替代手机字体与 CDN 实际加载验证。
- 回退 APK `build/rollback/MT论坛_v1.3.4_arm64.apk` 保留并核对原 SHA-256；稳定源码快照 `build/source-snapshots/v1.4.0` 与参与构建源码一致，不含本地签名口令。根目录仅保留最新 APK。开发文档与原生入口审计同步至 D:\App\开发文档。
- 未安装到手机，未提交真实收藏删除、登录、发帖、回复或签到请求；收藏写操作目前由动态表单 fixture 验证，真实账号网络验收仍待用户设备完成。快捷回复工具支持插入 HTTPS 网络图片地址，本地文件上传尚未实现。
## 2026-10-27 悬浮底栏重复点击动效（1.4.1+13）
- 用户反馈点击底栏先出现目标位置的点击态，再出现胶囊移动，要求只保留原胶囊位移。根因是普通悬浮项 InkWell 继承全局水波纹和按压高亮，同时 AnimatedSlide 自己移动；Review 同款组件已明确将 splash/highlight 设为透明。
- 普通悬浮项仅在底栏设置透明 splash/highlight，保留全局水波纹工厂的触感调用和 selectTab 的反馈去重；原选中胶囊仍以 240ms 滑动，系统要求减少动画时取消位移动画。标准 M3 底栏仅将 pressed overlay 设为透明，focused 状态继续交由主题处理。
- 液态玻璃底栏使用 GlassInteractionBehavior.none 去掉按压发光和缩放；底层 TabIndicator 还会按下时启用厚度/果冻形变，因此设置 indicatorPinchStrength=0 抑制点击的额外形变，保留指示器移动。拖动手势仍由组件原有逻辑处理。
- 静态分析无诊断，21 项 widget 检查通过，覆盖按住时胶囊不提前跳动、释放后中间与终点位移、玻璃参数和标准底栏 pressed/focus 状态，且覆盖现有导航、登录和大字号。真机触感及液态玻璃渲染还需设备验收。
## 最终交付核验（2026-10-27，v1.4.1+13）
- APK：`D:\App\MT论坛\MT论坛_v1.4.1_arm64.apk`，25,020,552 字节，包名 bbs.binmt.cc，版本 1.4.1+13，仅 arm64-v8a；SHA-256 `4db23cfcd80a5c63b6c6f65847ba6da9947d0f593971e9b50a97102b7fd99d18`。
- aapt 包信息、apksigner v2、证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975`、16KB zipalign 和原图标资源哈希均通过；离线构建 1 分 17 秒。静态分析无诊断，21 项 widget 回归通过；日志 build/navigation-motion-tests.log、build/navigation-motion-build.log。
- 1.4.0 APK、核验和签名记录归档 build/rollback，并验证旧包 SHA-256；本版不含签名口令的源码快照 build/source-snapshots/v1.4.1 已保存，项目 lib/assets/test/pubspec 与实际构建快照一致。
- 未安装到手机；普通/液态玻璃底栏的触感、视觉效果及设备帧率尚需真机验收。标准底栏只关闭按压态，键盘焦点状态保持主题默认处理。
## 2026-10-27 消息页作为底栏页面（1.4.2+14）
- 用户指出消息虽在底栏，点击却走 openSite 新路由，底栏选中胶囊不移动，切屏动画与首页、发现不一致。消息改为 IndexedStack 内的同级标签，顶栏通知按钮也选中同一标签，首次进入才加载；切换标签保留已加载消息、分类与滚动位置，不自动反复刷新。
- 复用 NativeForumPage 的解析和 M3 消息布局，以嵌入模式隐藏重复顶栏、使用外层留白和刷新按钮。消息/提醒分类及分页在同一标签内读取；发送消息等独立操作仍沿用原生页面。访客在消息标签看到登录提示，主动登录或取消后底栏和标签保持；过期会话在标签内提示重新登录，不弹出时误关闭首页。
- 按返回键从消息标签回首页；如果页面有未提交编辑内容先确认，提交中不丢失状态。账号变化更换页面 key 并隔离旧请求，避免旧账号消息覆盖当前账号。触感、底栏胶囊的原有移动及 1.4.1 去除水波纹行为保留。
- 已核对消息标签明暗合成预览 docs/preview-messages-tab-dark.png、preview-messages-tab-light.png；76 项 Flutter 回归和 4 项登录桥接检查通过，覆盖访客、原生登录成功/取消、底栏及顶栏入口、分类原位切换、标签返回/状态保留和账号切换迟到请求。实际非空消息、真实登录及设备动画仍需真机验证。
## 最终交付核验（2026-10-27，v1.4.2+14）
- APK：`D:\App\MT论坛\MT论坛_v1.4.2_arm64.apk`，25,020,552 字节，包名 bbs.binmt.cc，版本 1.4.2+14，仅 arm64-v8a；SHA-256 `8d543d86d1c77762c6c4309f391b78206f4a55d3eb7ff3075b84dcb1592df664`。
- aapt 包信息、apksigner v2、证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975`、16KB zipalign 和原图标资源哈希均通过；离线构建 48 秒。静态分析无诊断，76 项 Flutter 回归与 4 项登录桥接检查通过；日志 build/messages-tab-tests.log、build/messages-tab-build.log。
- 1.4.1 APK、核验及签名记录归档 build/rollback 并验证旧包哈希；本版不含签名口令的源码快照 build/source-snapshots/v1.4.2 已保存，项目 lib/assets/test/pubspec 与实际构建快照一致。
- 未安装到手机，也未进行真实账号登录或真实消息收发；消息标签明暗预览和测试使用合成数据，真机效果及真实非空消息仍需验收。

## 2026-10-27 消息页两级顶栏（1.5.0+15）
- 一级 M3 顶栏按用户指定列出“消息、我的帖子、坛友互动、系统提醒、应用提醒”；子分类从当前同源官网响应的 `.tb` 提取，仅接受相同消息/提醒分类路径。切分类继续复用底栏常驻的嵌入页面，不另开网页或切屏。
- 嵌入消息页从正文移除重复的网页分类栏和侧栏导航，页面操作如“发送消息”“筛选设置”保留在 M3 内容区。当前响应无子项时只显示一级栏。正文顶部偏移按实际显示一行或两行计算；Review 磨砂顶栏的单条底边随最后一行移动。
- 回归覆盖消息一级/二级切换、官方“我的帖子”六个子项、操作保留、单行/双行边界对齐；当前其他分类的二级列表仍按服务端实际响应展示，不预设未核验内容。明暗预览：`docs/preview-messages-tab-dark.png`、`docs/preview-messages-tab-light.png`，为合成空消息数据。
- 静态分析无诊断；77 项 Flutter 测试及 4 项官网登录 JS 检查通过。Flutter CLI 首次触发的在线 Gradle 构建卡在 Maven TLS 握手，取消后按项目离线流程使用缓存构建成功，日志分别在 `build/message-top-tabs-online-attempt.log` 与 `build/message-top-tabs-build.log`。

## 最终交付核验（2026-10-27，v1.5.0+15）
- APK：`D:\App\MT论坛\MT论坛_v1.5.0_arm64.apk`，25,086,088 字节，包名 `bbs.binmt.cc`，版本 `1.5.0+15`，应用名 MT论坛，仅 `arm64-v8a`；SHA-256 `6c899af6de720d03be13d48f71cfa3efff453f4f02d0ff7c83ba60907e5a1229`。
- aapt 包/应用名和版本、apksigner v2 证书摘要 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975`、16KB zipalign 及 APK 图标资源哈希 `6cc19ee2603f723038dc8771b389f86da56ce0791ae1af765c754c2adc4044a1` 均核验通过。清单见 `build/release-verification.json`；签名详情见 `build/final-apk-signature.txt`。
- v1.4.2 APK 已归档为 `build/rollback/MT论坛_v1.4.2_arm64.apk` 并核对旧哈希 `8d543d86d1c77762c6c4309f391b78206f4a55d3eb7ff3075b84dcb1592df664`。v1.5.0 源码快照 `build/source-snapshots/v1.5.0` 不含本机签名配置；根目录仅保留当前版本 APK。
- 尚未安装到手机。测试与预览用合成消息数据；真实登录账号下各分类实际二级项和设备字体/磨砂观感仍需在论坛可访问的设备上确认。离线 release 编译和安装包签名已完成。

## 2026-10-27 消息顶栏窄屏裁字修复（1.5.1+16）
- 用户真机截图显示“我的帖子”“坛友互动”“系统提醒”“应用提醒”等一级标签尾部被截断。1.5.0 强制五等分，上一轮使用 390dp、Windows 中文字体的预览未覆盖更窄屏幕或放大字号，因此不能据此声称真机适配完成。
- 一级与二级均采用 M3 可横向滚动标签，按文字自然宽度分配；字号增大时分栏高度和内容顶部偏移一起增长，磨砂底边仍位于最后一行。最后一个一级分类可横向滑动并点击；不压缩系统字体。
- 360dp 下以中文字体和 1.0、1.4、2.0 倍字号检查每个标签的实际文字宽度，验证无标签内部裁切及最右分类可点击；59 项消息、UI 和预览相关 Flutter 检查通过，静态分析无诊断。`docs/preview-messages-scaled-dark.png` 是 360dp、1.4 倍字号的合成数据预览，不能代替 Android 真机验收。
- 用户截图没有显示消息二级栏，可能是官网响应没有子项，也可能是解析未覆盖实际模板；现有 Chrome 登录标签读取超时，本轮未能核实，未用合成 fixture 推断真实官网内容。当前规则仍仅显示从当前官网页面读取到的同源子项。
- 修复离线发布脚本遗漏：直接调用 Gradle 时必须同步临时 Android `local.properties` 的版本名和版本号；只更新 Dart defines 不能保证 APK manifest 版本正确。旧 BKS 对应签名保持不变。

## 最终交付核验（2026-10-27，v1.5.1+16）
- APK：`D:\App\MT论坛\MT论坛_v1.5.1_arm64.apk`，25,086,092 字节，包名 `bbs.binmt.cc`，应用名 MT论坛，版本 `1.5.1+16`，仅 `arm64-v8a`；SHA-256 `162b24e7b64b1b5418aeba19b54cc7ca15219856b9ec86706a45cfa34ec9471f`。
- 离线 Gradle release 成功；aapt、apksigner v2、既有证书摘要 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975`、16KB zipalign、原图标资源哈希均通过。日志 `build/message-overflow-build.log`、`build/message-overflow-tests.log`、`build/message-overflow-preview.log`；核验清单 `build/release-verification.json`。
- v1.5.0 APK 和核验记录已归档 `build/rollback` 并核对 SHA-256 `6c899af6de720d03be13d48f71cfa3efff453f4f02d0ff7c83ba60907e5a1229`；源码快照 `build/source-snapshots/v1.5.1` 不包含本机签名配置。根目录仅保留新 APK。
- ADB 未发现连接设备，未安装或在真实论坛账号下验收；二级分类实际返回及 Android 设备字体、顶栏滑动效果仍需复核。

## 2026-10-27 通知“查看”显示帖子原网页结构（1.5.2+17）
- 用户截图显示“查看”页面把帖子作者栏、头像、楼层及正文按网页 HTML 通用布局直接排出，未使用已有原生帖子页。实际账号通知 URL 本轮不可取得，不能断言该条链接的具体参数。
- 路由现在识别论坛同源 `mod=redirect&goto=findpost` 中的 `ptid` 和仅有 `pid` 的链接，并保留原始 URL 交给论坛解析跳转；`openForumWeb` 和原生消息链接统一分派至现有帖子页。若未识别的入口返回包含主题与帖子正文的 HTML，通用页改为直接以已获取内容替换为原生帖子页，避免再次请求及原网页排版。
- 已解析的帖子编号来自原始或最终地址、同源 canonical、或同源回复表单；快捷回复和收藏使用实际编号，无法识别时不发送 `tid=null` 请求。服务器跳转可能定位到包含目标回复的页面，但原生列表尚未保证自动滚至目标楼层。
- 77 项论坛、通知、原生帖子与 Widget 检查通过，含 `ptid`、仅 `pid`、未知入口返回帖子三种合成路径，检查原生头像/帖子与回复编号；静态分析无诊断。真实消息 URL、用户账号权限与回复楼层定位仍需设备验收。

## 最终交付核验（2026-10-27，v1.5.2+17）
- APK：`D:\App\MT论坛\MT论坛_v1.5.2_arm64.apk`，25,086,088 字节，包名 `bbs.binmt.cc`，应用名 MT论坛，版本 `1.5.2+17`，仅 `arm64-v8a`；SHA-256 `1a9ee4cf36ab8006c59dbf31e336f303834d1bf5bf2141254d82e78f4f9db9b7`。
- 离线 Gradle 构建成功；aapt、apksigner v2、既有签名证书 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975`、16KB zipalign 与原图标资源哈希通过。日志 `build/notice-thread-build.log`、`build/notice-thread-tests.log`、`build/notice-thread-analyze.log`；核验清单 `build/release-verification.json`。
- v1.5.1 APK、签名和核验记录归档 `build/rollback`，旧包 SHA-256 `162b24e7b64b1b5418aeba19b54cc7ca15219856b9ec86706a45cfa34ec9471f`；源码快照 `build/source-snapshots/v1.5.2` 不含签名配置。未安装到设备或访问真实通知内容。
## 2026-10-27 帖子正文换行首次尝试（1.5.3，真机确认无效）
- 初次尝试在 ForumPage.customStylesBuilder 覆盖 white-space:nowrap，但真机上同一条通知回复仍被裁切。复查 flutter_widget_from_html_core 发现该回调先于元素自带的行内样式应用，因此原样式会把覆盖值盖回去；此版不能视为修复完成。
- 发布脚本曾因继承到 JDK 26.0.1 而在 Android JDK 镜像转换阶段失败。现在脚本选择已安装的 D:\jdk17（17.0.12），并在结束时恢复调用环境原 JAVA_HOME，避免同类构建错误复发。
- 发布 APK：D:\App\MT论坛\MT论坛_v1.5.3_arm64.apk，25,086,088 字节；包名 bbs.binmt.cc，版本 1.5.3+18，仅 arm64-v8a。SHA-256：60b08e12371f5ea17c8868fed9609dba6090daa9f6dfb0a825d88dd42bae7f7f。
- aapt 包名/应用名/版本、apksigner v2 证书摘要 3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975、16KB zipalign、ARM64-only ABI 与原始 icon 资源哈希均通过。核验清单 build/release-verification.json，签名记录 build/final-apk-signature.txt，构建摘要 build/post-content-wrap-build.log。
- 1.5.2 APK 和版本核验/签名记录已备份至 build/rollback；旧 APK 哈希已核对。源码快照 build/source-snapshots/v1.5.3 不包含签名配置，编译临时源 lib/assets/packages 与项目源码哈希一致。
- 已在连接设备安装并打开 v1.5.3，UIAutomator 和屏幕截图都确认目标消息仍是一行并被卡片裁切。测试套件和 dart analyze 未运行；核验记录已移入 build/rollback/v1.5.3-release-verification.json。

## 2026-10-27 帖子正文强制换行（1.5.4+19）
- 修复移到 parseForum：把正文内的 white-space:nowrap 改为 white-space:normal，移除 nowrap 属性，并为 nobr 元素添加正常换行样式；链接仍允许在必要时断开，pre/blockcode 保留预格式文本。帖子详情和通知进入帖子详情共用 ForumPost 与 ForumPage，修复覆盖所有楼层。
- APK：D:\App\MT论坛\MT论坛_v1.5.4_arm64.apk，25,086,088 字节；包名 bbs.binmt.cc，版本 1.5.4+19，仅 arm64-v8a。SHA-256：b25b6161afa25b2b2a4d925d5d864f350d523a97d4165dd712f1f69dfb69ca88。
- aapt 包信息、应用名、apksigner v2 证书、16KB zipalign、arm64-only ABI 和原始图标资源哈希均已核对；摘要 build/post-content-wrap-v1.5.4-build.log，清单 build/release-verification.json，签名记录 build/final-apk-signature.txt。JDK 26 导致的首次构建失败已在 v1.5.3 修复的发布脚本中处理：使用 D:\jdk17 并恢复调用环境。
- v1.5.3 APK、核验记录和签名记录已归档至 build/rollback；v1.5.4 源码快照 build/source-snapshots/v1.5.4 不含签名文件，lib/assets/packages 和编译临时源哈希一致。根目录只保留 v1.5.4 APK。
- 1 项针对 nowrap 正文的 Flutter Widget 回归检查通过，验证窄屏帖卡正文实际换成多行；完整测试套件和 dart analyze 未运行。v1.5.4 安装更新被 Android 拒绝（INSTALL_FAILED_ABORTED: User rejected permissions），设备仍保留 v1.5.3，因此新包断行效果未在设备确认。
## 2026-10-27 帖子边界、筛选设置和通知卡片（1.5.5+20）
- 用户反馈 v1.5.4 的帖子正文仍被裁切。楼层正文外层明确限定为卡片可用宽度；解析时移除非图片元素的固定宽度，并将单行单格排版表格转换为普通容器，保留文字、链接、图片及代码格式。360dp 回归包含固定宽度、nowrap、单格表格和卡片边界；复杂多列表格仍需真实内容验收。
- 通知使用专用卡片：正文保留时间、用户和通知内容，只剥离正文中的“屏蔽”“查看”操作文字，操作区只呈现官网给出的这两个链接。我的帖子、坛友互动、系统提醒和应用提醒均覆盖同一解析路径；私人消息沿用原来的会话处理。四类回归使用合成数据，尚未逐类获取真实账号通知验收。
- 筛选设置从同源官网响应提取顶部标签，放入 Review 磨砂顶栏，切换在当前页面完成；未保存时先确认。按官网表格分组渲染规则、说明、复选项及对应保存按钮，直接读取 label 或表格行标题，保留隐藏令牌、原字段和值。有关结构参考 Discuz 默认模板：https://gitlab.rails365.net/hfpp2012/docker-for-discuz/blob/master/discuz/html/template/default/home/spacecp_privacy.htm 和 https://gitlab.rails365.net/hfpp2012/docker-for-discuz/blob/master/discuz/html/template/default/home/space_notice.htm；这些模板不代表已验证本站全部真实页面。
- 74 项相关 Flutter 检查通过，包括四类通知、筛选表单值与令牌、取消切换、360dp 双倍字号和磨砂分界、帖子固定宽度及布局表格；dart analyze lib 和 dart analyze test 无诊断。完整仓库分析还报告液态玻璃第三方包既有的提示级诊断，本次未改该包。
- APK：D:\App\MT论坛\MT论坛_v1.5.5_arm64.apk；25,086,084 字节；包名 bbs.binmt.cc，版本 1.5.5+20，minSdk 24、targetSdk 36，仅 arm64-v8a。SHA-256：08b7171fa56b3f167b5849eb710c3ba0b7275dbf0219e754a050ae193f815cc3。
- aapt 包信息、apksigner v2 既有证书、原 icon 资源哈希和 16KB 对齐已核验。日志 build/message-layout-v1.5.5-tests.log、build/message-layout-v1.5.5-privacy-tests.log、build/message-layout-v1.5.5-analyze.log 和 build/message-layout-v1.5.5-build.log；核验清单 build/release-verification.json。
- v1.5.4 APK、签名和核验记录归档 build/rollback，已校验旧包哈希；无签名材料的源码快照为 build/source-snapshots/v1.5.5，正式编译用 lib/assets/packages 与项目哈希一致。设备当前安装 v1.5.4，本轮未安装 v1.5.5；新包真实通知、复杂正文和筛选保存仍需设备验证，未执行真实屏蔽或保存操作。

## 2026-10-27 版本名回退（1.0.0+20）
- 用户要求应用版本名恢复为 1.0.0。pubspec、关于页和发布脚本校验/文件名已同步；Android versionCode 保持 20，允许覆盖此前已安装的低 versionCode 构建。
- 历史 v1.5.x 记录不改写；本次只改变版本名，不代表功能源码回退。

- 版本名回退正式包：D:\App\MT论坛\MT论坛_v1.0.0_arm64.apk，25086084 字节，版本 1.0.0+20，包名 bbs.binmt.cc，仅 arm64-v8a，SHA-256 c6e4e12aec7fef1e8390791e7f5bdf5da6474bd4a43545b8ad10a3b0c1ea2735。BUILD SUCCESSFUL；aapt、apksigner v2 和 zipalign 16KB 核验通过。只对版本元数据重新构建，未重跑 Flutter 测试/分析，未安装到设备。旧 v1.5.5 包及核验记录保存于 build/rollback。

## 2026-10-28 搜索原生列表与首页连续加载（1.0.0+21）
- 搜索请求此前先展示了用于取得动态搜索令牌的首页 HTML，再把搜索结果交给通用 HTML 渲染器。现在取得表单和提交期间不设置可见 document；结果原位使用 ForumPage/ThreadTile，保持同一路由，解析作者、头像、摘要、回复/浏览及日期，使用官网下一页地址。
- 首页最新此前只渲染前 5 条，导读仅用于补全元数据。改为显示最新发表导读列表及其分页；惰性构建帖子卡片，页内与跨页按 URL 去重。加载失败保留已有列表并提供重试；请求受账号及刷新代次限制，重复/已读分页地址停止自动加载。
- 首页禁用边缘拉伸与过度滚动装饰，保留下拉刷新；分页状态区保留最小高度，减少触底状态变动造成的跳动。真实设备上的 GPU/液态玻璃闪烁仍需设备观察。
- 必要检查：6 项搜索/首页专项测试通过，包含延迟搜索期间不显示首页、搜索字段/令牌/原生卡片、分页去重及反复触底不重复请求、导读失败回退；dart analyze lib test 无问题。日志 build/search-feed-tests.log、build/search-feed-analyze.log。未扩大到全套回归，未安装设备或执行账号写操作。
- 版本名沿用用户指定的 1.0.0；versionCode 增至 21。GitHub main 已有初始源码及版本名回退提交（4dffb5508d76c2114b8dd58188b8c2390de3ef77）；项目根目录没有 .git，推送检出位于 build/github-push-checkout，不上传 APK、签名文件或构建缓存。
- 正式包：MT论坛_v1.0.0_arm64.apk，25,086,088 字节，SHA-256 5e3e4fcede409da31f5a0a8a0d1c92d5ff63348c90d273b505618d244177b8d8。构建成功，aapt 确认 1.0.0+21 / bbs.binmt.cc，ZIP 仅 ARM64-v8a；既有签名证书、原图标资源哈希、16KB 对齐以及 190 个生产源码/资源文件与编译目录一致性核验通过。核验清单 build/release-verification.json；code20 的同名 APK 已存 build/rollback/MT论坛_v1.0.0_code20_arm64.apk，避免与早期 1.0.0 回退包混淆。

## 2026-10-28 发现搜索对齐、触感与文案（1.0.0+22）
- 发现页只读 SearchBar 的 leading 增加 8dp 起始内边距，搜索图标和文字同步右移，图标起始位置与下方列表图标对齐；不改变整条搜索栏触摸范围。
- SearchBar 内部输入框消费文字区域点击，无法触发全局 HapticSplashFactory；图标/外层点击则能触发，因此此前存在触感不一致。只读搜索入口及编辑搜索栏显式调用同一 light 反馈，保留现有 splash 去重与触感总开关；键盘提交也与搜索按钮一致。
- 排查非 Material 点击入口，补齐帖子图片 GestureDetector 和两处 HTML 正文链接的同一反馈。不在文本输入或图片缩放/拖拽过程中增加连续震动，不另设反馈开关。
- “精华采撷”是原始中文文案，并非乱码；按用户要求改为“精华内容”。对 lib 和资产 JS 共 23 个文件严格 UTF-8 解码并检查替换字符与常见乱码模式，未发现其他本地 UI 编码问题；网站动态内容不在此静态检查保证范围内。
- 3 项必要专项测试通过：搜索图标/文字/空白和编辑栏启用时各一次反馈、关闭时均无反馈、搜索图标位置及精华文案、底栏原有胶囊动效；dart analyze lib test 无问题。日志 build/discover-haptics-tests.log、build/discover-haptics-analyze.log。平台触感调用已检查，未作实际手机马达或视觉验收。
- 版本名保持 1.0.0，versionCode 增至 22；本轮未要求再次推送 GitHub，源码和文档先保存在本机。旧 code21 同名包保留至 build/rollback/MT论坛_v1.0.0_code21_arm64.apk。
- 正式包 MT论坛_v1.0.0_arm64.apk：25086084 字节，SHA-256 d0471c970d12520c6afc962bd09214e09c64f66b846f812a3df6bcebd90d7359；aapt 确认 bbs.binmt.cc / 1.0.0+22，单 ARM64-v8a、原签名证书、原图标哈希与 16KB 对齐核验通过，190 个生产源码/资源文件与编译目录一致。构建日志 build/discover-haptics-build.log，核验清单 build/release-verification.json；仍未安装到真机。

## 2026-10-28 排行榜专用原生卡片（1.0.0+23）
- 用户截图证实排行榜仍由通用 HTML 渲染：作者/标题重复成为正文和按钮，缺少名次且留白过大。排行榜改为专用 ForumRanking 模型与惰性原生卡片列表，不经过 HtmlWidget、通用消息卡片或网页数据表格适配器。
- 已匿名只读核对官网 misc.php?mod=ranklist 的总览、type=thread&view=replies&orderby=thismonth、type=member、type=forum&view=threads 四份实际响应。总览按官网列表顺序显示名次；具体榜单读取数字及前三名图片 alt，不能只读 .icn 文本。非总览缺失合法名次的行不猜排名。帖子行展示一次标题、作者头像/昵称及官网统计，用户/版块排行使用同样的紧凑卡片。
- 从当前响应提取全部/用户/帖子/版块顶栏，以及对应次级榜单；时间范围使用正文原生选择控件。更多、分类、统计口径和时间切换都在同一页面更新，磨砂分界位于末级顶栏下方，保留官网同源链接和顺序，不额外逐帖抓取摘要。
- 注意实际官网帖子/版块排行 .ct2_a 缺少 id=ct，解析应使用 .ct2_a .mn；不能只依赖 #ct。总览 .xl li、详情 .tl tr 和用户 .hasrank dl 是三种不同结构。
- 必要检查：四份官网主体响应移除脚本/事件后作为公开 fixture；6 项解析/Widget 检查通过，覆盖图片名次、唯一内容、作者与统计、分类、360dp 普通/双倍字号、更多原位切换和顶栏高度。曾发现旧的“更多”按钮焦点在懒列表复用后触发自动滚动，现按响应 URI 更新列表 key、切换前清理旧焦点，并在新布局完成后回到顶部。dart analyze lib test 无问题。日志 build/ranking-tests.log、build/ranking-analyze.log。
- 版本名保持 1.0.0，versionCode 增至 23；未在真机验收，未提交论坛写操作，本轮未要求推送 GitHub。旧 code22 包与签名/核验记录归档 build/rollback。
- 正式包 MT论坛_v1.0.0_arm64.apk：25086084 字节，SHA-256 1b579f4addd4b0d4b7d72d7d153c8a04c121d4044dc9467a139cba3343b7f62c；aapt 确认 bbs.binmt.cc / 1.0.0+23，单 ARM64-v8a、原签名证书、原图标哈希与 16KB 对齐核验通过，190 个生产源码/资源文件及 pubspec 与编译目录一致。构建日志 build/ranking-build.log，核验清单 build/release-verification.json；未安装真机。

## 2026-10-28 首页帖子批量列表滑动性能（1.0.0+24）
- 根因：发现页“最新发表”直接使用导读列表数据；首页每个 `ThreadTile` 则在进入列表时调用一次 `threadSummary`（每次返回再触发卡片重绘），并且冷启动先显示首页少量预览、随后再替换成导读页。两条路径看起来相似，首页实际多出逐帖 HTTP 请求和一轮列表替换。
- 首页冷启动现在先读取官方“最新发表”导读结果，若首批不足 20 条且有下一页，则继续读取到约 20 条后一次性展示；首页区块返回的少量帖子只作为导读请求失败时的回退。刷新过程中保留已有列表。
- 首页最新列表与发现页一样只使用导读响应携带的数据，不在卡片滚入视口时逐篇请求摘要或令每张卡片异步更新；列表继续惰性构建。首批到约 20 条后，滚动到末尾前 600dp 时再取下一页，保留 URL 去重、重复分页保护和失败重试。
- 导读列表没有提供摘要、用户组或点赞数时不再额外请求每篇帖子补齐，因此这些字段按服务端列表实际返回值展示；保留列表提供的标题、作者、头像、日期及浏览/回复数。若以后要保留逐帖摘要，需先有官方批量接口或缓存策略，避免恢复逐条网络请求。
- 版本名保持 1.0.0，versionCode 增至 24。必要检查为 Dart 静态分析、ARM64 release 构建及包身份/ABI/签名/16KB 对齐核验；本轮不运行额外 Flutter 测试，未安装真机。
- 最终 ARM64 正式包：`MT论坛_v1.0.0_arm64.apk`，25,086,084 字节，SHA-256 `b16b98b528bbc2cc8fdb50cda2dcabf80a3a8f27e8047384cf0e110a363219e6`；aapt 确认 `bbs.binmt.cc` / `1.0.0+24` / 应用名 MT论坛，仅 arm64-v8a。原签名证书、原图标资源 SHA-256 `6cc19ee2603f723038dc8771b389f86da56ce0791ae1af765c754c2adc4044a1`、16KB zipalign 均通过；193 个生产源码/资源/配置文件与编译快照逐项哈希一致。记录见 `build/release-verification.json`、`build/final-apk-signature.txt`，构建与分析日志为 `build/home-feed-batch-build.log`、`build/home-feed-batch-analyze.log`。code23 APK 已保存在 rollback；未安装真机。
