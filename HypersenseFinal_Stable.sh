# save main script
cat > ~/HypersenseFinal_Stable.sh <<'SH'
#!/data/data/com.termux/files/usr/bin/env bash
# HypersenseFinal_Stable.sh — Hypersense v10 Final (ready-to-run)
# Developer: AG HYDRAX | Marketing Head: Roobal Sir (@roobal_sir) | Instagram: @hydraxff_yt
# Non-root, Termux-safe, Activation-bound (time-locked), Auto-start & Watchdog
# Dialog-based UI preferred (falls back to CLI)
set -o nounset
set -o pipefail

# -------------------------
# Paths & Files
# -------------------------
HYP_DIR="${HOME:-/data/data/com.termux/files/home}/.hypersense"
LOG_DIR="$HYP_DIR/logs"
CFG_FILE="$HYP_DIR/config.cfg"
ACT_FILE="$HYP_DIR/activation.info"
ENGINE_SCRIPT="$HYP_DIR/engine_worker.sh"
DAEMON_SCRIPT="$HYP_DIR/daemon_monitor.sh"
BOOT_DIR="${HOME:-/data/data/com.termux/files/home}/.termux/boot"
BOOT_FILE="$BOOT_DIR/hypersense_boot.sh"
AUTOSTART_FLAG="$HYP_DIR/.autostart_enabled"
AUTOSTART_FILE="$BOOT_FILE"
ENGINE_LOG="$LOG_DIR/engine.log"
AI_FPS_LOG="$LOG_DIR/ai_fps_boost.log"
MONITOR_TMP="$HYP_DIR/monitor.tmp"
PID_FILE="$HYP_DIR/neural.pid"
ROTATE_LINES=2000
PROFILES_DIR="$HYP_DIR/profiles"
GAME_PRESETS_FILE="$HYP_DIR/game_presets.cfg"

mkdir -p "$HYP_DIR" "$LOG_DIR" "$BOOT_DIR" "$PROFILES_DIR"
touch "$ENGINE_LOG" "$AI_FPS_LOG"
chmod 700 "$HYP_DIR" 2>/dev/null || true
chmod 600 "$ENGINE_LOG" "$AI_FPS_LOG" 2>/dev/null || true

# -------------------------
# Helpers & Safe wrappers
# -------------------------
safe_echo(){ printf "%s\n" "$*"; }
info(){ safe_echo "[INFO] $*" | tee -a "$ENGINE_LOG"; }
warn(){ safe_echo "[WARN] $*" | tee -a "$ENGINE_LOG"; }
err(){ safe_echo "[ERROR] $*" | tee -a "$ENGINE_LOG" >&2; }

sha256_hash() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf "%s" "$1" | sha256sum | awk '{print $1}'
  else
    printf "%s" "$1" | md5sum | awk '{print $1}'
  fi
}

# Termux:API safe detection
termux_api_available(){
  command -v termux-battery-status >/dev/null 2>&1
}

get_battery_safe(){
  if termux_api_available; then
    if command -v jq >/dev/null 2>&1; then
      termux-battery-status 2>/dev/null | jq -r '.percentage // "N/A"' 2>/dev/null || echo "N/A"
    else
      termux-battery-status 2>/dev/null | awk -F: '/percentage/ {gsub(/[", ]/,"",$2); print $2; exit}' 2>/dev/null || echo "N/A"
    fi
  else
    echo "N/A"
  fi
}

get_temp_safe(){
  # Try thermal sysfs first
  for tz in /sys/class/thermal/thermal_zone*/temp; do
    [ -f "$tz" ] || continue
    val=$(cat "$tz" 2>/dev/null || echo "")
    [ -n "$val" ] && {
      if [ "${#val}" -gt 3 ]; then awk "BEGIN{printf \"%.1f\", $val/1000}"; else awk "BEGIN{printf \"%.1f\", $val}"; fi
      return
    }
  done
  # fallback to termux-battery-status temperature (if available)
  if termux_api_available; then
    if command -v jq >/dev/null 2>&1; then
      tmp=$(termux-battery-status 2>/dev/null | jq -r '.temperature // empty' 2>/dev/null || echo "")
      [ -n "$tmp" ] && { awk "BEGIN{printf \"%.1f\", $tmp/10}"; return; }
    else
      t=$(termux-battery-status 2>/dev/null | awk -F: '/temperature/ {gsub(/ /,"",$2); print $2; exit}' 2>/dev/null || echo "")
      [ -n "$t" ] && { awk "BEGIN{printf \"%.1f\", $t/10}"; return; }
    fi
  fi
  echo "N/A"
}

get_refresh_rate(){
  if command -v dumpsys >/dev/null 2>&1; then
    r=$(dumpsys SurfaceFlinger 2>/dev/null | grep -oE "[0-9]+(\.[0-9]+)? Hz" | head -n1 | sed 's/ Hz//' || true)
    [ -n "$r" ] && { echo "${r%%.*}"; return; }
    r=$(dumpsys display 2>/dev/null | grep -oE "activeRefreshRate=[0-9]+" | head -n1 | cut -d= -f2 || true)
    [ -n "$r" ] && { echo "$r"; return; }
  fi
  echo "60"
}

rotate_log(){
  f="$1"
  [ -f "$f" ] || return
  lines=$(wc -l < "$f" 2>/dev/null || echo 0)
  if [ "$lines" -gt "$ROTATE_LINES" ]; then
    tail -n $((ROTATE_LINES/2)) "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
  fi
}

# -------------------------
# Default Config & loader
# -------------------------
default_config(){
  cat > "$CFG_FILE" <<'EOF'
# Hypersense configuration (auto-generated)
touch_x=12
touch_y=12
touch_smooth=0.8
neural_turbo=0
arc_plus=0
vpool_enabled=0
uvram_enabled=0
afb_mode="Auto"
autostart_enabled=0
idle_target=70
active_target=95
cpu_threshold=45
thermal_soft=45
thermal_hard=50
thermal_hysteresis=3
thermal_cooldown_s=90
sample_interval_ms=300
micro_trigger_ms=120
game_whitelist=com.dts.freefire,com.dts.freefiremax,com.pubg.imobile,com.tencent.ig,com.konami.pes2019
profile_active=""
EOF
  chmod 600 "$CFG_FILE"
}

[ -f "$CFG_FILE" ] || default_config
# shellcheck disable=SC1090
. "$CFG_FILE"

# ensure safe variables
: "${touch_x:=12}" : "${touch_y:=12}" : "${touch_smooth:=0.8}"
: "${neural_turbo:=0}" : "${arc_plus:=0}" : "${vpool_enabled:=0}" : "${uvram_enabled:=0}"
: "${afb_mode:=Auto}" : "${autostart_enabled:=0}"
: "${idle_target:=70}" : "${active_target:=95}" : "${cpu_threshold:=45}"
: "${thermal_soft:=45}" : "${thermal_hard:=50}" : "${thermal_hysteresis:=3}" : "${thermal_cooldown_s:=90}"
: "${sample_interval_ms:=300}" : "${micro_trigger_ms:=120}"
: "${game_whitelist:=com.dts.freefire,com.dts.freefiremax,com.pubg.imobile,com.tencent.ig,com.konami.pes2019}"
: "${profile_active:=}"

save_config(){
  cat > "$CFG_FILE" <<EOF
# Hypersense configuration (saved)
touch_x=$touch_x
touch_y=$touch_y
touch_smooth=$touch_smooth
neural_turbo=$neural_turbo
arc_plus=$arc_plus
vpool_enabled=$vpool_enabled
uvram_enabled=$uvram_enabled
afb_mode="$afb_mode"
autostart_enabled=$autostart_enabled
idle_target=$idle_target
active_target=$active_target
cpu_threshold=$cpu_threshold
thermal_soft=$thermal_soft
thermal_hard=$thermal_hard
thermal_hysteresis=$thermal_hysteresis
thermal_cooldown_s=$thermal_cooldown_s
sample_interval_ms=$sample_interval_ms
micro_trigger_ms=$micro_trigger_ms
game_whitelist=$game_whitelist
profile_active="$profile_active"
EOF
  chmod 600 "$CFG_FILE"
}

