# Android Builder

通用 Android app 构建、测试、安装驱动脚本。支持自动检测项目配置，一键完成 build → test → install → launch 流程。

## 功能

- 🔍 **自动检测**：包名、主 Activity、Gradle、ADB
- 📱 **设备管理**：USB/WiFi 自动连接
- 🚀 **一键烟雾测试**：build → test → install → launch
- ⚙️ **交互式配置**：首次使用引导设置

## 快速开始

```bash
# 1. 克隆或下载到任意位置
git clone <repo-url> android-builder

# 2. 进入你的 Android 项目目录
cd /path/to/your/android/project

# 3. 初始化配置（自动检测 + 交互式填写）
bash /path/to/android-builder/driver.sh init

# 4. 运行烟雾测试
bash /path/to/android-builder/driver.sh smoke
```

## 命令列表

| 命令 | 功能 |
|------|------|
| `init` | 初始化项目配置（自动检测 + 用户输入） |
| `build` | 构建 debug APK |
| `test` | 运行单元测试 |
| `install` | 自动构建、检测设备、安装 APK |
| `launch` | 在设备上启动 app |
| `logcat` | 查看 app 日志 |
| `clean` | 清理构建 |
| `smoke` | 完整烟雾测试 |
| `connect` | 检查/连接无线设备 |
| `devices` | 列出已连接设备 |

## 自动检测

| 配置项 | 检测来源 |
|--------|----------|
| 包名 | `app/build.gradle` 的 `applicationId` / `namespace` |
| 主 Activity | `AndroidManifest.xml` 的 MAIN+LAUNCHER intent-filter |
| Gradle | 项目根目录的 `gradlew` / `gradlew.bat` |
| ADB | 系统 PATH 或 Android SDK 目录 |

## 配置文件

运行 `init` 后会在脚本同目录生成 `app-config.env`：

```bash
APP_PACKAGE=com.example.myapp
APP_ACTIVITY=.MainActivity
APK_PATH=app/build/outputs/apk/debug/app-debug.apk
WIRELESS_IP=192.168.1.100
WIRELESS_PORT=5555
LOGCAT_TAGS=MainActivity
```

## 前置条件

- JDK 17+
- Android SDK
- ADB（[下载](https://googledownloads.cn/android/repository/platform-tools-latest-windows.zip)）

## License

MIT
