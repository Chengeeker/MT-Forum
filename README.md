# MT论坛

面向 Android 的 Jetpack Compose 论坛客户端，连接 [MT 论坛](https://bbs.binmt.cc/)。当前版本为 1.6.16+68，包名为 `bbs.binmt.cc`，支持 Android 7.0 及以上。发布架构为 arm64-v8a。

应用支持论坛浏览与搜索、发帖回复、收藏和历史、消息与签到、图片画廊和视频播放，以及 WebDAV 设置备份。Compose 是当前主工程，早期 Flutter 版保留在 Git 提交历史中。

## 构建和测试

使用 JDK 17 和 Android SDK 36。从项目根目录运行主机回归：

```powershell
.\gradlew.bat testReleaseUnitTest
```

使用 Android Studio 或运行 `assembleDebug` 可以构建开发版。原签名发布包需要维护者的本地签名配置。

## 许可

复用代码的许可和第三方声明随 [应用资源](app/src/main/assets) 提供。
