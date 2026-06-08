#!/usr/bin/env bash
# Android App Builder Driver
# Usage: bash driver.sh <command>
# Commands: init | build | test | install | launch | logcat | clean | smoke | connect | devices

set -euo pipefail
# Resolve script directory (for config file)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Project root is the current working directory (where the Android project is)
PROJECT_ROOT="$(pwd)"
cd "$PROJECT_ROOT"

CONFIG_FILE="$SCRIPT_DIR/app-config.env"
CMD="${1:-help}"

# ============================================================
# Auto-detection functions
# ============================================================

# Detect applicationId / namespace from build.gradle*
detect_package() {
  local gradle_files=(app/build.gradle app/build.gradle.kts)
  for f in "${gradle_files[@]}"; do
    if [ -f "$f" ]; then
      local pkg
      pkg=$(grep -oP 'applicationId\s*["\x27]?\K[^"\x27]+' "$f" 2>/dev/null | head -1)
      if [ -z "$pkg" ]; then
        pkg=$(grep -oP 'namespace\s*["\x27]?\K[^"\x27]+' "$f" 2>/dev/null | head -1)
      fi
      if [ -n "$pkg" ]; then
        echo "$pkg"
        return 0
      fi
    fi
  done
  return 1
}

# Detect main activity from AndroidManifest.xml
detect_activity() {
  local manifest="app/src/main/AndroidManifest.xml"
  if [ ! -f "$manifest" ]; then
    return 1
  fi
  local result
  result=$(sed -n '/<activity/,/<\/activity>/p' "$manifest" | grep -B50 'LAUNCHER' | grep 'android:name' | head -1 | sed 's/.*android:name="\([^"]*\)".*/\1/')
  if [ -n "$result" ]; then
    echo "$result"
    return 0
  fi
  return 1
}

# Detect Gradle wrapper
detect_gradle() {
  if [ -f "./gradlew" ]; then
    echo "./gradlew"
  elif [ -f "./gradlew.bat" ]; then
    echo "./gradlew.bat"
  else
    return 1
  fi
}

# Detect ADB
detect_adb() {
  if command -v adb &>/dev/null; then
    echo "adb"
  elif [ -f "$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe" ]; then
    echo "$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
  elif [ -f "$HOME/AppData/Local/Android/Sdk/platform-tools/adb.exe" ]; then
    echo "$HOME/AppData/Local/Android/Sdk/platform-tools/adb.exe"
  else
    echo "ERROR: ADB not found." >&2
    echo "Download platform-tools from: https://googledownloads.cn/android/repository/platform-tools-latest-windows.zip" >&2
    echo "Extract and add the folder to PATH." >&2
    return 1
  fi
}

# ============================================================
# Device network detection
# ============================================================

# Get device WiFi IP address
get_device_wifi_ip() {
  $ADB shell ip addr show wlan0 2>/dev/null | grep -oP 'inet \K[0-9.]+' | head -1
}

# Get device WiFi MAC address
get_device_wifi_mac() {
  $ADB shell ip addr show wlan0 2>/dev/null | grep -oP 'link/ether \K[0-9a-f:]+' | head -1
}

# Get device wireless debugging port
get_device_adb_port() {
  # Try to get port from system properties
  local port
  port=$($ADB shell getprop service.adb.tcp.port 2>/dev/null | tr -d '\r\n')
  if [ -n "$port" ] && [ "$port" != "0" ]; then
    echo "$port"
    return 0
  fi
  port=$($ADB shell getprop persist.adb.tcp.port 2>/dev/null | tr -d '\r\n')
  if [ -n "$port" ] && [ "$port" != "0" ]; then
    echo "$port"
    return 0
  fi
  return 1
}

# Get computer's local IP in the same network segment
get_computer_ip() {
  # Try to get the IP that matches the device's subnet
  local device_ip="$1"
  if [ -z "$device_ip" ]; then
    # Just return any non-loopback IP
    ip addr show 2>/dev/null | grep -oP 'inet \K[0-9.]+' | grep -v '^127\.' | head -1 || \
    hostname -I 2>/dev/null | awk '{print $1}' || \
    return 1
  else
    # Get subnet from device IP (first 3 octets)
    local subnet
    subnet=$(echo "$device_ip" | cut -d'.' -f1-3)
    # Find matching IP on computer
    ip addr show 2>/dev/null | grep -oP 'inet \K[0-9.]+' | grep "^${subnet}\." | head -1 || \
    return 1
  fi
}

