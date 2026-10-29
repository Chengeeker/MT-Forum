# MT论坛

面向 Android 的 Flutter 论坛客户端，连接 [MT 论坛](https://bbs.binmt.cc/)，使用 Material 3（M3）界面。

## 项目概览

- 应用名称：MT论坛
- Android 包名：`bbs.binmt.cc`
- 发布架构：`arm64-v8a`
- 论坛主要页面由 Flutter 原生界面呈现；外部链接通过应用内浏览器打开，QQ 使用官方授权流程。

## 功能

### 浏览论坛

- 首页、发现、板块、导读、热门排行和搜索
- 帖子列表分页加载，展示可读取的作者、头像、摘要和互动统计
- 帖子详情、楼层回复、引用回复及快捷回复
- 收藏、浏览历史、账号资料、消息与提醒、签到

### 阅读与媒体

- M3 帖子排版、代码块复制、链接和图片展示
- 图片共享元素转场、多图缩放浏览及视频播放
- 站外 HTTP(S) 链接使用应用内浏览器

### 个性化

- 浅色、深色主题和字体设置
- 可选的液态玻璃效果
- 悬浮底栏与磨砂顶栏

## 登录与交互说明

- 支持论坛提供的用户名/密码、邮箱/密码登录方式，以及 QQ 官方授权流程。
- 发帖、回复和同源表单使用原生 M3 控件；提交失败时保留输入，不自动重试。
- 网站验证码、复杂插件页面及附件上传可能需要单独适配；未适配的功能不会被描述为已完整支持。

## 开发与构建

准备兼容项目约束的 Flutter SDK、Android SDK 和 Windows PowerShell 环境后，可运行：

```powershell
flutter pub get
flutter analyze lib test
flutter test
```

维护者可在本机签名配置完成后构建并执行检查：

```powershell
pwsh -File .\tool\build_release.ps1 -RunChecks
```

发布脚本构建 ARM64 release。签名文件、密钥和口令仅保存在本机，不应提交到版本库。

## 项目文档

- [开发记录与交付说明](docs/DEVELOPMENT.md)
- [原生页面适配审计](docs/NATIVE_UI_AUDIT.md)
- [登录协议核对](docs/LOGIN_PROTOCOL.md)
- [Review 组件许可说明](docs/REVIEW_LICENSE)

## 声明

本项目为第三方客户端项目。论坛内容和网站图标归其各自权利人所有；Review 组件许可见项目内的 `docs/REVIEW_LICENSE`。
