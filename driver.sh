#!/usr/bin/env bash
# Android App Builder Driver
# Usage: bash driver.sh <command> [options]
# Commands: init | build | test | install | launch | logcat | clean | smoke | connect | devices | doctor | screenshot | ui-dump | inspect

set -euo pipefail

# ============================================================
# Global setup
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(pwd)"
cd "$PROJECT_ROOT"

CONFIG_FILE="$SCRIPT_DIR/app-config.env"
CMD="${1:-help}"
shift 2>/dev/null || true
ARGS=("$@")

# Parse global flags
JSON_MODE=false
for arg in "${ARGS[@]}"; do
  if [ "$arg" = "--json" ]; then
    JSON_MODE=true
  fi
done

# ============================================================
# Logging functions
# ============================================================

log_info()  { echo "[INFO] $*"; }
log_warn()  { echo "[WARN] $*"; }
log_error() { echo "[ERROR] $*"; }
log_ok()    { echo "[OK] $*"; }

# ============================================================
# JSON helpers (no jq dependency)
# ============================================================

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  echo -n "$s"
}

# ============================================================
# Auto-detection functions
# ============================================================

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

detect_gradle() {
  if [ -f "./gradlew" ]; then
    echo "./gradlew"
  elif [ -f "./gradlew.bat" ]; then
    echo "./gradlew.bat"
  else
    return 1
  fi
}

detect_adb() {
  if command -v adb &>/dev/null; then
    echo "adb"
  elif [ -f "$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe" ]; then
    echo "$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
  elif [ -f "$HOME/AppData/Local/Android/Sdk/platform-tools/adb.exe" ]; then
    echo "$HOME/AppData/Local/Android/Sdk/platform-tools/adb.exe"
  else
    log_error "ADB not found. Download: https://googledownloads.cn/android/repository/platform-tools-latest-windows.zip" >&2
    return 1
  fi
}

# ============================================================
# Device network detection
# ============================================================

get_device_wifi_ip() {
  $ADB shell ip addr show wlan0 2>/dev/null | grep -oP 'inet \K[0-9.]+' | head -1
}

get_device_wifi_mac() {
  $ADB shell ip addr show wlan0 2>/dev/null | grep -oP 'link/ether \K[0-9a-f:]+' | head -1
}

