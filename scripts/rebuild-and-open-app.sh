#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-run}"
if [[ "$MODE" == "--isolated" || "$MODE" == "--isolated-stop" ]]; then
  export APM44_APP_DERIVED_DATA="$ROOT/build/isolated-app"
fi
DERIVED_DATA_PATH="${APM44_APP_DERIVED_DATA:-$ROOT/build/app}"
CONFIG="${APM44_BUILD_CONFIG:-Debug}"
APP_NAME="APM44 Bridge"
DAEMON_NAME="apm44-bridge"
APP="$DERIVED_DATA_PATH/Build/Products/$CONFIG/$APP_NAME.app"
EXECUTABLE="$APP/Contents/MacOS/$APP_NAME"

usage() {
  cat >&2 <<USAGE
usage: $0 [run|--no-launch|--verify|--logs|--isolated|--isolated-stop]

Builds $APP_NAME into a deterministic local path, stops any running app/helper,
then opens that exact app bundle. Environment overrides:
  APM44_APP_DERIVED_DATA  DerivedData path (default: build/app)
  APM44_BUILD_CONFIG      Xcode configuration (default: Debug)

--isolated builds a separate local app with its own preferences, disables
automatic updates, and points update requests at loopback. It stops only the
app from this checkout's isolated path. It does NOT isolate audio devices:
use it for UI checks without pressing Start, installing a driver, or enabling
launch at login while real audio work is active.
--isolated-stop stops only that local UI process, without rebuilding.
USAGE
}

case "$MODE" in
  run|--no-launch|--verify|verify|--logs|logs|--isolated|--isolated-stop)
    ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    usage
    exit 2
    ;;
esac

cd "$ROOT"

local_app_pids() {
  ps -axo pid=,comm= | awk -v target="$EXECUTABLE" '
    { pid=$1; sub(/^[[:space:]]*[0-9]+[[:space:]]+/, ""); if ($0 == target) print pid }'
}

if [[ "$MODE" == "--isolated" || "$MODE" == "--isolated-stop" ]]; then
  for pid in $(local_app_pids); do kill -TERM "$pid"; done
  for _ in {1..40}; do
    [[ -z "$(local_app_pids)" ]] && break
    sleep 0.2
  done
  if [[ -n "$(local_app_pids)" ]]; then
    echo "error: isolated app has not stopped; refusing to replace its bundle" >&2
    exit 1
  fi
  [[ "$MODE" == "--isolated-stop" ]] && exit 0

  bash scripts/prepare-submodules.sh
  cmake -S "$ROOT" -B "$ROOT/build/isolated-native" -DCMAKE_BUILD_TYPE=Release
  cmake --build "$ROOT/build/isolated-native" --target apm44-bridge --parallel
fi

echo "== Clean launch bundle =="
rm -rf "$APP"

echo "== Build local app =="
bash scripts/verify-app-build.sh

if [[ "$MODE" == "--isolated" ]]; then
  # Separate bundle identity means UI edits cannot write the installed app's defaults.
  local_id="com.niko.apm44.local.$(printf '%s' "$ROOT" | shasum -a 256 | cut -c1-12)"
  plist="$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $local_id" "$plist"
  /usr/libexec/PlistBuddy -c 'Set :SUEnableAutomaticChecks false' "$plist"
  /usr/libexec/PlistBuddy -c 'Set :SUAutomaticallyUpdate false' "$plist"
  /usr/libexec/PlistBuddy -c 'Set :SUFeedURL http://127.0.0.1:9/appcast.xml' "$plist"
  APM44_APP_PATH="$APP" APM44_DAEMON_PATH="$ROOT/build/isolated-native/BridgeDaemon/apm44-bridge" \
    bash scripts/embed-daemon-in-app.sh
  echo "Isolated preferences: $local_id"
  /usr/bin/open -n "$APP" --args -SUEnableAutomaticChecks NO -SUAutomaticallyUpdate NO
  for _ in {1..40}; do
    pid="$(local_app_pids)"
    if [[ -n "$pid" ]]; then
      echo "Running isolated app: $pid $EXECUTABLE"
      echo "Logs: /usr/bin/log stream --level info --predicate 'processIdentifier == $pid'"
      exit 0
    fi
    sleep 0.2
  done
  echo "error: isolated app did not start: $APP" >&2
  exit 1
fi

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "error: expected executable missing at $EXECUTABLE" >&2
  exit 1
fi

echo "== Launch target =="
echo "App: $APP"
echo "Executable: $EXECUTABLE"
stat -f "Executable mtime: %Sm" "$EXECUTABLE"

if [[ "$MODE" == "--no-launch" ]]; then
  exit 0
fi

echo "== Stop existing processes =="
pkill -TERM -x "$APP_NAME" 2>/dev/null || true
pkill -TERM -x "$DAEMON_NAME" 2>/dev/null || true

for _ in {1..40}; do
  if ! pgrep -x "$APP_NAME" >/dev/null && ! pgrep -x "$DAEMON_NAME" >/dev/null; then
    break
  fi
  sleep 0.2
done

pkill -KILL -x "$APP_NAME" 2>/dev/null || true
pkill -KILL -x "$DAEMON_NAME" 2>/dev/null || true

echo "== Open rebuilt app =="
/usr/bin/open -n "$APP"

for _ in {1..40}; do
  pid="$(pgrep -x "$APP_NAME" | head -1 || true)"
  if [[ -n "$pid" ]]; then
    command="$(ps -p "$pid" -o command=)"
    if [[ "$command" != "$EXECUTABLE"* ]]; then
      echo "error: running $APP_NAME is not the rebuilt executable" >&2
      echo "expected: $EXECUTABLE" >&2
      echo "actual:   $command" >&2
      exit 1
    fi
    echo "Running: $pid $command"
    if [[ "$MODE" == "--logs" || "$MODE" == "logs" ]]; then
      /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    fi
    exit 0
  fi
  sleep 0.2
done

echo "error: $APP_NAME did not appear to start" >&2
exit 1