# Check if device and computer are on the same LAN
check_same_lan() {
  local device_ip="$1"
  local computer_ip="$2"

  if [ -z "$device_ip" ] || [ -z "$computer_ip" ]; then
    return 1
  fi

  # Compare first 3 octets (subnet)
  local device_subnet
  device_subnet=$(echo "$device_ip" | cut -d'.' -f1-3)
  local computer_subnet
  computer_subnet=$(echo "$computer_ip" | cut -d'.' -f1-3)

  if [ "$device_subnet" = "$computer_subnet" ]; then
    return 0
  fi
  return 1
}

# ============================================================
# Config management
# ============================================================

load_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Configuration not found."
    echo "Run: bash driver.sh init"
    exit 1
  fi
  source "$CONFIG_FILE"

  if [ -z "${APP_PACKAGE:-}" ]; then
    echo "ERROR: APP_PACKAGE not set in config. Run: bash driver.sh init"
    exit 1
  fi
  if [ -z "${APP_ACTIVITY:-}" ]; then
    echo "ERROR: APP_ACTIVITY not set in config. Run: bash driver.sh init"
    exit 1
  fi

  APK_PATH="${APK_PATH:-app/build/outputs/apk/debug/app-debug.apk}"
  WIRELESS_PORT="${WIRELESS_PORT:-5555}"
  LOGCAT_TAGS="${LOGCAT_TAGS:-$APP_PACKAGE}"
}

save_config() {
  cat > "$CONFIG_FILE" << EOF
# Android App Configuration
# Generated by: driver.sh init on $(date +%Y-%m-%d)

# App Info
APP_PACKAGE=$APP_PACKAGE
APP_ACTIVITY=$APP_ACTIVITY

# Build
APK_PATH=$APK_PATH

# Wireless Device (optional)
WIRELESS_IP=${WIRELESS_IP:-}
WIRELESS_PORT=${WIRELESS_PORT:-5555}

# Logcat
LOGCAT_TAGS=$LOGCAT_TAGS
EOF
  echo "✓ Configuration saved to: $CONFIG_FILE"
}

# ============================================================
# ADB device functions
# ============================================================

check_wired_device() {
  local devices
  devices=$($ADB devices 2>/dev/null | grep -v "List" | grep -v "^$" | grep -v "wireless" || true)
  if echo "$devices" | grep -q "device$"; then
    return 0
  fi
  return 1
}

check_wireless_device() {
  if [ -z "${WIRELESS_IP:-}" ]; then
    return 1
  fi
  if $ADB devices 2>/dev/null | grep -q "$WIRELESS_IP:$WIRELESS_PORT"; then
    return 0
  fi
  return 1
}

connect_wireless() {
  if [ -z "${WIRELESS_IP:-}" ]; then
    echo "No wireless device configured. Run: bash driver.sh init"
    return 1
  fi

  echo "=== Connecting to wireless device ==="
  echo "Target: $WIRELESS_IP:$WIRELESS_PORT"

  if check_wireless_device; then
    echo "Already connected to $WIRELESS_IP:$WIRELESS_PORT"
    return 0
  fi

  echo "Attempting wireless connection..."
  if $ADB connect "$WIRELESS_IP:$WIRELESS_PORT" 2>&1 | grep -q "connected"; then
    echo "Successfully connected to $WIRELESS_IP:$WIRELESS_PORT"
    return 0
  else
    echo "Failed to connect to $WIRELESS_IP:$WIRELESS_PORT"
    echo ""
    echo "Troubleshooting:"
    echo "1. Ensure device and computer are on the same network"
    echo "2. Enable wireless debugging on device (Developer options > Wireless debugging)"
    echo "3. Pair device first: adb pair $WIRELESS_IP:<pairing_port>"
    return 1
  fi
}

get_active_device() {
  if check_wired_device; then
    echo "wired"
    return 0
  elif check_wireless_device; then
    echo "wireless"
    return 0
  fi
  return 1
}

# ============================================================
# Init command
# ============================================================