get_device_adb_port() {
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

get_computer_ip() {
  local device_ip="$1"
  if [ -z "$device_ip" ]; then
    ip addr show 2>/dev/null | grep -oP 'inet \K[0-9.]+' | grep -v '^127\.' | head -1 || \
    hostname -I 2>/dev/null | awk '{print $1}' || \
    return 1
  else
    local subnet
    subnet=$(echo "$device_ip" | cut -d'.' -f1-3)
    ip addr show 2>/dev/null | grep -oP 'inet \K[0-9.]+' | grep "^${subnet}\." | head -1 || \
    return 1
  fi
}

check_same_lan() {
  local device_ip="$1"
  local computer_ip="$2"
  if [ -z "$device_ip" ] || [ -z "$computer_ip" ]; then
    return 1
  fi
  local device_subnet
  device_subnet=$(echo "$device_ip" | cut -d'.' -f1-3)
  local computer_subnet
  computer_subnet=$(echo "$computer_ip" | cut -d'.' -f1-3)
  [ "$device_subnet" = "$computer_subnet" ]
}

# ============================================================
# Config management
# ============================================================

load_config() {
  if [ ! -f "$CONFIG_FILE" ]; then
    log_error "Configuration not found. Run: bash driver.sh init"
    exit 1
  fi
  source "$CONFIG_FILE"

  if [ -z "${APP_PACKAGE:-}" ]; then
    log_error "APP_PACKAGE not set. Run: bash driver.sh init"
    exit 1
  fi
  if [ -z "${APP_ACTIVITY:-}" ]; then
    log_error "APP_ACTIVITY not set. Run: bash driver.sh init"
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
  log_ok "Configuration saved to: $CONFIG_FILE"
}

# ============================================================
# Device connection
# ============================================================

check_wired_device() {
  local devices
  devices=$($ADB devices 2>/dev/null | grep -v "List" | grep -v "^$" | grep -v "wireless" || true)
  echo "$devices" | grep -q "device$"
}

check_wireless_device() {
  if [ -z "${WIRELESS_IP:-}" ]; then
    return 1
  fi
  $ADB devices 2>/dev/null | grep -q "$WIRELESS_IP:$WIRELESS_PORT"
}

connect_wireless() {
  if [ -z "${WIRELESS_IP:-}" ]; then
    log_error "No wireless device configured. Run: bash driver.sh init"
    return 1
  fi

  log_info "Connecting to wireless device: $WIRELESS_IP:$WIRELESS_PORT"

  if check_wireless_device; then
    log_ok "Already connected to $WIRELESS_IP:$WIRELESS_PORT"
    return 0
  fi

  if $ADB connect "$WIRELESS_IP:$WIRELESS_PORT" 2>&1 | grep -q "connected"; then
    log_ok "Connected to $WIRELESS_IP:$WIRELESS_PORT"
    return 0
  else
    log_error "Failed to connect to $WIRELESS_IP:$WIRELESS_PORT"
    log_info "Troubleshooting:"
    log_info "  1. Ensure device and computer are on the same network"
    log_info "  2. Enable wireless debugging (Developer options)"
    log_info "  3. Pair first: adb pair $WIRELESS_IP:<pairing_port>"
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

ensure_device_connected() {
  local device_type
  device_type=$(get_active_device 2>/dev/null || true)
  if [ -z "$device_type" ]; then
    log_warn "No device found. Attempting wireless connection..."
    if ! connect_wireless; then
      log_error "No device available"
      return 1
    fi
  fi
  return 0
}

# ============================================================
# Device info helpers
# ============================================================

get_current_activity() {
  # Get the current foreground activity
  $ADB shell dumpsys activity activities 2>/dev/null | \
    grep -oP 'mResumedActivity.*\{[^}]*\K[a-zA-Z0-9.]+/[a-zA-Z0-9.]+' | head -1 || \
  $ADB shell dumpsys window 2>/dev/null | \
    grep -oP 'mCurrentFocus.*\{[^}]*\K[a-zA-Z0-9.]+/[a-zA-Z0-9.]+' | head -1
}

wait_for_activity() {
  local target_activity="$1"
  local timeout="${2:-15}"
  local elapsed=0

  log_info "Waiting for activity: $target_activity (timeout: ${timeout}s)"

  while [ $elapsed -lt $timeout ]; do
    local current
    current=$(get_current_activity 2>/dev/null || true)
    if [ -n "$current" ]; then
      echo "$current"
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  log_warn "Activity detection timeout after ${timeout}s"
  return 1
}

# ============================================================
# Crash analysis
# ============================================================

find_latest_crash() {
  # Extract the latest crash from logcat
  local logcat_output
  logcat_output=$($ADB logcat -d -t 500 2>/dev/null || true)

  if [ -z "$logcat_output" ]; then
    return 1
  fi

  # Find FATAL EXCEPTION or AndroidRuntime crash
  local crash_block
  crash_block=$(echo "$logcat_output" | awk '
    /FATAL EXCEPTION|AndroidRuntime|Process:.*has died/ { found=1; block="" }
    found { block = block "\n" $0 }
    found && /^[[:space:]]*$/ { found=0; print block; block="" }
    END { if (found) print block }
  ' | tail -1)

  if [ -z "$crash_block" ]; then
    # Check for native crashes
    crash_block=$(echo "$logcat_output" | awk '
      /signal 11|signal 6|native crash|DEBUG.*pid/ { found=1; block="" }
      found { block = block "\n" $0 }
      found && /^[[:space:]]*$/ { found=0; print block; block="" }
      END { if (found) print block }
    ' | tail -1)
  fi

  if [ -n "$crash_block" ]; then
    echo "$crash_block"
    return 0
  fi
  return 1
}

analyze_crash() {
  local crash_data="$1"

  # Extract crash type
  local crash_type=""
  crash_type=$(echo "$crash_data" | grep -oP 'FATAL EXCEPTION.*' | head -1 || true)
  if [ -z "$crash_type" ]; then
    crash_type=$(echo "$crash_data" | grep -oP 'signal \d+' | head -1 || true)
  fi

  # Extract exception name
  local exception=""
  exception=$(echo "$crash_data" | grep -oP '[a-zA-Z]+Exception|[a-zA-Z]+Error' | head -1 || true)

  # Extract location
  local location=""
  location=$(echo "$crash_data" | grep -oP '\(.*\.java:\d+\)|\(.*\.kt:\d+\)' | head -1 || true)
  if [ -z "$location" ]; then
    location=$(echo "$crash_data" | grep -oP '[a-zA-Z]+\.(java|kt):\d+' | head -1 || true)
  fi

  # Extract process name
  local process=""
  process=$(echo "$crash_data" | grep -oP 'Process:\s*\K\S+' | head -1 || true)

  echo "type=$(json_escape "${crash_type:-unknown}")"
  echo "exception=$(json_escape "${exception:-unknown}")"
  echo "location=$(json_escape "${location:-unknown}")"
  echo "process=$(json_escape "${process:-unknown}")"
}

check_runtime_crash() {
  local package="$1"
  local logcat_output
  logcat_output=$($ADB logcat -d -t 200 2>/dev/null || true)

  # Check for crashes related to our package
  if echo "$logcat_output" | grep -q "FATAL EXCEPTION" && \
     echo "$logcat_output" | grep -q "$package"; then
    return 0
  fi
  return 1
}

# ============================================================
# cmd_doctor
# ============================================================

cmd_doctor() {
  local results=()

  echo "=== Android Builder Doctor ==="
  echo ""

  # --- Environment checks ---
  log_info "Checking environment..."
  echo ""

  # Java
  if command -v java &>/dev/null; then
    local java_version
    java_version=$(java -version 2>&1 | head -1 | grep -oP '"\K[^"]+' || echo "unknown")
    log_ok "Java detected: $java_version"
    results+=("java=true")
  else
    log_error "Java not found"
    results+=("java=false")
  fi

  # javac
  if command -v javac &>/dev/null; then
    log_ok "javac detected"
    results+=("javac=true")
  else
    log_warn "javac not found (needed for some builds)"
    results+=("javac=false")
  fi

  # ADB
  local detected_adb
  detected_adb=$(detect_adb 2>/dev/null || true)
  if [ -n "$detected_adb" ]; then
    log_ok "ADB detected: $detected_adb"
    results+=("adb=true")
    ADB="$detected_adb"
  else
    log_error "ADB not found"
    results+=("adb=false")
  fi

  # Gradle
  local detected_gradle
  detected_gradle=$(detect_gradle 2>/dev/null || true)
  if [ -n "$detected_gradle" ]; then
    log_ok "Gradle detected: $detected_gradle"
    results+=("gradle=true")
  else
    log_warn "Gradle wrapper not found"
    results+=("gradle=false")
  fi

  # ANDROID_HOME / ANDROID_SDK_ROOT
  if [ -n "${ANDROID_HOME:-}" ]; then
    log_ok "ANDROID_HOME: $ANDROID_HOME"
    results+=("android_home=true")
  elif [ -n "${ANDROID_SDK_ROOT:-}" ]; then
    log_ok "ANDROID_SDK_ROOT: $ANDROID_SDK_ROOT"
    results+=("android_home=true")
  else
    log_warn "ANDROID_HOME / ANDROID_SDK_ROOT not set"
    results+=("android_home=false")
  fi

  # Device connection
  echo ""
  log_info "Checking device connection..."
  echo ""

  if [ -n "${ADB:-}" ]; then
    if check_wired_device; then
      log_ok "Wired device connected"
      results+=("device_connected=true")
      results+=("device_type=wired")

      # Get device info
      local wifi_ip
      wifi_ip=$(get_device_wifi_ip 2>/dev/null || true)
      local wifi_mac
      wifi_mac=$(get_device_wifi_mac 2>/dev/null || true)
      if [ -n "$wifi_ip" ]; then
        log_ok "Device WiFi IP: $wifi_ip"
        results+=("wifi_ip=$wifi_ip")
      fi
      if [ -n "$wifi_mac" ]; then
        log_ok "Device WiFi MAC: $wifi_mac"
        results+=("wifi_mac=$wifi_mac")
      fi

      # Check wireless debug support
      local adb_port
      adb_port=$(get_device_adb_port 2>/dev/null || true)
      if [ -n "$adb_port" ]; then
        log_ok "Wireless debug port: $adb_port"
        results+=("wireless_adb=true")
        results+=("adb_port=$adb_port")
      else
        log_info "Wireless debug: port not detected"
        results+=("wireless_adb=false")
      fi
    elif check_wireless_device; then
      log_ok "Wireless device connected ($WIRELESS_IP:$WIRELESS_PORT)"
      results+=("device_connected=true")
      results+=("device_type=wireless")
    else
      log_error "No connected device"
      results+=("device_connected=false")
    fi
  else
    log_error "ADB not available, skipping device checks"
    results+=("device_connected=false")
  fi

  # --- Crash analysis ---
  echo ""
  log_info "Checking for recent crashes..."
  echo ""

  if [ -n "${ADB:-}" ] && check_wired_device || check_wireless_device 2>/dev/null; then
    local crash_data
    crash_data=$(find_latest_crash 2>/dev/null || true)
    if [ -n "$crash_data" ]; then
      log_error "Crash detected!"
      echo ""
      echo "[Crash Detected]"

      local crash_info
      crash_info=$(analyze_crash "$crash_data")

      local crash_type
      crash_type=$(echo "$crash_info" | grep '^type=' | cut -d= -f2-)
      local exception
      exception=$(echo "$crash_info" | grep '^exception=' | cut -d= -f2-)
      local location
      location=$(echo "$crash_info" | grep '^location=' | cut -d= -f2-)

      echo "Type: ${crash_type:-unknown}"
      echo "Exception: ${exception:-unknown}"
      echo "Location: ${location:-unknown}"

      results+=("has_crash=true")
      results+=("crash_type=$(json_escape "$crash_type")")
      results+=("crash_exception=$(json_escape "$exception")")
      results+=("crash_location=$(json_escape "$location")")
    else
      log_ok "No recent crashes found"
      results+=("has_crash=false")
    fi
  else
    log_warn "No device connected, skipping crash check"
    results+=("has_crash=unknown")
  fi

  # --- JSON output ---
  if $JSON_MODE; then
    echo ""
    print_json_doctor "${results[@]}"
  fi

  echo ""
  log_info "Doctor check complete."
}

print_json_doctor() {
  local results=("$@")
  local json="{"

  local first=true
  for item in "${results[@]}"; do
    local key="${item%%=*}"
    local value="${item#*=}"

    if $first; then
      first=false
    else
      json+=","
    fi

    # Convert "true"/"false" strings to JSON booleans
    if [ "$value" = "true" ]; then
      json+="\"$key\":true"
    elif [ "$value" = "false" ]; then
      json+="\"$key\":false"
    else
      json+="\"$key\":\"$(json_escape "$value")\""
    fi
  done

  json+="}"
  echo "$json"
}

# ============================================================
# cmd_screenshot
# ============================================================

cmd_screenshot() {
  local custom_name="${1:-}"
  local output_dir="./screenshots"

  ensure_device_connected || exit 1

  mkdir -p "$output_dir"

  # Generate filename
  local filename
  if [ -n "$custom_name" ]; then
    filename="${custom_name}.png"
  else
    filename="screenshot_$(date +%Y%m%d_%H%M%S).png"
  fi
  local output_path="$output_dir/$filename"
  local tmp_file="/sdcard/__android_builder_tmp.png"

  log_info "Taking screenshot..."

  # Capture on device
  if ! $ADB shell screencap -p "$tmp_file" 2>/dev/null; then
    log_error "Failed to capture screenshot on device"
    return 1
  fi

  # Pull to local
  if ! $ADB pull "$tmp_file" "$output_path" 2>/dev/null; then
    log_error "Failed to pull screenshot"
    $ADB shell rm -f "$tmp_file" 2>/dev/null
    return 1
  fi

  # Cleanup temp file on device
  $ADB shell rm -f "$tmp_file" 2>/dev/null

  if [ -f "$output_path" ]; then
    log_ok "Screenshot saved:"
    log_info "$output_path"
    echo "$output_path"
  else
    log_error "Screenshot file not created"
    return 1
  fi
}

# ============================================================
# cmd_ui_dump
# ============================================================

cmd_ui_dump() {
  local output_dir="./ui-dumps"

  ensure_device_connected || exit 1

  mkdir -p "$output_dir"

  local filename="ui_$(date +%Y%m%d_%H%M%S).xml"
  local output_path="$output_dir/$filename"
  local tmp_file="/sdcard/window_dump.xml"

  log_info "Dumping UI hierarchy..."

  # Dump UI on device
  if ! $ADB shell uiautomator dump "$tmp_file" 2>/dev/null; then
    log_error "Failed to dump UI hierarchy"
    return 1
  fi

  # Pull to local
  if ! $ADB pull "$tmp_file" "$output_path" 2>/dev/null; then
    log_error "Failed to pull UI dump"
    return 1
  fi

  # Cleanup
  $ADB shell rm -f "$tmp_file" 2>/dev/null

  if [ -f "$output_path" ]; then
    log_ok "UI dumped:"
    log_info "$output_path"
    echo "$output_path"
  else
    log_error "UI dump file not created"
    return 1
  fi
}

# ============================================================
# cmd_inspect (screenshot + ui-dump)
# ============================================================

cmd_inspect() {
  echo "=== Inspecting current screen ==="
  echo ""

  ensure_device_connected || exit 1

  # Screenshot
  log_info "[1/2] Taking screenshot..."
  local screenshot_path
  screenshot_path=$(cmd_screenshot "inspect_$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true)

  # UI dump
  log_info "[2/2] Dumping UI hierarchy..."
  local ui_dump_path
  ui_dump_path=$(cmd_ui_dump 2>/dev/null || true)

  echo ""
  echo "=== Inspection Results ==="
  if [ -n "$screenshot_path" ]; then
    log_ok "Screenshot: $screenshot_path"
  else
    log_error "Screenshot failed"
  fi
  if [ -n "$ui_dump_path" ]; then
    log_ok "UI dump: $ui_dump_path"
  else
    log_error "UI dump failed"
  fi
}

# ============================================================
# cmd_init
# ============================================================

cmd_init() {
  echo "=== Android Builder: Initialize Configuration ==="
  echo ""

  # --- Auto-detect project config ---
  log_info "[1/4] Auto-detecting project configuration..."
  echo ""

  local detected_pkg
  detected_pkg=$(detect_package 2>/dev/null || true)
  if [ -n "$detected_pkg" ]; then
    log_ok "Package: $detected_pkg"
  else
    log_warn "Package: not detected"
  fi

  local detected_act
  detected_act=$(detect_activity 2>/dev/null || true)
  if [ -n "$detected_act" ]; then
    log_ok "Activity: $detected_act"
  else
    log_warn "Activity: not detected"
  fi

  local detected_gradle
  detected_gradle=$(detect_gradle 2>/dev/null || true)
  if [ -n "$detected_gradle" ]; then
    log_ok "Gradle: $detected_gradle"
  else
    log_warn "Gradle: not detected"
  fi

  local detected_adb
  detected_adb=$(detect_adb 2>/dev/null || true)
  if [ -n "$detected_adb" ]; then
    log_ok "ADB: $detected_adb"
  else
    log_warn "ADB: not detected"
  fi

  echo ""

  # --- Detect device network info ---
  log_info "[2/4] Detecting device network information..."
  echo ""

  local device_wifi_ip=""
  local device_wifi_mac=""
  local computer_ip=""
  local same_lan=false
  local adb_port=""

  if [ -n "$detected_adb" ]; then
    ADB="$detected_adb"

    if check_wired_device; then
      log_ok "USB device connected"

      device_wifi_ip=$(get_device_wifi_ip 2>/dev/null || true)
      device_wifi_mac=$(get_device_wifi_mac 2>/dev/null || true)

      if [ -n "$device_wifi_ip" ]; then
        log_ok "Device WiFi IP: $device_wifi_ip"
        if [ -n "$device_wifi_mac" ]; then
          log_ok "Device WiFi MAC: $device_wifi_mac"
        fi

        computer_ip=$(get_computer_ip "$device_wifi_ip" 2>/dev/null || true)
        if [ -n "$computer_ip" ]; then
          log_ok "Computer IP: $computer_ip"
          if check_same_lan "$device_wifi_ip" "$computer_ip"; then
            log_ok "Same LAN detected"
            same_lan=true

            adb_port=$(get_device_adb_port 2>/dev/null || true)
            if [ -n "$adb_port" ]; then
              log_ok "Wireless debug port: $adb_port"
            else
              log_warn "Wireless debug port: not detected"
            fi
          else
            log_warn "Different LAN - wireless connection not available"
          fi
        else
          log_warn "Computer IP: not detected"
        fi
      else
        log_warn "Device WiFi: not connected"
      fi
    else
      log_warn "No USB device connected"
    fi
  else
    log_warn "ADB not available"
  fi

  echo ""

  # --- User input for project config ---
  log_info "[3/4] Confirm or fill in project configuration..."
  echo ""

  # Package
  if [ -n "$detected_pkg" ]; then
    read -p "  Package name [$detected_pkg]: " input_pkg
    APP_PACKAGE="${input_pkg:-$detected_pkg}"
  else
    read -p "  Package name (e.g. com.example.myapp): " APP_PACKAGE
    if [ -z "$APP_PACKAGE" ]; then
      log_error "Package name is required"
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
      log_error "Activity is required"
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
        log_warn "Port is required for wireless connection"
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
  log_info "[4/4] Configuration summary:"
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
    log_info "Try: bash driver.sh smoke"
  else
    log_info "Configuration not saved."
    exit 0
  fi
}

# ============================================================
# cmd_build
# ============================================================

cmd_build() {
  echo "=== Building debug APK ==="
  $GRADLE assembleDebug --console=plain 2>&1 | tail -5
  log_ok "APK: $APK_PATH"
}

# ============================================================
# cmd_test
# ============================================================

cmd_test() {
  echo "=== Running unit tests ==="
  $GRADLE test --console=plain 2>&1 | tail -10
}

# ============================================================
# cmd_install
# ============================================================

cmd_install() {
  echo "=== Installing APK on device ==="

  if [ ! -f "$APK_PATH" ]; then
    log_warn "APK not found, building first..."
    $GRADLE assembleDebug --console=plain 2>&1 | tail -3
  fi

  ensure_device_connected || exit 1

  local device_type
  device_type=$(get_active_device)
  log_info "Installing to $device_type device..."

  if $ADB install -r "$APK_PATH" 2>&1; then
    log_ok "APK installed successfully"
  else
    log_error "APK installation failed"
    return 1
  fi
}

# ============================================================
# cmd_launch
# ============================================================

cmd_launch() {
  echo "=== Launching app ==="

  ensure_device_connected || exit 1

  if $ADB shell am start -n "$APP_PACKAGE/$APP_ACTIVITY" 2>&1; then
    sleep 2
    log_ok "App launched"
  else
    log_error "Failed to launch app"
    return 1
  fi
}

# ============================================================
# cmd_logcat
# ============================================================

cmd_logcat() {
  echo "=== Recent logcat ==="

  ensure_device_connected || exit 1

  local filter
  filter=$(echo "$LOGCAT_TAGS" | tr ',' ' ')

  $ADB logcat -d -t 100 --pid=$($ADB shell pidof "$APP_PACKAGE" 2>/dev/null || echo 0) 2>/dev/null || \
  $ADB logcat -d -t 100 -s $filter 2>/dev/null || \
  log_warn "No running process found. Start the app first."
}

# ============================================================
# cmd_clean
# ============================================================

cmd_clean() {
  echo "=== Cleaning build ==="
  $GRADLE clean --console=plain 2>&1 | tail -3
  log_ok "Build cleaned"
}

# ============================================================
# cmd_smoke (enhanced)
# ============================================================

cmd_smoke() {
  local smoke_results=()
  local smoke_passed=true

  echo "=== Smoke Test ==="
  echo ""

  # Step 1: Build
  log_info "[1/6] Building..."
  if $GRADLE assembleDebug --console=plain 2>&1 | tail -3; then
    log_ok "Build succeeded"
    smoke_results+=("build=true")
  else
    log_error "Build failed"
    smoke_results+=("build=false")
    smoke_passed=false
  fi

  # Step 2: Test
  log_info "[2/6] Testing..."
  if $GRADLE test --console=plain 2>&1 | tail -5; then
    log_ok "Tests passed"
    smoke_results+=("test=true")
  else
    log_warn "Tests failed (non-blocking)"
    smoke_results+=("test=false")
  fi

  # Step 3: Check APK
  log_info "[3/6] Checking APK..."
  if [ -f "$APK_PATH" ]; then
    local size
    size=$(du -h "$APK_PATH" | cut -f1)
    log_ok "APK exists: $APK_PATH ($size)"
    smoke_results+=("apk=true")
  else
    log_error "APK not found!"
    smoke_results+=("apk=false")
    smoke_passed=false
  fi

  # Step 4: Device connection
  log_info "[4/6] Checking device..."
  if ensure_device_connected 2>/dev/null; then
    local device_type
    device_type=$(get_active_device)
    log_ok "Device connected ($device_type)"
    smoke_results+=("device=true")
  else
    log_error "No device connected"
    smoke_results+=("device=false")
    smoke_passed=false
  fi

  # Step 5: Install and Launch
  if [ "${smoke_results[-1]}" = "device=true" ] && [ "$smoke_passed" = true ]; then
    log_info "[5/6] Installing and launching..."

    if $ADB install -r "$APK_PATH" 2>&1; then
      log_ok "Installed"
      smoke_results+=("install=true")

      # Launch
      $ADB shell am start -n "$APP_PACKAGE/$APP_ACTIVITY" 2>&1
      log_ok "Launched"
      smoke_results+=("launch=true")

      # Wait for activity
      log_info "Waiting for app to stabilize..."
      sleep 10

      # Check current activity
      local current_activity
      current_activity=$(get_current_activity 2>/dev/null || true)
      if [ -n "$current_activity" ]; then
        log_ok "Activity detected: $current_activity"
        smoke_results+=("activity=true")
      else
        log_warn "Could not detect current activity"
        smoke_results+=("activity=false")
      fi

      # Check for crashes
      log_info "[6/6] Checking for crashes..."
      if check_runtime_crash "$APP_PACKAGE"; then
        log_error "App crashed after launch!"
        smoke_results+=("crash=false")
        smoke_passed=false

        # Show crash details
        local crash_data
        crash_data=$(find_latest_crash 2>/dev/null || true)
        if [ -n "$crash_data" ]; then
          echo ""
          echo "[Crash Details]"
          local crash_info
          crash_info=$(analyze_crash "$crash_data")
          local exception
          exception=$(echo "$crash_info" | grep '^exception=' | cut -d= -f2-)
          local location
          location=$(echo "$crash_info" | grep '^location=' | cut -d= -f2-)
          echo "Exception: ${exception:-unknown}"
          echo "Location: ${location:-unknown}"
        fi
      else
        log_ok "No crash detected"
        smoke_results+=("crash=true")
      fi

      # Auto screenshot
      log_info "Taking smoke test screenshot..."
      local screenshot_path
      screenshot_path=$(cmd_screenshot "smoke_$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true)
      if [ -n "$screenshot_path" ]; then
        smoke_results+=("screenshot=$screenshot_path")
      fi
    else
      log_error "Installation failed"
      smoke_results+=("install=false")
      smoke_results+=("launch=false")
      smoke_passed=false
    fi
  else
    smoke_results+=("install=false")
    smoke_results+=("launch=false")
  fi

  # --- Summary ---
  echo ""
  echo "=== Smoke Test Summary ==="
  echo ""

  for item in "${smoke_results[@]}"; do
    local key="${item%%=*}"
    local value="${item#*=}"

    case "$key" in
      build)     [ "$value" = "true" ] && log_ok "Build" || log_error "Build" ;;
      test)      [ "$value" = "true" ] && log_ok "Tests" || log_warn "Tests" ;;
      apk)       [ "$value" = "true" ] && log_ok "APK" || log_error "APK" ;;
      device)    [ "$value" = "true" ] && log_ok "Device" || log_error "Device" ;;
      install)   [ "$value" = "true" ] && log_ok "Install" || log_error "Install" ;;
      launch)    [ "$value" = "true" ] && log_ok "Launch" || log_error "Launch" ;;
      activity)  [ "$value" = "true" ] && log_ok "Activity" || log_warn "Activity" ;;
      crash)     [ "$value" = "true" ] && log_ok "No Crash" || log_error "Crash Detected" ;;
      screenshot) log_info "Screenshot: $value" ;;
    esac
  done

  echo ""
  if $smoke_passed; then
    log_ok "SMOKE TEST PASSED"
  else
    log_error "SMOKE TEST FAILED"
    exit 1
  fi

  # JSON output
  if $JSON_MODE; then
    echo ""
    local json="{"
    local first=true
    for item in "${smoke_results[@]}"; do
      local key="${item%%=*}"
      local value="${item#*=}"
      if $first; then first=false; else json+=","; fi
      if [ "$value" = "true" ]; then
        json+="\"$key\":true"
      elif [ "$value" = "false" ]; then
        json+="\"$key\":false"
      else
        json+="\"$key\":\"$(json_escape "$value")\""
      fi
    done
    json+=",\"passed\":$smoke_passed"
    json+="}"
    echo "$json"
  fi
}

