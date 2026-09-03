# Phase 9 发布清单

本项目使用同一套 Flutter 代码发布到 macOS、Windows、Android 和 iOS。发布构建前先确保工作区干净，并完成测试：

```bash
flutter test
flutter build web --debug
```

## macOS

本机开发构建：

```bash
flutter build macos --release
```

产物位于 `build/macos/Build/Products/Release/`。向其他 Mac 分发前，需要使用 Apple Developer 证书签名并进行 notarization；不要把证书、钥匙串导出文件或 API 密钥提交到仓库。

## Windows

在 Windows 主机运行：

```powershell
flutter build windows --release
```

产物位于 `build\\windows\\x64\\runner\\Release\\`。分发前应使用代码签名证书签名安装包或可执行文件。Windows 不能在 macOS 上交叉构建。

## Android

先安装 Android Studio 与 Android SDK，并配置 Flutter：

```bash
flutter config --android-sdk <android-sdk-path>
flutter doctor
flutter build apk --release
```

测试可安装 `build/app/outputs/flutter-apk/app-release.apk`。正式发布应创建本地 `android/key.properties` 和上传密钥，改用 release signing config；这些文件必须保持在 Git 忽略列表中。

## iOS

在 macOS 上配置 Apple Developer Team、Bundle ID 与 provisioning profile 后运行：

```bash
flutter build ipa --release
```

随后通过 Xcode Organizer、TestFlight 或企业分发流程上传。签名身份和 provisioning profile 不应提交到 Git。

## 本机验证状态

- macOS Debug：已于 2026-09-03 构建通过。
- Web Debug：已于 2026-09-03 构建通过。
- Android：当前机器未安装 Android SDK，待安装后执行 APK 验证。
- Windows：需在 Windows 主机执行构建验证。
- iOS：Xcode 工具链可用，正式 IPA 仍需要选择签名团队。