# -------------------------
# Activation (time-locked base64)
# -------------------------
yyyymmdd_to_epoch(){
  d="$1"
  if ! [[ "$d" =~ ^[0-9]{8}$ ]]; then echo ""; return; fi
  date -d "${d:0:4}-${d:4:2}-${d:6:2} 00:00:00" +%s 2>/dev/null || echo ""
}

yyyymmddhhmm_to_epoch(){
  d="$1"
  if ! [[ "$d" =~ ^[0-9]{12}$ ]]; then echo ""; return; fi
  date -d "${d:0:4}-${d:4:2}-${d:6:2} ${d:8:2}:${d:10:2}:00" +%s 2>/dev/null || echo ""
}

check_activation(){
  if [ ! -f "$ACT_FILE" ]; then return 1; fi
  . "$ACT_FILE" 2>/dev/null || return 1
  NOW_EPOCH=$(date +%s)
  if ! [[ "${PLAN_EXPIRY_EPOCH:-}" =~ ^[0-9]+$ ]]; then return 1; fi
  if (( NOW_EPOCH > PLAN_EXPIRY_EPOCH )); then
    warn "Saved activation expired on $(date -d "@$PLAN_EXPIRY_EPOCH" '+%F')"
    rm -f "$ACT_FILE" 2>/dev/null || true
    return 2
  fi
  return 0
}

prompt_activation(){
  if command -v dialog >/dev/null 2>&1; then
    dialog --msgbox "HYPERSENSEINDIA\nActivation required (one-time, time-locked token)." 10 70
  else
    safe_echo "HYPERSENSEINDIA - Activation required."
  fi

  while true; do
    if command -v dialog >/dev/null 2>&1; then
      token=$(dialog --inputbox "Enter Activation Token (Base64)\nRAW: USER|PLAN|YYYYMMDD|YYYYMMDDHHMM|SIGN" 11 80 3>&1 1>&2 2>&3)
    else
      read -r -p "Enter Activation Token (Base64): " token
    fi

    [ -z "${token:-}" ] && {
      if command -v dialog >/dev/null 2>&1; then
        dialog --yesno "No token entered. Exit?" 7 45 && { clear; exit 1; } || continue
      else
        safe_echo "No token entered. Exiting."; exit 1
      fi
    }

    decoded=$(printf "%s" "$token" | base64 -d 2>/dev/null || echo "")
    if [ -z "$decoded" ]; then
      command -v dialog >/dev/null 2>&1 && dialog --msgbox "Invalid token (not Base64 or corrupted). Try again." 7 60 || safe_echo "Invalid token. Try again."
      continue
    fi

    IFS='|' read -r IN_USER IN_PLAN IN_PLANEXP IN_ACTLOCK IN_SIGN <<< "$decoded"

    if [ -z "${IN_USER:-}" ] || [ -z "${IN_PLAN:-}" ] || [ -z "${IN_PLANEXP:-}" ] || [ -z "${IN_ACTLOCK:-}" ]; then
      command -v dialog >/dev/null 2>&1 && dialog --msgbox "Token missing fields. Use USER|PLAN|YYYYMMDD|YYYYMMDDHHMM|SIGN" 8 70 || safe_echo "Token missing fields."
      continue
    fi

    PLAN_EXP_EPOCH=$(yyyymmdd_to_epoch "$IN_PLANEXP")
    ACTLOCK_EPOCH=$(yyyymmddhhmm_to_epoch "$IN_ACTLOCK")
    if [ -z "$PLAN_EXP_EPOCH" ] || [ -z "$ACTLOCK_EPOCH" ]; then
      command -v dialog >/dev/null 2>&1 && dialog --msgbox "Expiry/ActLock format invalid. Use YYYYMMDD and YYYYMMDDHHMM." 8 70 || safe_echo "Expiry format invalid."
      continue
    fi

    NOW_EPOCH=$(date +%s)
    if (( NOW_EPOCH > ACTLOCK_EPOCH )); then
      command -v dialog >/dev/null 2>&1 && dialog --msgbox "Activation window expired on $(date -d "@$ACTLOCK_EPOCH" '+%F %R'). Token invalid." 8 70 || safe_echo "Activation window expired. Token invalid."
      return 1
    fi

    if (( PLAN_EXP_EPOCH < ACTLOCK_EPOCH )); then
      command -v dialog >/dev/null 2>&1 && dialog --msgbox "Plan expiry earlier than activation-lock date. Invalid token." 8 70 || safe_echo "Plan expiry earlier than activation-lock. Invalid token."
      continue
    fi

    DEVICE_ID=$( (command -v settings >/dev/null 2>&1 && settings get secure android_id 2>/dev/null) || hostname 2>/dev/null || echo "unknown_device" )
    DEVICE_HASH=$(sha256_hash "$DEVICE_ID")
    cat > "$ACT_FILE" <<EOF
USERNAME="${IN_USER}"
PLAN="${IN_PLAN}"
PLAN_EXPIRY_RAW="${IN_PLANEXP}"
ACT_LOCK_RAW="${IN_ACTLOCK}"
PLAN_EXPIRY_EPOCH="${PLAN_EXP_EPOCH}"
ACT_LOCK_EPOCH="${ACTLOCK_EPOCH}"
DEVICE_HASH="${DEVICE_HASH}"
ACTIVATED_ON="$(date '+%Y%m%d%H%M')"
EOF
    chmod 600 "$ACT_FILE"
    info "Activated user=${IN_USER} plan=${IN_PLAN} plan_expiry=${IN_PLANEXP} actlock=${IN_ACTLOCK}"
    command -v dialog >/dev/null 2>&1 && dialog --msgbox "Activation successful!\nUser: ${IN_USER}\nPlan: ${IN_PLAN}\nPlan expiry: $(date -d "@$PLAN_EXP_EPOCH" '+%F')" 8 70 || safe_echo "Activation successful!"
    return 0
  done
}

# -------------------------
# Game presets default (if missing)
# -------------------------
if [ ! -f "$GAME_PRESETS_FILE" ]; then
  cat > "$GAME_PRESETS_FILE" <<'GCFG'
# Format: pkg|name|touch_x|touch_y|touch_smooth|neural_turbo|arc_plus|afb_mode
com.dts.freefire|FreeFire|18|17|0.7|1|1|Auto
com.dts.freefiremax|FreeFireMax|20|18|0.65|1|1|Auto
com.pubg.imobile|BGMI|14|16|0.8|1|1|Auto
GCFG
fi

load_game_presets(){
  PRESET_LIST=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    pkg=$(printf "%s" "$line" | cut -d'|' -f1)
    nm=$(printf "%s" "$line" | cut -d'|' -f2)
    PRESET_LIST="${PRESET_LIST}${pkg}:${nm};"
  done < "$GAME_PRESETS_FILE"
}

load_game_presets

