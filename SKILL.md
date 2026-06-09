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

在你的 Android 项目目录下运行：

```bash
bash /path/to/android-builder/driver.sh init
```

## 命令列表

```bash
bash /path/to/android-builder/driver.sh <command> [options]
```

### 基础命令

| 命令 | 功能 |
|------|------|
| `init` | 初始化项目配置（自动检测 + 用户输入） |
| `build` | 构建 debug APK |
| `test` | 运行单元测试 |
| `install` | 自动构建、检测设备、安装 APK |
| `launch` | 在设备上启动 app |
| `logcat` | 查看 app 日志 |
| `clean` | 清理构建 |
| `smoke` | 完整烟雾测试（含崩溃检测 + 自动截图） |
| `connect` | 检查设备连接，尝试无线连接 |
| `devices` | 列出所有已连接的 ADB 设备 |

### 诊断命令

| 命令 | 功能 |
|------|------|
| `doctor` | 环境诊断 + 崩溃分析 |
| `screenshot` | 设备截图 |
| `ui-dump` | 导出 UI 层级结构 (XML) |
| `inspect` | 截图 + UI 一键导出（供 AI 分析） |

### 全局选项

| 选项 | 说明 |
|------|------|
| `--json` | JSON 格式输出（支持: devices, doctor, smoke） |

## 智能无线配置

`init` 命令自动检测已连接的 USB 设备：

1. 获取设备 WiFi IP 和 MAC 地址
2. 检测设备和电脑是否在同一局域网
3. 尝试获取无线调试端口
4. 自动填充配置

## doctor 命令

环境诊断 + 崩溃分析：

```bash
bash driver.sh doctor
```

检测项：
- Java / javac / ADB / Gradle
- ANDROID_HOME / ANDROID_SDK_ROOT
- 设备连接状态
- WiFi IP / MAC
- 无线调试端口
- 最近崩溃分析

输出示例：
```
[OK] Java detected: 21
[OK] ADB detected: adb
[OK] Device connected
[OK] Device WiFi IP: 192.168.1.100
[ERROR] No recent crashes found
```

JSON 输出：
```bash
bash driver.sh doctor --json
```

## screenshot 命令

自动截图并保存到本地：

```bash
bash driver.sh screenshot              # 自动生成文件名
bash driver.sh screenshot my_capture   # 自定义文件名
```

保存位置：`./screenshots/`

## ui-dump 命令

导出当前页面的 UI 层级结构：

```bash
bash driver.sh ui-dump
```

保存位置：`./ui-dumps/`

## inspect 命令

一键导出当前页面状态（截图 + UI 结构），方便 AI 分析：

```bash
bash driver.sh inspect
```

## smoke 命令（增强版）

完整烟雾测试流程：

1. Build → 编译 APK
2. Test → 运行单元测试
3. Check APK → 验证产物
4. Install → 安装到设备
5. Launch → 启动 app
6. Wait → 等待稳定
7. Activity Check → 检测当前页面
8. Crash Check → 检测运行时崩溃
9. Screenshot → 自动截图

输出示例：
```
[OK] Build
[OK] Tests
[OK] APK
[OK] Device
[OK] Install
[OK] Launch
[OK] Activity
[OK] No Crash
[OK] SMOKE TEST PASSED
```

JSON 输出：
```bash
bash driver.sh smoke --json
```

## 设备连接

驱动**自动检测**设备连接：

1. **USB 有线** — 优先检测
2. **WiFi 无线** — 有线未找到时自动尝试

## 配置文件

配置保存在 `app-config.env`（与 driver.sh 同目录）：

```bash
APP_PACKAGE=com.example.myapp
APP_ACTIVITY=.MainActivity
APK_PATH=app/build/outputs/apk/debug/app-debug.apk
WIRELESS_IP=192.168.1.100
WIRELESS_PORT=5555
LOGCAT_TAGS=MainActivity
```

## ADB 检测路径

按优先级依次检测：

1. 系统 PATH
2. `%LOCALAPPDATA%/Android/Sdk/platform-tools/`
3. `$HOME/AppData/Local/Android/Sdk/platform-tools/`

## 常见问题

| 症状 | 解决方案 |
|------|----------|
| `Configuration not found` | 运行 `bash driver.sh init` |
| `JAVA_HOME not set` | 设置 `JAVA_HOME` 环境变量 |
| `SDK location not found` | 创建 `local.properties` 写入 `sdk.dir=<路径>` |
| ADB not found | 下载 [platform-tools](https://googledownloads.cn/android/repository/platform-tools-latest-windows.zip) |
| 无线连接失败 | 先配对：`adb pair <ip>:<port>` |
