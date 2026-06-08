# Android Builder

[中文文档](README_CN.md)

Universal Android app build, test, and install driver script. Auto-detects project configuration, supports one-click smoke testing.

## Features

- 🔍 **Auto Detection**: Package name, main Activity, Gradle, ADB
- 📱 **Device Management**: USB/WiFi auto connection
- 🌐 **Smart Wireless**: Auto-detect device WiFi IP, check same LAN, get debug port
- 🚀 **One-Click Smoke Test**: build → test → install → launch
- ⚙️ **Interactive Setup**: Guided first-time configuration

## Quick Start

```bash
# 1. Clone or download
git clone https://github.com/AnonyJcy/android-builder.git

# 2. Enter your Android project directory
cd /path/to/your/android/project

# 3. Initialize config (auto-detect + interactive)
bash /path/to/android-builder/driver.sh init

# 4. Run smoke test
bash /path/to/android-builder/driver.sh smoke
```

## Commands

| Command | Description |
|---------|-------------|
| `init` | Initialize project config (auto-detect + user input) |
| `build` | Build debug APK |
| `test` | Run unit tests |
| `install` | Auto build, detect device, install APK |
| `launch` | Launch app on device |
| `logcat` | View app logs |
| `clean` | Clean build |
| `smoke` | Full smoke test |
| `connect` | Check/connect wireless device |
| `devices` | List connected devices |

## Auto Detection

| Config | Source |
|--------|--------|
| Package | `app/build.gradle` `applicationId` / `namespace` |
| Activity | `AndroidManifest.xml` MAIN+LAUNCHER intent-filter |
| Gradle | `gradlew` / `gradlew.bat` in project root |
| ADB | System PATH or Android SDK directory |

## Config File

Running `init` generates `app-config.env` in the script directory:

```bash
APP_PACKAGE=com.example.myapp
APP_ACTIVITY=.MainActivity
APK_PATH=app/build/outputs/apk/debug/app-debug.apk
WIRELESS_IP=192.168.1.100
WIRELESS_PORT=5555
LOGCAT_TAGS=MainActivity
```

## Prerequisites

- JDK 17+
- Android SDK
- ADB ([Download](https://googledownloads.cn/android/repository/platform-tools-latest-windows.zip))

## License

[MIT](LICENSE)