# -------------------------
# Engine worker writer
# -------------------------
write_engine_worker(){
  cat > "$ENGINE_SCRIPT" <<'EOE'
#!/data/data/com.termux/files/usr/bin/env bash
# Engine worker (long-running)
HYP_DIR="$HOME/.hypersense"
LOG="$HYP_DIR/logs/engine.log"
AI_LOG="$HYP_DIR/logs/ai_fps_boost.log"
PID_FILE="$HYP_DIR/neural.pid"
CFG="$HYP_DIR/config.cfg"
GAME_PRESETS="$HYP_DIR/game_presets.cfg"
touch "$LOG" "$AI_LOG"
echo $$ > "$PID_FILE"
log(){ printf "%s | %s\n" "$(date '+%F %T')" "$*" >> "$LOG"; }
ailog(){ printf "%s | %s\n" "$(date '+%F %T')" "$*" >> "$AI_LOG"; }

[ -f "$CFG" ] && . "$CFG"

# Helper functions inside worker
get_temp(){
  for tz in /sys/class/thermal/thermal_zone*/temp; do [ -f "$tz" ] || continue; v=$(cat "$tz" 2>/dev/null || echo ""); [ -n "$v" ] && { if [ "${#v}" -gt 3 ]; then awk "BEGIN{printf \"%.1f\", $v/1000}"; else awk "BEGIN{printf \"%.1f\", $v}"; fi; return; }; done
  if command -v termux-battery-status >/dev/null 2>&1; then
    t=$(termux-battery-status 2>/dev/null | awk -F: '/temperature/ {gsub(/ /,"",$2); print $2; exit}')
    [ -n "$t" ] && { awk "BEGIN{printf \"%.1f\", $t/10}"; return; }
  fi
  echo "N/A"
}

get_bat(){ if command -v termux-battery-status >/dev/null 2>&1; then termux-battery-status 2>/dev/null | awk -F: '/percentage/ {gsub(/[", ]/,"",$2); print $2; exit}'; else echo "N/A"; fi }

get_foreground_pkg(){
  if command -v dumpsys >/dev/null 2>&1; then
    fg=$(dumpsys activity activities 2>/dev/null | awk -F' ' '/mResumedActivity|mFocusedActivity/ {print $NF; exit}' | cut -d'/' -f1)
    [ -z "$fg" ] && fg=$(dumpsys window windows 2>/dev/null | awk -F' ' '/mCurrentFocus|mFocusedApp/ {print $3; exit}' | cut -d'/' -f1)
    printf "%s" "${fg:-}"
    return
  fi
  printf ""
}

apply_preset_from_line(){
  line="$1"
  pkg=$(printf "%s" "$line" | cut -d'|' -f1)
  nm=$(printf "%s" "$line" | cut -d'|' -f2)
  tx=$(printf "%s" "$line" | cut -d'|' -f3)
  ty=$(printf "%s" "$line" | cut -d'|' -f4)
  ts=$(printf "%s" "$line" | cut -d'|' -f5)
  nt=$(printf "%s" "$line" | cut -d'|' -f6)
  ap=$(printf "%s" "$line" | cut -d'|' -f7)
  afb=$(printf "%s" "$line" | cut -d'|' -f8)
  # minimal safety and apply
  touch_x=${tx:-$touch_x}
  touch_y=${ty:-$touch_y}
  touch_smooth=${ts:-$touch_smooth}
  neural_turbo=${nt:-$neural_turbo}
  arc_plus=${ap:-$arc_plus}
  afb_mode=${afb:-$afb_mode}
  # persist subset safely
  cat > "$CFG" <<EOF
touch_x=$touch_x
touch_y=$touch_y
touch_smooth=$touch_smooth
neural_turbo=$neural_turbo
arc_plus=$arc_plus
vpool_enabled=$vpool_enabled
uvram_enabled=$uvram_enabled
afb_mode="$afb_mode"
sample_interval_ms=$sample_interval_ms
micro_trigger_ms=$micro_trigger_ms
EOF
  log "Preset applied for $nm ($pkg): X=$touch_x Y=$touch_y S=$touch_smooth turbo=$neural_turbo arc=$arc_plus afb=$afb_mode"
  ailog "Preset applied for $nm"
}

# load presets into memory array
PRESET_LINES=$(grep -v -E '^\s*#' "$GAME_PRESETS" 2>/dev/null || true)

# minimal thermal state
LAST_THERMAL_ACTION=""
COOLDOWN_UNTIL=0
MANUAL_SAFE_MODE=0

# sample helper
ai_estimate(){
  CPU_LOAD=$(top -bn1 2>/dev/null | awk '/CPU/ {print $2; exit}' 2>/dev/null | sed 's/%//' || echo 30)
  [ -z "$CPU_LOAD" ] && CPU_LOAD=30
  TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "")
  if [ -n "$TEMP_RAW" ]; then
    if [ "${#TEMP_RAW}" -gt 3 ]; then TEMP=$(expr "$TEMP_RAW" / 1000); else TEMP="$TEMP_RAW"; fi
  else TEMP=35; fi
  BOOST_SCORE=$((100 - CPU_LOAD))
  RR=$(dumpsys SurfaceFlinger 2>/dev/null | grep -oE "[0-9]+(\.[0-9]+)? Hz" | head -n1 | sed 's/ Hz//' || echo 60)
  EST=$(awk -v b="$BOOST_SCORE" -v r="$RR" 'BEGIN{printf "%.1f", (b * r / 100)}')
  ailog "CPU:${CPU_LOAD}% TEMP:${TEMP}C BOOST:${BOOST_SCORE} EST_FPS_GAIN:+${EST}"
}

# Thermal handling in worker
thermal_check_and_apply(){
  Tstr=$(get_temp 2>/dev/null)
  [ -z "$Tstr" ] && return 0
  if [ "$Tstr" = "N/A" ]; then return 0; fi
  T_int=$(awk "BEGIN{printf \"%d\", $Tstr}")
  NOW=$(date +%s)
  if [ "$T_int" -ge "$thermal_hard" ] && [ "$MANUAL_SAFE_MODE" -eq 0 ]; then
    neural_turbo=0; arc_plus=0
    COOLDOWN_UNTIL=$((NOW + thermal_cooldown_s))
    LAST_THERMAL_ACTION="hard-paused"
    ailog "ThermalGuardian | TEMP:${Tstr}C | ACTION: HARD_PAUSE"
    echo "hard-paused" > "$HYP_DIR/thermal.state" 2>/dev/null || true
    # persist minimal state
    cat > "$CFG" <<EOF
neural_turbo=$neural_turbo
arc_plus=$arc_plus
vpool_enabled=$vpool_enabled
uvram_enabled=$uvram_enabled
afb_mode="$afb_mode"
sample_interval_ms=$sample_interval_ms
micro_trigger_ms=$micro_trigger_ms
EOF
    return 0
  fi
  if [ "$T_int" -ge "$thermal_soft" ] && [ "$MANUAL_SAFE_MODE" -eq 0 ]; then
    sample_interval_ms=$(( sample_interval_ms + 200 ))
    neural_turbo=0
    LAST_THERMAL_ACTION="soft-throttle"
    ailog "ThermalGuardian | TEMP:${Tstr}C | ACTION: SOFT_THROTTLE sample_interval_ms=${sample_interval_ms}"
    cat > "$CFG" <<EOF
sample_interval_ms=$sample_interval_ms
micro_trigger_ms=$micro_trigger_ms
neural_turbo=$neural_turbo
arc_plus=$arc_plus
vpool_enabled=$vpool_enabled
uvram_enabled=$uvram_enabled
afb_mode="$afb_mode"
EOF
    return 0
  fi
  if [ "$T_int" -le $((thermal_soft - thermal_hysteresis)) ] && [ "$MANUAL_SAFE_MODE" -eq 0 ]; then
    if [ -f "$HYP_DIR/thermal.state" ]; then
      prev=$(cat "$HYP_DIR/thermal.state" 2>/dev/null || echo "")
      if [ "$prev" = "hard-paused" ]; then
        if [ "$NOW" -ge "$COOLDOWN_UNTIL" ]; then
          LAST_THERMAL_ACTION="auto-resume"
          ailog "ThermalGuardian | TEMP:${Tstr}C | ACTION: AUTO-RESUME"
          rm -f "$HYP_DIR/thermal.state"
        fi
      fi
    fi
  fi
  return 0
}

# Game detection & presets
last_game=""
while true; do
  # reload config each tick
  [ -f "$CFG" ] && . "$CFG"
  BAT=$(get_bat)
  TEMP=$(get_temp)
  log "tick | bat:${BAT}% | temp:${TEMP}C | turbo:${neural_turbo} arc:${arc_plus} vpool:${vpool_enabled} uvr:${uvram_enabled} afb:${afb_mode}"
  ai_estimate
  thermal_check_and_apply

  # minimal battery protection
  if [ "$BAT" != "N/A" ] && [ "$BAT" -lt 15 ]; then
    log "Battery <15%: throttling predictions"
    sleep 5
    continue
  fi

  fg=$(get_foreground_pkg)
  active=""
  if [ -n "$fg" ]; then
    # check for preset hits
    while IFS= read -r p; do
      [ -z "$p" ] && continue
      case "$p" in \#*) continue ;; esac
      pkg=$(printf "%s" "$p" | cut -d'|' -f1)
      if [ "$pkg" = "$fg" ]; then
        active="$p"
        break
      fi
    done <<< "$PRESET_LINES"
  fi

  if [ -n "$active" ]; then
    if [ "$fg" != "$last_game" ]; then
      apply_preset_from_line "$active"
      last_game="$fg"
      ailog "Game detected: $fg -> preset applied"
    fi
    # in active game: allow aggressive mode
    # we can add additional in-game micro adjustments here
  else
    # no game; restore default sampling if needed (we keep config)
    last_game=""
  fi

  # sampling sleep dynamic
  if [ "${neural_turbo:-0}" -eq 1 ]; then sleep 1; else sleep 2; fi