# ============================================================
# cmd_connect
# ============================================================

cmd_connect() {
  echo "=== Device Connection Status ==="

  # Check wired
  if check_wired_device; then
    log_ok "Wired device connected"

    echo ""
    log_info "Device network info:"
    local wifi_ip
    wifi_ip=$(get_device_wifi_ip 2>/dev/null || true)
    local wifi_mac
    wifi_mac=$(get_device_wifi_mac 2>/dev/null || true)

    if [ -n "$wifi_ip" ]; then
      echo "  WiFi IP:  $wifi_ip"
      echo "  WiFi MAC: ${wifi_mac:-unknown}"

      local comp_ip
      comp_ip=$(get_computer_ip "$wifi_ip" 2>/dev/null || true)
      if [ -n "$comp_ip" ]; then
        echo "  Computer: $comp_ip"
        if check_same_lan "$wifi_ip" "$comp_ip"; then
          echo "  LAN:      ✓ Same network"
          echo ""
          log_info "Wireless connection available: adb connect $wifi_ip:<port>"
        else
          echo "  LAN:      ✗ Different network"
        fi
      fi
    else
      echo "  WiFi:     Not connected"
    fi
  else
    log_warn "No wired device"
  fi

  echo ""

  # Check wireless
  if check_wireless_device; then
    log_ok "Wireless device connected ($WIRELESS_IP:$WIRELESS_PORT)"
  elif [ -n "${WIRELESS_IP:-}" ]; then
    log_warn "No wireless device"
    echo ""
    read -p "Try wireless connection? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      connect_wireless
    fi
  else
    log_warn "Wireless not configured (run: bash driver.sh init)"
  fi
}