cmd_init() {
  echo "=== Android Builder: Initialize Configuration ==="
  echo ""

  # --- Auto-detect project config ---
  echo "[1/4] Auto-detecting project configuration..."
  echo ""

  local detected_pkg
  detected_pkg=$(detect_package 2>/dev/null || true)
  if [ -n "$detected_pkg" ]; then
    echo "  ✓ Package: $detected_pkg"
  else
    echo "  ✗ Package: not detected"
  fi

  local detected_act
  detected_act=$(detect_activity 2>/dev/null || true)
  if [ -n "$detected_act" ]; then
    echo "  ✓ Activity: $detected_act"
  else
    echo "  ✗ Activity: not detected"
  fi

  local detected_gradle
  detected_gradle=$(detect_gradle 2>/dev/null || true)
  if [ -n "$detected_gradle" ]; then
    echo "  ✓ Gradle: $detected_gradle"
  else
    echo "  ✗ Gradle: not detected"
  fi

  local detected_adb
  detected_adb=$(detect_adb 2>/dev/null || true)
  if [ -n "$detected_adb" ]; then
    echo "  ✓ ADB: $detected_adb"
  else
    echo "  ✗ ADB: not detected"
  fi

  echo ""

  # --- Detect device network info ---
  echo "[2/4] Detecting device network information..."
  echo ""

  local device_wifi_ip=""
  local device_wifi_mac=""
  local computer_ip=""
  local same_lan=false
  local adb_port=""

  if [ -n "$detected_adb" ]; then
    ADB="$detected_adb"

    # Check for wired device
    if check_wired_device; then
      echo "  ✓ USB device connected"

      # Get device WiFi info
      device_wifi_ip=$(get_device_wifi_ip 2>/dev/null || true)
      device_wifi_mac=$(get_device_wifi_mac 2>/dev/null || true)

      if [ -n "$device_wifi_ip" ]; then
        echo "  ✓ Device WiFi IP: $device_wifi_ip"
        if [ -n "$device_wifi_mac" ]; then
          echo "  ✓ Device WiFi MAC: $device_wifi_mac"
        fi

        # Check if on same LAN
        computer_ip=$(get_computer_ip "$device_wifi_ip" 2>/dev/null || true)
        if [ -n "$computer_ip" ]; then
          echo "  ✓ Computer IP: $computer_ip"
          if check_same_lan "$device_wifi_ip" "$computer_ip"; then
            echo "  ✓ Same LAN detected"
            same_lan=true

            # Try to get wireless debug port
            adb_port=$(get_device_adb_port 2>/dev/null || true)
            if [ -n "$adb_port" ]; then
              echo "  ✓ Wireless debug port: $adb_port"
            else
              echo "  ✗ Wireless debug port: not detected (enable in Developer options)"
            fi
          else
            echo "  ✗ Different LAN - wireless connection not available"
          fi
        else
          echo "  ✗ Computer IP: not detected"
        fi
      else
        echo "  ✗ Device WiFi: not connected"
      fi
    else
      echo "  ✗ No USB device connected"
    fi
  else
    echo "  ✗ ADB not available"
  fi

  echo ""

  # --- User input for project config ---
  echo "[3/4] Confirm or fill in project configuration..."
  echo ""

  # Package
  if [ -n "$detected_pkg" ]; then
    read -p "  Package name [$detected_pkg]: " input_pkg
    APP_PACKAGE="${input_pkg:-$detected_pkg}"
  else
    read -p "  Package name (e.g. com.example.myapp): " APP_PACKAGE
    if [ -z "$APP_PACKAGE" ]; then
      echo "ERROR: Package name is required"
      exit 1
    fi
  fi

  # Activity
  if [ -n "$detected_act" ]; then
    read -p "  Main Activity [$detected_act]: " input_act
    APP_ACTIVITY="${input_act:-$detected_act}"
  else
    read -p "  Main Activity (e.g. .MainActivity): " APP_ACTIVITY
    if [ -z "$APP_ACTIVITY" ]; then
      echo "ERROR: Activity is required"
      exit 1
    fi
  fi

  # APK path
  local default_apk="app/build/outputs/apk/debug/app-debug.apk"
  read -p "  APK output path [$default_apk]: " input_apk
  APK_PATH="${input_apk:-$default_apk}"

  # Wireless device config
  echo ""
  echo "  Wireless device configuration:"

  if $same_lan && [ -n "$device_wifi_ip" ]; then
    echo "  (Device detected on same LAN: $device_wifi_ip)"
    read -p "  Use this IP for wireless connection? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
      WIRELESS_IP="$device_wifi_ip"
    else
      read -p "  IP address: " WIRELESS_IP
    fi
  else
    read -p "  IP address (press Enter to skip): " WIRELESS_IP
  fi

  if [ -n "${WIRELESS_IP:-}" ]; then
    if [ -n "$adb_port" ]; then
      read -p "  Port [$adb_port]: " input_port
      WIRELESS_PORT="${input_port:-$adb_port}"
    else
      read -p "  Port (check on device: Developer options > Wireless debugging): " WIRELESS_PORT
      if [ -z "$WIRELESS_PORT" ]; then
        echo "  WARNING: Port is required for wireless connection"
        WIRELESS_PORT="5555"
      fi
    fi
  else
    WIRELESS_PORT="5555"
  fi

  # Logcat tags
  read -p "  Logcat filter tags [$APP_PACKAGE]: " input_tags
  LOGCAT_TAGS="${input_tags:-$APP_PACKAGE}"

  # --- Confirm ---
  echo ""
  echo "[4/4] Configuration summary:"
  echo ""
  echo "  Package:    $APP_PACKAGE"
  echo "  Activity:   $APP_ACTIVITY"
  echo "  APK path:   $APK_PATH"
  if [ -n "${WIRELESS_IP:-}" ]; then
    echo "  Wireless:   $WIRELESS_IP:$WIRELESS_PORT"
  else
    echo "  Wireless:   (not configured)"
  fi
  echo "  Logcat:     $LOGCAT_TAGS"
  echo ""

  read -p "Save this configuration? (y/n): " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    save_config
    echo ""
    echo "Done! Try: bash driver.sh smoke"
  else
    echo "Configuration not saved."
    exit 0
  fi
}

