# MT论坛

面向 Android 的 Jetpack Compose 论坛客户端，连接 [MT 论坛](https://bbs.binmt.cc/)。当前版本为 1.6.20+72，包名为 `bbs.binmt.cc`，支持 Android 7.0 及以上，仅发布 arm64-v8a APK。

## 构建

在项目根目录运行：

```powershell
pwsh -File .\tool\build_release.ps1
```

脚本使用本机原有签名，运行主机回归后将签名 APK 输出到项目根目录。构建快照和运行时临时文件位于项目的 `tmp/`。已有 Gradle 依赖缓存时可加 `-Offline`。

## 开发记录

- [开发文档](docs/DEVELOPMENT.md)
- [Compose 迁移记录](docs/MIGRATION.md)
- [视觉对照清单](docs/VISUAL_PARITY.md)

Flutter 源码与最后一版 APK 已移入本地回退目录，Compose 为当前主工程。
