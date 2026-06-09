# Android Builder

[中文文档](README_CN.md)

AI-operable Android Runtime Layer. Universal build, test, install, and diagnostic driver for Android apps.

## Features

- 🔍 **Auto Detection**: Package name, main Activity, Gradle, ADB
- 📱 **Device Management**: USB/WiFi auto connection
- 🌐 **Smart Wireless**: Auto-detect device WiFi IP, check same LAN, get debug port
- 🚀 **One-Click Smoke Test**: build → test → install → launch + crash detection
- 🩺 **Doctor**: Environment diagnosis + crash analysis
- 📸 **Screenshot**: Auto capture device screen
- 🗂️ **UI Dump**: Export UI hierarchy for AI analysis
- 📊 **JSON Output**: Machine-readable output for automation
- ⚙️ **Interactive Setup**: Guided first-time configuration

## Quick Start

```bash
# Clone
git clone https://github.com/AnonyJcy/android-builder.git

# Enter your Android project
cd /path/to/your/android/project

# Initialize config
bash /path/to/android-builder/driver.sh init

# Run smoke test
bash /path/to/android-builder/driver.sh smoke
```

## Commands

### Basic

| Command | Description |
|---------|-------------|
| `init` | Initialize project config |
| `build` | Build debug APK |
| `test` | Run unit tests |
| `install` | Auto build + install APK |
| `launch` | Launch app on device |
| `logcat` | View app logs |
| `clean` | Clean build |
| `smoke` | Full smoke test with crash detection |
| `connect` | Check/connect wireless device |
| `devices` | List connected devices |

### Diagnostic

| Command | Description |
|---------|-------------|
| `doctor` | Environment diagnosis + crash analysis |
| `screenshot` | Take device screenshot |
| `ui-dump` | Export UI hierarchy (XML) |
| `inspect` | Screenshot + UI dump (for AI analysis) |

### Options

| Option | Description |
|--------|-------------|
| `--json` | JSON output (for: devices, doctor, smoke) |

## Examples

```bash
# Environment check
bash driver.sh doctor

# JSON output for automation
bash driver.sh doctor --json
bash driver.sh devices --json

# Take screenshot
bash driver.sh screenshot
bash driver.sh screenshot my_capture

# Export UI structure
bash driver.sh ui-dump

# Full inspection (screenshot + UI dump)
bash driver.sh inspect

# Enhanced smoke test
bash driver.sh smoke
bash driver.sh smoke --json
```

## Doctor Output

```
[OK] Java detected: 21
[OK] ADB detected: adb
[OK] Device connected
[OK] Device WiFi IP: 192.168.1.100
[OK] No recent crashes found
```

JSON:
```json
{
  "java": true,
  "adb": true,
  "gradle": true,
  "device_connected": true,
  "wifi_ip": "192.168.1.100",
  "has_crash": false
}
```

## Smoke Test Flow

1. Build → Compile APK
2. Test → Run unit tests
3. Check APK → Verify artifact
4. Install → Install to device
5. Launch → Start app
6. Wait → Stabilize
7. Activity Check → Detect foreground
8. Crash Check → Detect runtime crashes
9. Screenshot → Auto capture

## Prerequisites

- JDK 17+
- Android SDK
- ADB ([Download](https://googledownloads.cn/android/repository/platform-tools-latest-windows.zip))

## License

[MIT](LICENSE)