# ============================================================
# cmd_devices
# ============================================================

cmd_devices() {
  echo "=== Connected devices ==="

  if $JSON_MODE; then
    print_json_devices
  else
    $ADB devices -l 2>&1
    echo ""

    if check_wired_device; then
      log_info "Device Network:"
      local wifi_ip
      wifi_ip=$(get_device_wifi_ip 2>/dev/null || true)
      local wifi_mac
      wifi_mac=$(get_device_wifi_mac 2>/dev/null || true)
      echo "  WiFi IP:  ${wifi_ip:-not connected}"
      echo "  WiFi MAC: ${wifi_mac:-unknown}"
    fi

    echo ""
    echo "ADB path: $ADB"
  fi
}

print_json_devices() {
  local devices_output
  devices_output=$($ADB devices 2>/dev/null | grep -v "List" | grep -v "^$" || true)

  echo "{"
  echo "  \"devices\": ["

  local first=true
  while IFS= read -r line; do
    if [ -z "$line" ]; then
      continue
    fi

    local serial
    serial=$(echo "$line" | awk '{print $1}')
    local state
    state=$(echo "$line" | awk '{print $2}')

    # Get IP if available
    local ip=""
    local wifi=false
    if [[ "$serial" == *":"* ]]; then
      ip="${serial%%:*}"
      wifi=true
    elif [ "$state" = "device" ]; then
      ip=$(get_device_wifi_ip 2>/dev/null || true)
      if [ -n "$ip" ]; then
        wifi=true
      fi
    fi

    if $first; then
      first=false
    else
      echo ","
    fi

    echo -n "    {"
    echo -n "\"serial\":\"$(json_escape "$serial")\","
    echo -n "\"state\":\"$(json_escape "$state")\","
    echo -n "\"ip\":\"$(json_escape "${ip:-}")\","
    echo -n "\"wifi\":$wifi"
    echo -n "}"
  done <<< "$devices_output"

  echo ""
  echo "  ]"
  echo "}"
}

