# Android Builder

[English](README.md)

AI 可操作的 Android 运行时层。通用 Android app 构建、测试、安装、诊断驱动。

## 功能

- 🔍 **自动检测**：包名、主 Activity、Gradle、ADB
- 📱 **设备管理**：USB/WiFi 自动连接
- 🌐 **智能无线**：自动获取设备 WiFi IP，检测同局域网，获取调试端口
- 🚀 **一键烟雾测试**：build → test → install → launch + 崩溃检测
- 🩺 **Doctor**：环境诊断 + 崩溃分析
- 📸 **截图**：自动截取设备屏幕
- 🗂️ **UI Dump**：导出 UI 层级结构供 AI 分析
- 📊 **JSON 输出**：机器可读格式，方便自动化
- ⚙️ **交互式配置**：首次使用引导设置

## 快速开始

```bash
# 克隆
git clone https://github.com/AnonyJcy/android-builder.git

# 进入你的 Android 项目目录
cd /path/to/your/android/project

# 初始化配置
bash /path/to/android-builder/driver.sh init

# 运行烟雾测试
bash /path/to/android-builder/driver.sh smoke
```

## 命令列表

### 基础命令

| 命令 | 功能 |
|------|------|
| `init` | 初始化项目配置 |
| `build` | 构建 debug APK |
| `test` | 运行单元测试 |
| `install` | 自动构建 + 安装 APK |
| `launch` | 在设备上启动 app |
| `logcat` | 查看 app 日志 |
| `clean` | 清理构建 |
| `smoke` | 完整烟雾测试（含崩溃检测） |
| `connect` | 检查/连接无线设备 |
| `devices` | 列出已连接设备 |

### 诊断命令

| 命令 | 功能 |
|------|------|
| `doctor` | 环境诊断 + 崩溃分析 |
| `screenshot` | 设备截图 |
| `ui-dump` | 导出 UI 层级结构 (XML) |
| `inspect` | 截图 + UI 一键导出（供 AI 分析） |

### 选项

| 选项 | 说明 |
|------|------|
| `--json` | JSON 格式输出（支持: devices, doctor, smoke） |

## 使用示例

```bash
# 环境检查
bash driver.sh doctor

# JSON 输出（用于自动化）
bash driver.sh doctor --json
bash driver.sh devices --json

# 截图
bash driver.sh screenshot
bash driver.sh screenshot my_capture

# 导出 UI 结构
bash driver.sh ui-dump

# 完整检查（截图 + UI 结构）
bash driver.sh inspect

# 增强版烟雾测试
bash driver.sh smoke
bash driver.sh smoke --json
```

## Doctor 输出示例

```
[OK] Java detected: 21
[OK] ADB detected: adb
[OK] Device connected
[OK] Device WiFi IP: 192.168.1.100
[OK] No recent crashes found
```

JSON 格式：
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

## Smoke 测试流程

1. Build → 编译 APK
2. Test → 运行单元测试
3. Check APK → 验证产物
4. Install → 安装到设备
5. Launch → 启动 app
6. Wait → 等待稳定
7. Activity Check → 检测当前页面
8. Crash Check → 检测运行时崩溃
9. Screenshot → 自动截图

## 前置条件

- JDK 17+
- Android SDK
- ADB（[下载](https://googledownloads.cn/android/repository/platform-tools-latest-windows.zip)）

## License

[MIT](LICENSE)