# ============================================================
# Commands
# ============================================================

cmd_build() {
  echo "=== Building debug APK ==="
  $GRADLE assembleDebug --console=plain 2>&1 | tail -5
  echo "APK: $APK_PATH"
}

cmd_test() {
  echo "=== Running unit tests ==="
  $GRADLE test --console=plain 2>&1 | tail -10
}

cmd_install() {
  echo "=== Installing APK on device ==="

  if [ ! -f "$APK_PATH" ]; then
    echo "APK not found, building first..."
    $GRADLE assembleDebug --console=plain 2>&1 | tail -3
  fi

  DEVICE_TYPE=$(get_active_device 2>/dev/null || true)
  if [ -z "$DEVICE_TYPE" ]; then
    echo "No device found. Attempting wireless connection..."
    if ! connect_wireless; then
      echo "ERROR: No device available for installation"
      exit 1
    fi
  fi

  echo "Installing to $DEVICE_TYPE device..."
  $ADB install -r "$APK_PATH" 2>&1
  echo "✓ APK installed successfully"
}

cmd_launch() {
  echo "=== Launching app ==="

  DEVICE_TYPE=$(get_active_device 2>/dev/null || true)
  if [ -z "$DEVICE_TYPE" ]; then
    echo "No device found. Attempting wireless connection..."
    if ! connect_wireless; then
      echo "ERROR: No device available"
      exit 1
    fi
  fi

  $ADB shell am start -n "$APP_PACKAGE/$APP_ACTIVITY" 2>&1
  sleep 2
  echo "✓ App launched"
}

cmd_logcat() {
  echo "=== Recent logcat ==="

  DEVICE_TYPE=$(get_active_device 2>/dev/null || true)
  if [ -z "$DEVICE_TYPE" ]; then
    echo "No device found. Attempting wireless connection..."
    if ! connect_wireless; then
      echo "ERROR: No device available"
      exit 1
    fi
  fi

  local filter
  filter=$(echo "$LOGCAT_TAGS" | tr ',' ' ')

  $ADB logcat -d -t 100 --pid=$($ADB shell pidof "$APP_PACKAGE" 2>/dev/null || echo 0) 2>/dev/null || \
  $ADB logcat -d -t 100 -s $filter 2>/dev/null || \
  echo "No running process found. Start the app first."
}

cmd_clean() {
  echo "=== Cleaning build ==="
  $GRADLE clean --console=plain 2>&1 | tail -3
}

cmd_smoke() {
  echo "=== Smoke test: build + test + install + launch ==="
  echo "[1/4] Building..."
  $GRADLE assembleDebug --console=plain 2>&1 | tail -3

  echo "[2/4] Testing..."
  $GRADLE test --console=plain 2>&1 | tail -5

  echo "[3/4] Checking APK..."
  if [ -f "$APK_PATH" ]; then
    SIZE=$(du -h "$APK_PATH" | cut -f1)
    echo "✓ APK exists: $APK_PATH ($SIZE)"
  else
    echo "✗ APK not found!"
    echo "SMOKE TEST FAILED"
    exit 1
  fi

  echo "[4/4] Device connection..."
  DEVICE_TYPE=$(get_active_device 2>/dev/null || true)
  if [ -n "$DEVICE_TYPE" ]; then
    echo "✓ Device connected ($DEVICE_TYPE)"
    echo ""
    read -p "Install and launch app? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo "Installing..."
      $ADB install -r "$APK_PATH" 2>&1
      echo "Launching..."
      $ADB shell am start -n "$APP_PACKAGE/$APP_ACTIVITY" 2>&1
      sleep 2
      echo "✓ App installed and launched"
      echo ""
      echo "View logs: bash driver.sh logcat"
    fi
  else
    echo "✗ No device connected"
    echo ""
    echo "To connect:"
    echo "  Wired: Connect device via USB"
    echo "  Wireless: bash driver.sh connect"
  fi

  echo ""
  echo "SMOKE TEST PASSED"
}

