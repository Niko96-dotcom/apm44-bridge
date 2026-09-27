# Shared stop helper for the running APM44 Bridge app and bridge daemon.
# Sourced by scripts/uninstall-apm44.sh and inlined into the generated
# preinstall by scripts/build-release-pkg.sh. Arguments, if any, prefix the
# commands that need root: the uninstaller passes sudo, the preinstall nothing.
apm44_stop_app_and_helper() {
  local _apm44_as_root=("$@")
  local _apm44_console_user=""
  local _apm44_console_uid=""
  local _apm44_app_pattern=""
  local _apm44_helper_pattern=""
  local _apm44_i=""
  # Ask the existing app to quit, then terminate only helpers launched from the
  # installed app bundle. This avoids replacing a running old process image.
  _apm44_console_user="$(stat -f%Su /dev/console 2>/dev/null || true)"
  _apm44_console_uid="$(stat -f%u /dev/console 2>/dev/null || true)"
  if [[ -n "$_apm44_console_user" && "$_apm44_console_user" != "root" && "$_apm44_console_uid" =~ ^[0-9]+$ ]]; then
    ${_apm44_as_root[@]+"${_apm44_as_root[@]}"} launchctl asuser "$_apm44_console_uid" sudo -u "$_apm44_console_user" \
      osascript -e 'tell application id "com.niko.apm44.menu" to quit' 2>/dev/null || true
  fi
  _apm44_app_pattern='^/Applications/APM44 Bridge.app/Contents/MacOS/APM44 Bridge([[:space:]]|$)'
  for _apm44_i in {1..20}; do
    pgrep -f "$_apm44_app_pattern" >/dev/null 2>&1 || break
    sleep 0.1
  done
  if pgrep -f "$_apm44_app_pattern" >/dev/null 2>&1; then
    echo "Terminating running APM44 Bridge before replacing the app" >&2
    ${_apm44_as_root[@]+"${_apm44_as_root[@]}"} pkill -TERM -f "$_apm44_app_pattern" 2>/dev/null || true
    sleep 1
  fi
  if pgrep -f "$_apm44_app_pattern" >/dev/null 2>&1; then
    ${_apm44_as_root[@]+"${_apm44_as_root[@]}"} pkill -KILL -f "$_apm44_app_pattern" 2>/dev/null || true
  fi
  _apm44_helper_pattern='^/Applications/APM44 Bridge.app/Contents/MacOS/apm44-bridge([[:space:]]|$)'
  for _apm44_i in {1..20}; do
    pgrep -f "$_apm44_helper_pattern" >/dev/null 2>&1 || break
    sleep 0.1
  done
  if pgrep -f "$_apm44_helper_pattern" >/dev/null 2>&1; then
    ${_apm44_as_root[@]+"${_apm44_as_root[@]}"} pkill -TERM -f "$_apm44_helper_pattern" 2>/dev/null || true
    sleep 1
  fi
  if pgrep -f "$_apm44_helper_pattern" >/dev/null 2>&1; then
    ${_apm44_as_root[@]+"${_apm44_as_root[@]}"} pkill -KILL -f "$_apm44_helper_pattern" 2>/dev/null || true
  fi
  return 0
}