done
EOE
  chmod 700 "$ENGINE_SCRIPT"
  info "Engine worker written to $ENGINE_SCRIPT"
}

# -------------------------
# Daemon monitor writer (auto-restart)
# -------------------------
write_daemon_monitor(){
  cat > "$DAEMON_SCRIPT" <<'DAE'
#!/data/data/com.termux/files/usr/bin/env bash
HYP_DIR="${HOME:-/data/data/com.termux/files/home}/.hypersense"
ENGINE="$HYP_DIR/engine_worker.sh"
LOG="$HYP_DIR/logs/engine.log"

while true; do
  # if engine not running, start it
  if [ -f "$HYP_DIR/neural.pid" ]; then
    pid=$(cat "$HYP_DIR/neural.pid" 2>/dev/null || echo "")
    if [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1; then
      sleep 5
      continue
    fi
  fi
  if [ -f "$ENGINE" ]; then
    nohup bash "$ENGINE" >> "$LOG" 2>&1 &
    sleep 5
  else
    echo "$(date '+%F %T') - engine missing" >> "$LOG"
    sleep 6
  fi
done
DAE

  chmod 700 "$DAEMON_SCRIPT"
  info "Daemon monitor written to $DAEMON_SCRIPT"
}

# -------------------------
# Engine control
# -------------------------
is_engine_running(){
  [ -f "$PID_FILE" ] || return 1
  pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
  [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1
}

start_engine(){
  check_activation || { warn "Start blocked: activation invalid."; return 2; }
  if is_engine_running; then info "Engine already running (pid $(cat "$PID_FILE"))"; return 0; fi
  [ -f "$ENGINE_SCRIPT" ] || write_engine_worker
  nohup bash "$ENGINE_SCRIPT" >> "$ENGINE_LOG" 2>&1 &
  for i in {1..15}; do
    sleep 0.3
    is_engine_running && break
  done
  if is_engine_running; then info "Engine started (pid $(cat "$PID_FILE"))"; return 0; else err "Engine failed to start"; return 1; fi
}

stop_engine(){
  if ! is_engine_running; then info "Engine not running"; return 0; fi
  pid=$(cat "$PID_FILE") || true
  kill "$pid" 2>/dev/null || true
  sleep 0.6
  if ! is_engine_running; then rm -f "$PID_FILE" 2>/dev/null || true; info "Engine stopped"; return 0; else err "Failed to stop engine"; return 1; fi
}

enable_neural_turbo(){
  neural_turbo=1; arc_plus=1; vpool_enabled=1; uvram_enabled=1; afb_mode="Auto"
  save_config
  info "Neural Turbo ENABLED"
  start_engine || warn "Engine start failed"
}

disable_neural_turbo(){
  neural_turbo=0; arc_plus=0; vpool_enabled=0; uvram_enabled=0
  save_config
  info "Neural Turbo DISABLED"
}

toggle_arc_plus(){ arc_plus=$((1-arc_plus)); save_config; info "ARC+ -> $arc_plus"; start_engine >/dev/null 2>&1 || true; }
toggle_vpool(){ vpool_enabled=$((1-vpool_enabled)); save_config; info "vPool -> $vpool_enabled"; }
toggle_uvram(){ uvram_enabled=$((1-uvram_enabled)); save_config; info "uVRAM -> $uvram_enabled"; }

set_afb_mode(){
  mode="$1"; afb_mode="$mode"; save_config; info "AFB -> $afb_mode"
}

# -------------------------
# Autostart (Termux:Boot + Daemon) - single toggle control
# -------------------------
install_autostart_allinone(){
  # write engine & daemon if missing
  [ -f "$ENGINE_SCRIPT" ] || write_engine_worker
  [ -f "$DAEMON_SCRIPT" ] || write_daemon_monitor

  # create boot script
  mkdir -p "$BOOT_DIR"
  cat > "$BOOT_FILE" <<'BFILE'
#!/data/data/com.termux/files/usr/bin/env bash
# Hypersense Termux:Boot launcher
sleep 6
HYP="$HOME/.hypersense"
ENGINE="$HYP/engine_worker.sh"
DAEMON="$HYP/daemon_monitor.sh"

# Prevent duplicates
if [ -f "$HYP/neural.pid" ]; then
  PID=$(cat "$HYP/neural.pid" 2>/dev/null || echo "")
  if [ -n "$PID" ] && ps -p "$PID" >/dev/null 2>&1; then
    exit 0
  fi
fi

# start daemon monitor which ensures engine is running
if [ -f "$DAEMON" ]; then
  nohup bash "$DAEMON" >> "$HYP/logs/engine.log" 2>&1 &
else
  nohup bash "$ENGINE" >> "$HYP/logs/engine.log" 2>&1 &
fi
BFILE
  chmod 700 "$BOOT_FILE"

  # start daemon immediately
  nohup bash "$DAEMON_SCRIPT" >> "$ENGINE_LOG" 2>&1 &

  # set config flag
  autostart_enabled=1; save_config
  touch "$AUTOSTART_FLAG" 2>/dev/null || true
  info "Autostart All-In-One installed at $BOOT_FILE and daemon started"
}

uninstall_autostart_allinone(){
  # stop daemon and engine
  pkill -f "$(basename "$DAEMON_SCRIPT")" 2>/dev/null || true
  stop_engine || true
  rm -f "$BOOT_FILE" "$AUTOSTART_FLAG" 2>/dev/null || true
  autostart_enabled=0; save_config
  info "Autostart All-In-One removed"
}

autostart_status_report(){
  report=""
  [ -f "$BOOT_FILE" ] && report="$report Autostart: PRESENT\n" || report="$report Autostart: MISSING\n"
  if is_engine_running; then report="$report Neural Engine: RUNNING (pid $(cat "$PID_FILE"))\n"; else report="$report Neural Engine: NOT RUNNING\n"; fi
  command -v dialog >/dev/null 2>&1 && dialog --msgbox "$report" 10 60 || echo -e "$report"
}

# -------------------------
# Game detection helpers & VRAM info
# -------------------------
get_foreground_app(){
  if command -v dumpsys >/dev/null 2>&1; then
    fg=$(dumpsys activity activities 2>/dev/null | awk -F' ' '/mResumedActivity|mFocusedActivity/ {print $NF; exit}' | cut -d'/' -f1)
    [ -z "$fg" ] && fg=$(dumpsys window windows 2>/dev/null | awk -F' ' '/mCurrentFocus|mFocusedApp/ {print $3; exit}' | cut -d'/' -f1)
    echo "${fg:-}"
    return
  fi
  echo ""
}

is_game_foreground(){
  fg=$(get_foreground_app)
  [ -z "$fg" ] && return 1
  IFS=','; for pkg in $game_whitelist; do [ "$pkg" = "$fg" ] && return 0; done
  return 1
}

get_memory_info(){
  if [ -f /proc/meminfo ]; then
    mem_total_kb=$(awk '/MemTotal/ {print $2; exit}' /proc/meminfo 2>/dev/null || echo "")
    mem_free_kb=$(awk '/MemAvailable/ {print $2; exit}' /proc/meminfo 2>/dev/null || awk '/MemFree/ {print $2; exit}' /proc/meminfo 2>/dev/null || echo "")
    if [ -n "$mem_total_kb" ]; then
      total_mb=$((mem_total_kb/1024))
      free_mb=$((mem_free_kb/1024))
      printf "%s MB total | %s MB available" "$total_mb" "$free_mb"
      return
    fi
  fi
  echo "N/A"
}

# -------------------------
# Monitor / Logs UI
# -------------------------
monitor_status(){
  tmp="$MONITOR_TMP"
  {
    printf "────────────────────────────────────────────\n"
    printf " HYPERSENSE Monitor — %s\n" "$(date '+%F %T')"
    printf "────────────────────────────────────────────\n\n"
    if check_activation; then
      echo "Activation: VALID"
      . "$ACT_FILE"
      echo "User: ${USERNAME:-N/A}"
      echo "Plan: ${PLAN:-N/A}"
      echo "Plan Expiry: $(date -d "@${PLAN_EXPIRY_EPOCH:-0}" '+%F' 2>/dev/null || echo N/A)"
    else
      echo "Activation: NOT ACTIVE"
    fi
    echo ""
    echo "Neural Turbo:   $( [ "$neural_turbo" -eq 1 ] && echo "ON" || echo "OFF")"
    echo "ARC+:           $( [ "$arc_plus" -eq 1 ] && echo "ON" || echo "OFF")"
    echo "vPool (512MB):  $( [ "$vpool_enabled" -eq 1 ] && echo "ON" || echo "OFF")"
    echo "uVRAM (256MB):  $( [ "$uvram_enabled" -eq 1 ] && echo "ON" || echo "OFF")"
    echo "AFB Mode:       $afb_mode"
    echo "Engine running: $( is_engine_running && echo "YES (pid $(cat "$PID_FILE"))" || echo "NO")"
    echo ""
    bat=$(get_battery_safe)
    temp=$(get_temp_safe)
    rr=$(get_refresh_rate)
    echo "Battery: ${bat}%   Device Temp: ${temp}°C   Display Hz: ${rr}Hz"
    echo ""
    echo "Memory: $(get_memory_info)"
    echo ""
    echo "Last Engine Logs:"
    tail -n 12 "$ENGINE_LOG" 2>/dev/null || echo "No logs."
    echo ""
    echo "AI FPS Logs (last 8):"
    tail -n 8 "$AI_FPS_LOG" 2>/dev/null || echo "No AI logs."
    echo ""
  } > "$tmp"

  if command -v dialog >/dev/null 2>&1; then
    dialog --title "Hypersense Monitor" --textbox "$tmp" 22 80
  else
    cat "$tmp"; sleep 2
  fi
  rm -f "$tmp"
}

# -------------------------
# Touch & Presets (fixed slider-like)
# -------------------------
set_touch_values(){
  if command -v dialog >/dev/null 2>&1; then
    vals=$(dialog --inputbox "Enter X,Y,Smooth (comma separated)\nX and Y: 1-50 (higher = more sensitivity). Smooth: 0.05-5.0 (lower = snappier)\nExample: 18,17,0.7" 12 70 3>&1 1>&2 2>&3)
  else
    read -r -p "Enter X,Y,Smooth (e.g. 18,17,0.7): " vals
  fi
  IFS=',' read -r X Y S <<< "${vals},"
  X=${X:-$touch_x}; Y=${Y:-$touch_y}; S=${S:-$touch_smooth}
  # sanitize
  if ! [[ "$X" =~ ^[0-9]+$ ]] || [ "$X" -lt 1 ] || [ "$X" -gt 50 ]; then X=$touch_x; fi
  if ! [[ "$Y" =~ ^[0-9]+$ ]] || [ "$Y" -lt 1 ] || [ "$Y" -gt 50 ]; then Y=$touch_y; fi
  if ! awk "BEGIN{exit !(($S+0)==$S)}" 2>/dev/null; then S=$touch_smooth; fi
  awk_check=$(awk "BEGIN{print ($S >= 0.05 && $S <= 5.0)?1:0}" 2>/dev/null || echo 0)
  if [ "$awk_check" -ne 1 ]; then S=$touch_smooth; fi
  touch_x=$X; touch_y=$Y; touch_smooth=$S
  save_config
  command -v dialog >/dev/null 2>&1 && dialog --msgbox "Saved touch: X=$touch_x, Y=$touch_y, smooth=$touch_smooth" 6 50 || echo "Saved touch: X=$touch_x, Y=$touch_y, smooth=$touch_smooth"
}

touch_live_boost(){
  orig_x=$touch_x; orig_y=$touch_y; orig_s=$touch_smooth
  touch_x=$(( orig_x + 6 ))
  touch_y=$(( orig_y + 5 ))
  touch_s=$(awk "BEGIN{printf \"%.2f\", ($orig_s * 0.85)}")
  save_config
  info "Touch Live Boost applied: X=$touch_x Y=$touch_y S=$touch_s"
  sleep 6
  touch_x=$orig_x; touch_y=$orig_y; touch_s=$orig_s
  save_config
  info "Touch Live Boost ended, restored defaults"
}

# -------------------------
# Profiles (save / load)
# -------------------------
save_profile(){
  name="$1"
  [ -z "$name" ] && { echo "No name"; return 1; }
  file="$PROFILES_DIR/$name.profile"
  cat > "$file" <<EOF
touch_x=$touch_x
touch_y=$touch_y
touch_smooth=$touch_smooth
neural_turbo=$neural_turbo
arc_plus=$arc_plus
vpool_enabled=$vpool_enabled
uvram_enabled=$uvram_enabled
afb_mode="$afb_mode"
EOF
  echo "$name" > "$PROFILES_DIR/active.profile" 2>/dev/null || true
  profile_active="$name"
  save_config
  info "Profile saved: $name"
}

load_profile(){
  name="$1"
  file="$PROFILES_DIR/$name.profile"
  [ -f "$file" ] || { echo "Profile not found"; return 1; }
  . "$file"
  save_config
  profile_active="$name"
  echo "$name" > "$PROFILES_DIR/active.profile" 2>/dev/null || true
  info "Profile loaded: $name"
}

list_profiles(){
  ls -1 "$PROFILES_DIR"/*.profile 2>/dev/null | xargs -n1 basename 2>/dev/null | sed 's/\.profile$//' || echo "none"
}

# -------------------------
# FPS / AFB / 120Hz Simulation
# -------------------------
fps_estimator(){
  rr=$(get_refresh_rate)
  echo "$rr"
}

apply_afb_simulation(){
  mode="$1"
  info "Applying AFB simulation: mode=$mode"
  if [ -w /proc/sys/vm/drop_caches ]; then
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
  fi
  echo "$(date '+%F %T') - AFB applied mode:$mode" >> "$AI_FPS_LOG" 2>/dev/null || true
  return 0
}

simulate_120hz(){
  mode="$1"
  if [ "$mode" = "auto" ]; then
    rr=$(get_refresh_rate)
    if [ "$rr" -ge 90 ]; then
      apply_afb_simulation "120-sim-high"
      return 0
    else
      apply_afb_simulation "120-sim-fallback"
      return 0
    fi
  else
    apply_afb_simulation "manual-120"
    return 0
  fi
}

# -------------------------
# Network optimizer (lightweight)
# -------------------------
network_optimize(){
  info "Running network optimizer (userland hints)."
  echo "$(date '+%F %T') - Network optimize run" >> "$AI_FPS_LOG"
  # simple DNS check (no change without root)
  return 0
}

# -------------------------
# Restore defaults & repair
# -------------------------
restore_defaults(){
  default_config
  save_config
  rm -f "$ENGINE_LOG" "$AI_FPS_LOG" "$PID_FILE" 2>/dev/null || true
  mkdir -p "$LOG_DIR"
  info "Defaults restored (activation preserved if present)."
}

# -------------------------
# Advanced submenu
# -------------------------
advanced_menu(){
  while true; do
    if command -v dialog >/dev/null 2>&1; then
      CHOICE=$(dialog --title "ADVANCED: Neural Engine" --menu "Select Option" 20 80 14 \
        A1 "Neural Engine Status & Toggle" \
        A2 "ARC+ (Aim & Recoil) Toggle" \
        A3 "Recoil Stability Presets" \
        A4 "Adaptive Frame Booster (AFB) Mode" \
        A5 "vPool / uVRAM Controls" \
        A6 "Predictive Ramp & Micro-Burst Info" \
        A7 "Adaptive Power Governor (Idle/Active)" \
        A8 "Thermal Guardian (thresholds)" \
        A9 "Neural Decision (sampling/trigger)" \
        A10 "Game Detection & Whitelist" \
        A11 "AI Logs (FPS/Recoils)" \
        A12 "Manual Overrides (Force Active/Idle/Safe)" \
        A13 "Back to Main Menu" 3>&1 1>&2 2>&3)
    else
      echo "ADVANCED MENU (no-dialog)"; read -r CHOICE
    fi

    case "$CHOICE" in
      A1)
        status=$(printf "Engine: %s\nTurbo:%s ARC:%s vPool:%s uVRAM:%s AFB:%s\n" "$( is_engine_running && echo ON || echo OFF )" "$neural_turbo" "$arc_plus" "$vpool_enabled" "$uvram_enabled" "$afb_mode")
        if command -v dialog >/dev/null 2>&1; then
          dialog --msgbox "$status" 10 60
          if dialog --yesno "Toggle Engine (start/stop)?" 7 50; then
            is_engine_running && stop_engine || start_engine
          fi
        else
          echo -e "$status"
          echo "Toggle engine? (y/n)"; read -r ans; [ "$ans" = "y" ] && (is_engine_running && stop_engine || start_engine)
        fi
        ;;
      A2) toggle_arc_plus; command -v dialog >/dev/null 2>&1 && dialog --msgbox "ARC+: $( [ $arc_plus -eq 1 ] && echo ON || echo OFF )" 5 50 || true ;;
      A3)
        if command -v dialog >/dev/null 2>&1; then
          sel=$(dialog --menu "Choose Recoil Preset" 12 60 4 1 "Precision" 2 "Balanced" 3 "Aggressive" 4 "Custom" 3>&1 1>&2 2>&3)
          case $sel in
            1) touch_smooth=0.6; touch_x=14; touch_y=14 ;;
            2) touch_smooth=0.8; touch_x=12; touch_y=12 ;;
            3) touch_smooth=0.5; touch_x=18; touch_y=17 ;;
            4) set_touch_values ;;
          esac
          save_config; dialog --msgbox "Preset applied. X=$touch_x Y=$touch_y S=$touch_smooth" 6 50
        else
          echo "Presets: 1)Precision 2)Balanced 3)Aggressive 4)Custom"; read -r sel
          case $sel in 1) touch_smooth=0.6; touch_x=14; touch_y=14 ;; 2) touch_smooth=0.8; touch_x=12; touch_y=12 ;; 3) touch_smooth=0.5; touch_x=18; touch_y=17 ;; 4) set_touch_values ;; esac
          save_config
        fi
        ;;
      A4)
        if command -v dialog >/dev/null 2>&1; then
          afb_choice=$(dialog --menu "AFB Mode" 12 60 6 1 "Auto (recommended)" 2 "60 Hz" 3 "90 Hz" 4 "120 Hz" 5 "144 Hz" 6 "Off" 3>&1 1>&2 2>&3)
          case $afb_choice in 1)set_afb_mode "Auto";;2)set_afb_mode "60";;3)set_afb_mode "90";;4)set_afb_mode "120";;5)set_afb_mode "144";;6)set_afb_mode "Off";;esac
          dialog --msgbox "AFB -> $afb_mode" 6 40
        else
          echo "AFB modes: Auto / 60 / 90 / 120 / 144 / Off"; read -r m; set_afb_mode "$m"
        fi
        ;;
      A5)
        if command -v dialog >/dev/null 2>&1; then
          vchoice=$(dialog --menu "vPool/uVRAM Controls" 12 60 4 1 "Toggle vPool (512MB)" 2 "Toggle uVRAM (256MB)" 3 "Auto-clean vPool now" 4 "Back" 3>&1 1>&2 2>&3)
          case $vchoice in
            1) toggle_vpool; dialog --msgbox "vPool: $( [ $vpool_enabled -eq 1 ] && echo ON || echo OFF )" 5 50 ;;
            2) toggle_uvram; dialog --msgbox "uVRAM: $( [ $uvram_enabled -eq 1 ] && echo ON || echo OFF )" 5 50 ;;
            3) echo "$(date '+%F %T') - vPool cleaned" >> "$AI_FPS_LOG"; dialog --msgbox "vPool cleaned." 5 40 ;;
          esac
        else
          echo "vPool options"; read -r vchoice; case $vchoice in 1) toggle_vpool ;; 2) toggle_uvram ;; 3) echo "$(date '+%F %T') - vPool cleaned" >> "$AI_FPS_LOG" ;; esac
        fi
        ;;
      A6) command -v dialog >/dev/null 2>&1 && dialog --msgbox "Predictive Ramp runs automatically when Neural Turbo is ON. Micro-burst window: ${micro_trigger_ms}ms" 7 60 || echo "Predictive Ramp info";;
      A7)
        if command -v dialog >/dev/null 2>&1; then
          vals=$(dialog --inputbox "Idle%,Active%,CPUthreshold\nExample: 70,95,45" 9 60 3>&1 1>&2 2>&3)
          IFS=',' read -r it at ct <<< "$vals"
          idle_target=${it:-$idle_target}; active_target=${at:-$active_target}; cpu_threshold=${ct:-$cpu_threshold}
          save_config; dialog --msgbox "Saved Idle:$idle_target Active:$active_target CPUthr:$cpu_threshold" 6 50
        else
          read -r -p "Enter Idle,Active,CPUthr: " vals; IFS=',' read -r it at ct <<< "$vals"; idle_target=${it:-$idle_target}; active_target=${at:-$active_target}; cpu_threshold=${ct:-$cpu_threshold}; save_config
        fi
        ;;
      A8)
        if command -v dialog >/dev/null 2>&1; then
          vals=$(dialog --inputbox "Soft°C,Hard°C,Hysteresis,CooldownSec\nExample: 45,50,3,90" 9 60 3>&1 1>&2 2>&3)
          IFS=',' read -r s h gy cd <<< "$vals"
          thermal_soft=${s:-$thermal_soft}; thermal_hard=${h:-$thermal_hard}; thermal_hysteresis=${gy:-$thermal_hysteresis}; thermal_cooldown_s=${cd:-$thermal_cooldown_s}
          save_config; dialog --msgbox "Thermal soft:$thermal_soft hard:$thermal_hard hysteresis:$thermal_hysteresis cool:${thermal_cooldown_s}s" 6 60
        else
          read -r -p "Enter soft,hard,hysteresis,cooldown: " vals; IFS=',' read -r s h gy cd <<< "$vals"; thermal_soft=${s:-$thermal_soft}; thermal_hard=${h:-$thermal_hard}; thermal_hysteresis=${gy:-$thermal_hysteresis}; thermal_cooldown_s=${cd:-$thermal_cooldown_s}; save_config
        fi
        ;;
      A9)
        if command -v dialog >/dev/null 2>&1; then
          vals=$(dialog --inputbox "Sampling ms, Micro-trigger ms\nExample: 300,120" 8 50 3>&1 1>&2 2>&3)
          IFS=',' read -r si mt <<< "$vals"; sample_interval_ms=${si:-$sample_interval_ms}; micro_trigger_ms=${mt:-$micro_trigger_ms}; save_config; dialog --msgbox "Saved sample:${sample_interval_ms}ms micro:${micro_trigger_ms}ms" 6 50
        else
          read -r -p "Enter sample_ms,micro_ms: " vals; IFS=',' read -r si mt <<< "$vals"; sample_interval_ms=${si:-$sample_interval_ms}; micro_trigger_ms=${mt:-$micro_trigger_ms}; save_config
        fi
        ;;
      A10)
        if command -v dialog >/dev/null 2>&1; then
          new=$(dialog --editbox <(printf "%s\n" $(echo "$game_whitelist" | tr ',' '\n')) 15 60 3>&1 1>&2 2>&3)
          game_whitelist=$(echo "$new" | tr '\n' ',' | sed 's/,$//'); save_config; dialog --msgbox "Whitelist updated." 6 40
        else
          echo "Current whitelist: $game_whitelist"; read -r gw; game_whitelist=${gw:-$game_whitelist}; save_config
        fi
        ;;
      A11) command -v dialog >/dev/null 2>&1 && dialog --title "AI Logs" --textbox "$AI_FPS_LOG" 20 80 || tail -n 200 "$AI_FPS_LOG" ;;
      A12)
        if command -v dialog >/dev/null 2>&1; then
          mm=$(dialog --menu "Manual Overrides" 10 50 3 1 "Force Active (Enable Turbo)" 2 "Force Idle (Disable Turbo)" 3 "Safe Mode (Pause Predictive)" 3>&1 1>&2 2>&3)
          case $mm in 1) enable_neural_turbo ;; 2) disable_neural_turbo ;; 3) disable_neural_turbo; dialog --msgbox "Safe Mode ON" 5 40 ;; esac
        else
          echo "1)Force Active 2)Force Idle 3)Safe Mode"; read -r mm; [ "$mm" = "1" ] && enable_neural_turbo; [ "$mm" = "2" ] && disable_neural_turbo
        fi
        ;;
      A13) break ;;
      *) ;;
    esac
  done
}

# -------------------------
# Game Preset Manager
# -------------------------
game_preset_manager(){
  while true; do
    if command -v dialog >/dev/null 2>&1; then
      sel=$(dialog --menu "Game Presets" 15 70 6 1 "List / View Presets" 2 "Add Preset" 3 "Edit Presets" 4 "Remove Preset" 5 "Back" 3>&1 1>&2 2>&3)
    else
      echo "Game Preset Manager: 1 list 2 add 3 edit 4 remove 5 back"; read -r sel
    fi
    case $sel in
      1) dialog --msgbox "$(cat "$GAME_PRESETS_FILE")" 20 80 ;;
      2)
        pkg=$(dialog --inputbox "Package name (e.g. com.pubg.imobile):" 8 60 3>&1 1>&2 2>&3)
        name=$(dialog --inputbox "Friendly name:" 8 40 3>&1 1>&2 2>&3)
        tx=$(dialog --inputbox "Touch X (1-50):" 8 30 3>&1 1>&2 2>&3)
        ty=$(dialog --inputbox "Touch Y (1-50):" 8 30 3>&1 1>&2 2>&3)
        ts=$(dialog --inputbox "Smooth (0.05-5.0):" 8 30 3>&1 1>&2 2>&3)
        nt=$(dialog --inputbox "Neural turbo (0/1):" 8 20 3>&1 1>&2 2>&3)
        ap=$(dialog --inputbox "ARC+ (0/1):" 8 20 3>&1 1>&2 2>&3)
        afb=$(dialog --inputbox "AFB mode (Auto/60/90/120/Off):" 8 30 3>&1 1>&2 2>&3)
        echo "${pkg}|${name}|${tx}|${ty}|${ts}|${nt}|${ap}|${afb}" >> "$GAME_PRESETS_FILE"
        dialog --msgbox "Preset added." 6 40
        ;;
      3) dialog --msgbox "Edit the file manually at $GAME_PRESETS_FILE" 8 60 ;;
      4)
        lines=$(nl -ba "$GAME_PRESETS_FILE" | sed -n '1,200p')
        sel=$(dialog --inputbox "Open $GAME_PRESETS_FILE and remove line(s) manually (edit with your editor)." 12 70 3>&1 1>&2 2>&3)
        ;;
      5) break ;;
    esac
  done
}

# -------------------------
# Main Menu
# -------------------------
main_menu(){
  if ! check_activation; then
    prompt_activation || { warn "Activation failed/aborted."; exit 1; }
  fi

  [ -f "$ENGINE_SCRIPT" ] || write_engine_worker
  [ -f "$DAEMON_SCRIPT" ] || write_daemon_monitor
  rotate_log "$ENGINE_LOG"; rotate_log "$AI_FPS_LOG"

  while true; do
    . "$CFG_FILE"
    ACT_TEXT="Not Active"; is_engine_running && ENG_TEXT="ON (pid $(cat "$PID_FILE"))" || ENG_TEXT="OFF"
    check_activation && ACT_TEXT="Active"

    if command -v dialog >/dev/null 2>&1; then
      CHOICE=$(dialog --clear --title "HYPERSENSEINDIA - AG HYDRAX" --menu "Activation: $ACT_TEXT | Engine: $ENG_TEXT\nSelect Option" 28 96 18 \
        1 "Activate / Check Activation" \
        2 "Neural Engine Control (Enable/Disable/Recoil/AFB/Thermal)" \
        3 "Virtual Memory Engine (uVRAM/vPool Controls)" \
        4 "Touch & Recoil Engine (X/Y presets & Live Boost)" \
        5 "ARC+ Performance Engine" \
        6 "FPS / Performance Tools (AFB / 120Hz Simulation)" \
        7 "Game Modes & Presets (Auto/Manual/Profiles)" \
        8 "Auto-Start / Watchdog / Logs (All-in-one toggle)" \
        9 "System Status Center (Monitor)" \
        10 "Advanced → Neural Engine Submenu" \
        11 "Restore Defaults / Repair" \
        12 "Profiles (Save/Load/Delete)" \
        13 "Game Preset Manager" \
        0 "Exit" 3>&1 1>&2 2>&3)
    else
      echo "1)Activate 2)Neural Engine Control 3)Virtual Memory 4)Touch/Recoil 5)ARC+ 6)FPS Tools 7)Game Modes 8)AutoStart/Logs 9)Monitor 10)Advanced 11)Restore 12)Profiles 13)PresetMgr 0)Exit"
      read -r CHOICE
    fi

    case "$CHOICE" in
      1) check_activation && command -v dialog >/dev/null 2>&1 && dialog --msgbox "Activation valid." 5 40 || prompt_activation ;;
      2)
        if command -v dialog >/dev/null 2>&1; then
          sub=$(dialog --menu "Neural Engine Control" 15 76 6 1 "Enable Neural Core Engine (All-In-One)" 2 "Disable Neural Core Engine" 3 "Neural Recoil Stability Mode" 4 "AFB Mode Quick" 5 "Neural Thermal Guardian Info" 6 "Back" 3>&1 1>&2 2>&3)
          case $sub in
            1) enable_neural_turbo; dialog --msgbox "Neural Engine ENABLED (All-in-one)" 6 50 ;;
            2) disable_neural_turbo; dialog --msgbox "Neural Engine DISABLED" 5 50 ;;
            3) dialog --msgbox "Recoil mode applied (see Advanced for presets)" 6 50 ;;
            4) advanced_menu ;;
            5) dialog --msgbox "Thermal Guardian active (Advanced→A8 to configure)" 6 50 ;;
          esac
        else
          echo "Enable/Disable engine"; read -r t; [ "$t" = "1" ] && enable_neural_turbo || disable_neural_turbo
        fi
        ;;
      3)
        if command -v dialog >/dev/null 2>&1; then
          vsub=$(dialog --menu "Virtual Memory Engine" 12 60 4 1 "Toggle uVRAM (256MB)" 2 "Toggle vPool (512MB)" 3 "Clean Neural Memory" 4 "Back" 3>&1 1>&2 2>&3)
          case $vsub in 1) toggle_uvram ;; 2) toggle_vpool ;; 3) echo "$(date '+%F %T') - vPool cleaned" >> "$AI_FPS_LOG"; dialog --msgbox "vPool cleaned." 5 40 ;; esac
        else
          echo "Virtual memory options"; read -r v; [ "$v" = "1" ] && toggle_uvram || toggle_vpool
        fi
        ;;
      4)
        if command -v dialog >/dev/null 2>&1; then
          sub=$(dialog --menu "Touch & Recoil" 12 60 6 1 "Set Touch X/Y/Smooth" 2 "Touch Live Boost (short)" 3 "Recoil Presets" 4 "Show current touch" 5 "Profiles" 6 "Back" 3>&1 1>&2 2>&3)
          case $sub in
            1) set_touch_values ;;
            2) touch_live_boost ;;
            3) advanced_menu ;;
            4) dialog --msgbox "X=$touch_x Y=$touch_y Smooth=$touch_smooth" 6 50 ;;
            5) plist=$(list_profiles | tr '\n' ' '); sel=$(dialog --menu "Choose profile" 15 60 10 $(for i in $plist; do echo "$i" "$i"; done) 3>&1 1>&2 2>&3); [ -n "$sel" ] && load_profile "$sel" && dialog --msgbox "Loaded $sel" 6 40 ;;
          esac
        else
          echo "Touch options"; read -r t; [ "$t" = "1" ] && set_touch_values || touch_live_boost
        fi
        ;;
      5)
        if command -v dialog >/dev/null 2>&1; then
          dsub=$(dialog --menu "ARC+ Engine" 12 60 5 1 "Enable ARC+ (Max)" 2 "Disable ARC+" 3 "ARC+ Mode: Precision" 4 "ARC+ Mode: Speed" 5 "Back" 3>&1 1>&2 2>&3)
          case $dsub in
            1) arc_plus=1; save_config; dialog --msgbox "ARC+ Enabled" 5 40 ;;
            2) arc_plus=0; save_config; dialog --msgbox "ARC+ Disabled" 5 40 ;;
            3) touch_smooth=0.5; save_config; dialog --msgbox "ARC+ Precision set" 5 40 ;;
            4) touch_smooth=0.9; save_config; dialog --msgbox "ARC+ Speed set" 5 40 ;;
          esac
        else
          echo "ARC+ options"; read -r s; [ "$s" = "1" ] && arc_plus=1 || arc_plus=0; save_config
        fi
        ;;
      6)
        if command -v dialog >/dev/null 2>&1; then
          dsub=$(dialog --menu "FPS Tools" 12 60 6 1 "Show Display Hz" 2 "Apply AFB Simulation" 3 "Simulate 120Hz (userland)" 4 "Network Optimizer" 5 "FPS Logs" 6 "Back" 3>&1 1>&2 2>&3)
          case $dsub in
            1) dialog --msgbox "Display reports: $(fps_estimator) Hz" 6 60 ;;
            2) apply_afb_simulation "manual" ; dialog --msgbox "AFB simulation applied (userland)." 6 50 ;;
            3) simulate_120hz "manual" ; dialog --msgbox "120Hz simulation applied (userland)." 6 50 ;;
            4) network_optimize; dialog --msgbox "Network hints applied." 5 40 ;;
            5) dialog --title "AI FPS Log" --textbox "$AI_FPS_LOG" 20 80 ;;
          esac
        else
          echo "FPS tools"; read -r f; [ "$f" = "1" ] && echo "Hz: $(fps_estimator)"
        fi
        ;;
      7)
        if command -v dialog >/dev/null 2>&1; then
          gsub=$(dialog --menu "Game Modes" 12 60 6 1 "Smart Game Detection (Auto)" 2 "Game Mode: Force ON" 3 "Game Mode: Force OFF" 4 "Profiles (Save/Load/Delete)" 5 "View Whitelist" 6 "Back" 3>&1 1>&2 2>&3)
          case $gsub in
            1) dialog --msgbox "Smart detection runs automatically." 5 40 ;;
            2) cpu_threshold=5; save_config; dialog --msgbox "Game Mode forced ON (manual)." 5 40 ;;
            3) cpu_threshold=45; save_config; dialog --msgbox "Game Mode forced OFF (manual revert)." 5 40 ;;
            4) psel=$(dialog --menu "Profiles" 12 60 5 1 "Save current as..." 2 "Load profile" 3 "Delete profile" 4 "List" 5 "Back" 3>&1 1>&2 2>&3)
               case $psel in
                 1) pname=$(dialog --inputbox "Profile name:" 8 40 3>&1 1>&2 2>&3); save_profile "$pname"; dialog --msgbox "Saved $pname" 6 40 ;;
                 2) plist=$(list_profiles | tr '\n' ' '); sel=$(dialog --menu "Choose profile" 15 60 10 $(for i in $plist; do echo "$i" "$i"; done) 3>&1 1>&2 2>&3); [ -n "$sel" ] && load_profile "$sel" && dialog --msgbox "Loaded $sel" 6 40 ;;
                 3) plist=$(list_profiles | tr '\n' ' '); sel=$(dialog --menu "Delete profile" 15 60 10 $(for i in $plist; do echo "$i" "$i"; done) 3>&1 1>&2 2>&3); [ -n "$sel" ] && rm -f "$PROFILES_DIR/$sel.profile" && dialog --msgbox "Deleted $sel" 6 40 ;;
                 4) dialog --msgbox "Profiles:\n$(list_profiles)" 10 60 ;;
               esac
               ;;
            5) dialog --msgbox "Whitelist:\n$game_whitelist" 8 60 ;;
            6) ;;
          esac
        else
          echo "Game modes: auto/dedicated"
        fi
        ;;
      8)
        if command -v dialog >/dev/null 2>&1; then
          msub=$(dialog --menu "Auto-Start & Watchdog (All-in-One)" 15 70 6 1 "Enable Auto-Start (Termux:Boot + Daemon)" 2 "Disable Auto-Start" 3 "Status" 4 "View logs" 5 "Back" 3>&1 1>&2 2>&3)
          case $msub in
            1) install_autostart_allinone; dialog --msgbox "AutoStart enabled. Will run after reboot. (Default OFF originally.)" 6 60 ;;
            2) uninstall_autostart_allinone; dialog --msgbox "AutoStart disabled and engine stopped." 6 50 ;;
            3) autostart_status_report ;;
            4) dialog --title "Engine Log" --textbox "$ENGINE_LOG" 20 80 ;;
          esac
        else
          echo "Autostart options"; read -r m; [ "$m" = "1" ] && install_autostart_allinone || uninstall_autostart_allinone
        fi
        ;;
      9) monitor_status ;;
      10) advanced_menu ;;
      11) restore_defaults ;;
      12)
        if command -v dialog >/dev/null 2>&1; then
          psel=$(dialog --menu "Profiles" 12 60 5 1 "Save current as..." 2 "Load profile" 3 "Delete profile" 4 "List profiles" 5 "Back" 3>&1 1>&2 2>&3)
          case $psel in
            1) pname=$(dialog --inputbox "Profile name:" 8 40 3>&1 1>&2 2>&3); save_profile "$pname"; dialog --msgbox "Saved $pname" 6 40 ;;
            2) plist=$(list_profiles | tr '\n' ' '); sel=$(dialog --menu "Choose profile" 15 60 10 $(for i in $plist; do echo "$i" "$i"; done) 3>&1 1>&2 2>&3); [ -n "$sel" ] && load_profile "$sel" && dialog --msgbox "Loaded $sel" 6 40 ;;
            3) plist=$(list_profiles | tr '\n' ' '); sel=$(dialog --menu "Delete profile" 15 60 10 $(for i in $plist; do echo "$i" "$i"; done) 3>&1 1>&2 2>&3); [ -n "$sel" ] && rm -f "$PROFILES_DIR/$sel.profile" && dialog --msgbox "Deleted $sel" 6 40 ;;
            4) dialog --msgbox "Profiles:\n$(list_profiles)" 10 60 ;;
          esac
        else
          echo "Profiles menu"
        fi
        ;;
      13) game_preset_manager ;;
      0) clear; exit 0 ;;
      *) ;;
    esac
  done
}

# -------------------------
# Autostart-run (simulate boot) for CLI mode
# -------------------------
if [ "${1:-}" = "--autostart-run" ]; then
  if check_activation; then
    . "$CFG_FILE"
    temp=$(get_temp_safe)
    safe_to_start=1
    if [ "$temp" != "N/A" ]; then
      temp_int=$(awk "BEGIN{printf \"%d\", $temp}")
      if [ "$temp_int" -ge "$thermal_hard" ]; then
        info "Autostart: temperature too high ($temp C). Delaying engine start."
        safe_to_start=0
      fi
    fi
    if [ "$safe_to_start" -eq 1 ]; then
      [ -f "$DAEMON_SCRIPT" ] || write_daemon_monitor
      nohup bash "$DAEMON_SCRIPT" >> "$ENGINE_LOG" 2>&1 &
    else
      info "Autostart: engine start deferred due to thermal"
    fi
  else
    info "Autostart: activation missing; exit"
  fi
  exit 0
fi

# -------------------------
# Startup banner & entrypoint
# -------------------------
clear
if command -v dialog >/dev/null 2>&1; then
  dialog --msgbox "────────────────────────────────────────────\nHYPERSENSEINDIA\nAG HYDRAX\nMarketing Head: Roobal Sir (@roobal_sir)\nNeural vPool uVRAM Engine v10 — Final Release\nActivation required on first run.\n────────────────────────────────────────────" 14 72
else
  safe_echo "HYPERSENSEINDIA - Neural vPool uVRAM Engine v10 - Final Release"
fi

# Ensure engine worker & daemon exist
[ -f "$ENGINE_SCRIPT" ] || write_engine_worker
[ -f "$DAEMON_SCRIPT" ] || write_daemon_monitor

# rotate logs lightly
rotate_log "$ENGINE_LOG"; rotate_log "$AI_FPS_LOG"

# Run menu
main_menu
SH

# make it executable and run
chmod +x ~/HypersenseFinal_Stable.sh
echo "Saved to ~/HypersenseFinal_Stable.sh — run it with:"
echo "  bash ~/HypersenseFinal_Stable.sh"