# ============================================================
# cmd_help
# ============================================================

cmd_help() {
  echo "Android App Builder Driver"
  echo ""
  echo "Usage: driver.sh <command> [options]"
  echo ""
  echo "Commands:"
  echo "  init        Initialize project configuration (auto-detect + user input)"
  echo "  build       Build debug APK"
  echo "  test        Run unit tests"
  echo "  install     Build and install APK (auto-connect device)"
  echo "  launch      Launch app on device"
  echo "  logcat      View app logs"
  echo "  clean       Clean build"
  echo "  smoke       Full smoke test (build + test + install + launch + crash check)"
  echo "  connect     Check/connect wireless device"
  echo "  devices     List connected devices"
  echo "  doctor      Environment diagnosis + crash analysis"
  echo "  screenshot  Take device screenshot"
  echo "  ui-dump     Dump UI hierarchy (XML)"
  echo "  inspect     Take screenshot + UI dump (for AI analysis)"
  echo ""
  echo "Options:"
  echo "  --json      Output in JSON format (for: devices, doctor, smoke)"
  echo ""
  echo "Examples:"
  echo "  bash driver.sh init"
  echo "  bash driver.sh smoke"
  echo "  bash driver.sh doctor --json"
  echo "  bash driver.sh screenshot my_capture"
  echo "  bash driver.sh inspect"
}

