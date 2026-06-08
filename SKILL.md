---
name: android-builder
description: Build, test, install, and run Android apps with auto device detection. Use when user says "run app", "build app", "test app", "install app", or "smoke test".
---

# Android Builder

通用 Android app 构建、测试、安装驱动。支持自动检测项目配置，一键完成 build → test → install → launch 流程。

**所有路径相对于项目根目录。**

## 前置条件

- JDK 17+ (推荐 Eclipse Adoptium)
- Android SDK (根据项目 targetSdk 安装对应 Platform)
- ADB (自动检测，或手动安装 platform-tools)

## 快速开始

### 1. 初始化配置（首次使用）

在你的 Android 项目目录下运行：

```bash
bash /path/to/android-builder/driver.sh init
```

自动检测项目信息，检测不到的会询问用户：

| 配置项 | 自动检测来源 | 示例 |
|--------|-------------|------|
| 包名 | `app/build.gradle` 的 `applicationId` / `namespace` | `com.example.myapp` |
| 主 Activity | `AndroidManifest.xml` 的 MAIN+LAUNCHER intent-filter | `.MainActivity` |
| Gradle | 项目根目录的 `gradlew` / `gradlew.bat` | `./gradlew` |
| ADB | 系统 PATH 或 Android SDK 目录 | 自动检测 |
| 无线设备 | 用户手动输入 | `192.168.1.100:5555` |

### 2. 运行 Smoke Test

```bash
bash /path/to/android-builder/driver.sh smoke
```

完整流程：build → test → APK 检查 → 设备连接 → install & launch（如有设备）。

## 命令列表

```bash
bash /path/to/android-builder/driver.sh <command>
```

| 命令 | 功能 |
|------|------|
| `init` | 初始化项目配置（自动检测 + 用户输入） |
| `build` | `gradlew assembleDebug` — 构建 debug APK |
| `test` | `gradlew test` — 运行单元测试 |
| `install` | 自动构建、检测设备、安装 APK |
| `launch` | 在设备上启动 app |
| `logcat` | 查看 app 日志 |
| `clean` | `gradlew clean` |
| `smoke` | 完整烟雾测试：build + test + install + launch |
| `connect` | 检查设备连接，尝试无线连接 |
| `devices` | 列出所有已连接的 ADB 设备 |

## 设备连接

驱动**自动检测**设备连接：

1. **USB 有线** — 优先检测
2. **WiFi 无线** — 有线未找到时自动尝试

### 无线配置

在 `init` 时配置，或手动编辑 `app-config.env`：

```bash
WIRELESS_IP=192.168.1.100
WIRELESS_PORT=5555
```

### 首次无线配对

如果无线连接失败，需要先配对：

1. 在设备上启用**无线调试**（开发者选项）
2. 获取配对码：设备 > 无线调试 > 使用配对码配对设备
3. 运行：`adb pair <ip>:<pairing_port>`
4. 输入配对码

## 配置文件

配置保存在 `app-config.env`（与 driver.sh 同目录）：

```bash
# Android App Configuration
APP_PACKAGE=com.example.myapp
APP_ACTIVITY=.MainActivity
APK_PATH=app/build/outputs/apk/debug/app-debug.apk
WIRELESS_IP=192.168.1.100
WIRELESS_PORT=5555
LOGCAT_TAGS=MainActivity
```

可以手动编辑，或重新运行 `init` 更新。

## 直接使用 Gradle（跳过驱动）

```bash
./gradlew assembleDebug    # 构建
./gradlew test             # 测试
./gradlew clean            # 清理
```

## ADB 检测路径

按优先级依次检测：

1. 系统 PATH
2. `%LOCALAPPDATA%/Android/Sdk/platform-tools/`
3. `$HOME/AppData/Local/Android/Sdk/platform-tools/`

未找到时会提示下载链接。

## 常见问题

| 症状 | 解决方案 |
|------|----------|
| `Configuration not found` | 运行 `bash driver.sh init` 初始化配置 |
| `JAVA_HOME not set` | 设置 `JAVA_HOME` 环境变量指向 JDK 安装目录 |
| `SDK location not found` | 创建 `local.properties` 写入 `sdk.dir=<Android SDK 路径>` |
| `Could not find build tools` | `sdkmanager "build-tools;<version>"` |
| ADB not found | 下载 [platform-tools](https://googledownloads.cn/android/repository/platform-tools-latest-windows.zip)，解压后将目录添加到 PATH |
| 无线连接失败 | 先配对：`adb pair <ip>:<port>` |
