#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="${APM44_APP_DERIVED_DATA:-$ROOT/build/app}"
CONFIG="${APM44_BUILD_CONFIG:-Debug}"
APP_NAME="APM44 Bridge"
DAEMON_NAME="apm44-bridge"
APP="$DERIVED_DATA_PATH/Build/Products/$CONFIG/$APP_NAME.app"
EXECUTABLE="$APP/Contents/MacOS/$APP_NAME"
MODE="${1:-run}"

usage() {
  cat >&2 <<USAGE
usage: $0 [run|--no-launch|--verify|--logs]

Builds $APP_NAME into a deterministic local path, stops any running app/helper,
then opens that exact app bundle. Environment overrides:
  APM44_APP_DERIVED_DATA  DerivedData path (default: build/app)
  APM44_BUILD_CONFIG      Xcode configuration (default: Debug)
USAGE
}

case "$MODE" in
  run|--no-launch|--verify|verify|--logs|logs)
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

echo "== Clean launch bundle =="
rm -rf "$APP"

echo "== Build local app =="
bash scripts/verify-app-build.sh

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