# ============================================================
# Main dispatcher
# ============================================================

# Commands that don't need config or ADB
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

# Load config for remaining commands
load_config

# Detect Gradle (needed for build-related commands)
case "$CMD" in
  build|test|install|clean|smoke)
    GRADLE=$(detect_gradle 2>/dev/null || true)
    if [ -z "$GRADLE" ]; then
      log_error "No gradle wrapper found"
      exit 1
    fi
    ;;
esac

# Detect ADB (needed for device commands)
case "$CMD" in
  build|test|clean)
    # These don't need ADB
    ;;
  *)
    ADB=$(detect_adb 2>/dev/null || true)
    if [ -z "$ADB" ]; then
      log_error "ADB not found. Please install Android SDK Platform Tools."
      exit 1
    fi
    ;;
esac

# Dispatch command
case "$CMD" in
  build)      cmd_build ;;
  test)       cmd_test ;;
  install)    cmd_install ;;
  launch)     cmd_launch ;;
  logcat)     cmd_logcat ;;
  clean)      cmd_clean ;;
  smoke)      cmd_smoke ;;
  connect)    cmd_connect ;;
  devices)    cmd_devices ;;
  doctor)     cmd_doctor ;;
  screenshot) cmd_screenshot "${ARGS[0]:-}" ;;
  ui-dump)    cmd_ui_dump ;;
  inspect)    cmd_inspect ;;
  *)
    log_error "Unknown command: $CMD"
    echo ""
    cmd_help
    exit 1
    ;;
esac