cmd_connect() {
  echo "=== Device Connection Status ==="

  # Check wired
  if check_wired_device; then
    echo "✓ Wired device connected"

    # Auto-detect WiFi info for wireless setup
    echo ""
    echo "Device network info:"
    local wifi_ip
    wifi_ip=$(get_device_wifi_ip 2>/dev/null || true)
    local wifi_mac
    wifi_mac=$(get_device_wifi_mac 2>/dev/null || true)

    if [ -n "$wifi_ip" ]; then
      echo "  WiFi IP:  $wifi_ip"
      echo "  WiFi MAC: ${wifi_mac:-unknown}"

      # Check same LAN
      local comp_ip
      comp_ip=$(get_computer_ip "$wifi_ip" 2>/dev/null || true)
      if [ -n "$comp_ip" ]; then
        echo "  Computer: $comp_ip"
        if check_same_lan "$wifi_ip" "$comp_ip"; then
          echo "  LAN:      ✓ Same network"
          echo ""
          echo "  Wireless connection available: adb connect $wifi_ip:<port>"
        else
          echo "  LAN:      ✗ Different network"
        fi
      fi
    else
      echo "  WiFi:     Not connected"
    fi
  else
    echo "✗ No wired device"
  fi

  echo ""

  # Check wireless
  if check_wireless_device; then
    echo "✓ Wireless device connected ($WIRELESS_IP:$WIRELESS_PORT)"
  elif [ -n "${WIRELESS_IP:-}" ]; then
    echo "✗ No wireless device"
    echo ""
    read -p "Try wireless connection? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      connect_wireless
    fi
  else
    echo "✗ Wireless not configured (run: bash driver.sh init)"
  fi
}

cmd_devices() {
  echo "=== Connected devices ==="
  $ADB devices -l 2>&1
  echo ""

  # Show network info if wired device connected
  if check_wired_device; then
    echo "=== Device Network ==="
    local wifi_ip
    wifi_ip=$(get_device_wifi_ip 2>/dev/null || true)
    local wifi_mac
    wifi_mac=$(get_device_wifi_mac 2>/dev/null || true)
    echo "WiFi IP:  ${wifi_ip:-not connected}"
    echo "WiFi MAC: ${wifi_mac:-unknown}"
  fi

  echo ""
  echo "ADB path: $ADB"
}

cmd_help() {
  echo "Android App Builder Driver"
  echo ""
  echo "Usage: driver.sh <command>"
  echo ""
  echo "Commands:"
  echo "  init       Initialize project configuration (auto-detect + user input)"
  echo "  build      Build debug APK"
  echo "  test       Run unit tests"
  echo "  install    Build and install APK (auto-connect device)"
  echo "  launch     Launch app on device"
  echo "  logcat     View app logs"
  echo "  clean      Clean build"
  echo "  smoke      Full smoke test (build + test + install)"
  echo "  connect    Check/connect wireless device"
  echo "  devices    List connected devices"
}

# ============================================================
# Main
# ============================================================

# Handle init and help without requiring config
case "$CMD" in
  init)
    cmd_init
    exit 0
    ;;
  help|--help|-h)
    cmd_help
    exit 0
    ;;
esac

# Load config for all other commands
load_config

# Detect Gradle
GRADLE=$(detect_gradle 2>/dev/null || true)
if [ -z "$GRADLE" ]; then
  echo "ERROR: No gradle wrapper found"
  exit 1
fi

# Detect ADB (for commands that need it)
case "$CMD" in
  build|test|clean)
    ;;
  *)
    ADB=$(detect_adb 2>/dev/null || true)
    if [ -z "$ADB" ]; then
      echo "ERROR: ADB not found. Please install Android SDK Platform Tools."
      exit 1
    fi
    ;;
esac

# Run command
case "$CMD" in
  build)    cmd_build ;;
  test)     cmd_test ;;
  install)  cmd_install ;;
  launch)   cmd_launch ;;
  logcat)   cmd_logcat ;;
  clean)    cmd_clean ;;
  smoke)    cmd_smoke ;;
  connect)  cmd_connect ;;
  devices)  cmd_devices ;;
  *)
    echo "Unknown command: $CMD"
    echo ""
    cmd_help
    exit 1
    ;;
esac
