#!/usr/bin/env bash
# Product-UI copy must omit chrome that restates a title, tours a control, or
# fills an optional subtitle/helper slot. English defaults live in AppStrings.swift.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/App/APM44Bridge"
STRINGS="$APP/AppStrings.swift"
MENU="$APP/MenuContentView.swift"
SETUP="$APP/FirstRunPreflightView.swift"
MANAGER="$APP/BridgeProcessManager.swift"
GERMAN="$APP/de.lproj/Localizable.strings"

fail() {
  printf 'test_ui_chrome: %s\n' "$*" >&2
  exit 1
}

[[ -f "$STRINGS" && -f "$MENU" && -f "$SETUP" && -f "$MANAGER" && -f "$GERMAN" ]] \
  || fail "missing AppStrings or view sources"

python3 - "$STRINGS" "$MENU" "$SETUP" "$MANAGER" "$GERMAN" <<'PY'
import re
import sys
from pathlib import Path

strings_path, menu_path, setup_path, manager_path, german_path = map(Path, sys.argv[1:])
strings = strings_path.read_text()
menu = menu_path.read_text()
setup = setup_path.read_text()
manager = manager_path.read_text()
german = german_path.read_text()
failures: list[str] = []


def english_default(key: str) -> str:
    pattern = rf'(?:t|format)\(\s*"{re.escape(key)}",\s*\n?\s*"((?:\\.|[^"\\])*)"'
    match = re.search(pattern, strings)
    if not match:
        failures.append(f"missing English default for key {key!r}")
        return ""
    return match.group(1)


def german_value(key: str) -> str:
    pattern = rf'"{re.escape(key)}"\s*=\s*"((?:\\.|[^"\\])*)"'
    match = re.search(pattern, german)
    if not match:
        failures.append(f"missing German string for key {key!r}")
        return ""
    return match.group(1)


banned = (
    "Welcome to",
    "Manage your",
    "This page lets you",
    "This section lets you",
    "Use this to",
    "Here's where you'll",
    "Easily ",
    "Simply ",
    "Powerful ",
)
haystack = strings + "\n" + menu + "\n" + setup
for phrase in banned:
    if phrase.lower() in haystack.lower():
        failures.append(f"banned chrome phrase present: {phrase!r}")

cubase = english_default("cubase_control_room_hint")
if "click-free" in cubase.lower():
    failures.append("Cubase subtitle still tours click-free monitoring")
if "German UI:" in cubase or "Geräteanschlüsse" in cubase:
    failures.append("Cubase subtitle still carries a German-UI parenthetical")
if cubase.count(".") > 0:
    failures.append(f"Cubase subtitle should be one fragment without a period: {cubase!r}")
if cubase != "Assign Monitor 1 device ports to APM44 Bridge left and right":
    failures.append(f"Cubase subtitle should be the port-assignment constraint, got {cubase!r}")

empty_hint = english_default("no_output_devices_hint")
if "choose an output" in empty_hint.lower() or "here" in empty_hint.lower():
    failures.append(f"empty-output hint restates the picker: {empty_hint!r}")
if empty_hint != "Connect headphones or an audio interface":
    failures.append(f"empty-output hint should say why the list is empty, got {empty_hint!r}")

password = english_default("enter_admin_password")
if "enter your" in password.lower():
    failures.append(f"admin helper restates the password prompt: {password!r}")
if password != "Requires an admin password":
    failures.append(f"admin helper should be the privilege constraint, got {password!r}")

if "selectedOutputGoneHint" in manager or "selected_output_gone_hint" in strings:
    failures.append("gone-output banner still echoes the error heading")
if re.search(r"bannerMessage\s*=\s*AppStrings\.bridgeDidNotStop", manager):
    failures.append("stop-failure banner still repeats the error heading")

if re.search(
    r"Text\(AppStrings\.buffering\).*stoppedLatencyHint",
    menu,
    re.S,
):
    failures.append("stopped metrics still title the extra latency line as Buffering")

if "routingMode.menuLabel" in menu or "AppStrings.routingHal" in menu:
    failures.append("status hero still shows Using APM44 Bridge under Stopped")
if 't("routing_hal"' in strings or '"routing_hal"' in german:
    failures.append("Using APM44 Bridge / Nutzt APM44 Bridge strings are still defined")
if "var menuLabel" in Path(sys.argv[1]).parent.joinpath("HalDriverDetector.swift").read_text():
    failures.append("RoutingMode.menuLabel still supplies the Stopped subtitle")

stopped = english_default("stopped_latency_hint")
if "buffer" in stopped.lower() or "~%lld" in stopped:
    failures.append(f"stopped latency hint still restates the buffer target: {stopped!r}")
if stopped != "Device, DAW, and hardware latency are additional":
    failures.append(f"stopped latency hint should be the additional-latency fact, got {stopped!r}")

target = english_default("buffer_target %lld")
if "buffer" in target.lower():
    failures.append(f"buffering subtitle restates Buffering: {target!r}")
if target != "~%lld ms":
    failures.append(f"buffering subtitle should be the duration, got {target!r}")

minimum = english_default("buffer_target_minimum %lld")
if minimum != "~%lld ms (path minimum)":
    failures.append(f"HAL floor subtitle should keep the path-minimum constraint, got {minimum!r}")

reload_hint = english_default("driver_reload_hint")
if "." in reload_hint or "Core Audio" in reload_hint:
    failures.append(f"driver reload hint should be status only, got {reload_hint!r}")
if reload_hint != "Installed, not loaded":
    failures.append(f"driver reload hint should be installed-not-loaded status, got {reload_hint!r}")

restart_hint = english_default("driver_restart_hint")
if restart_hint.count(".") > 0:
    failures.append(f"driver restart hint should be one fragment, got {restart_hint!r}")
if restart_hint != "Restart the Mac once if it is still missing":
    failures.append(f"driver restart hint should be the first-load constraint, got {restart_hint!r}")

missing = english_default("driver_missing_detail")
if "open the" in missing.lower() or ".pkg" in missing.lower():
    failures.append(f"missing-driver detail repeats the installer action: {missing!r}")
if missing != "Not installed":
    failures.append(f"missing-driver detail should be status, got {missing!r}")

reconnect = english_default("reconnecting_attempt %lld %lld")
if "stable" in reconnect.lower():
    failures.append(f"reconnect banner still explains launch stability: {reconnect!r}")

previous = english_default("previous_output_unavailable %@")
if previous.count(".") > 1:
    failures.append(f"previous-output error should be one line, got {previous!r}")

detail_parts = setup.split("private var halRateDetail", 1)
if len(detail_parts) < 2:
    failures.append("missing halRateDetail")
else:
    body = detail_parts[1][:700]
    if "nominalRateHint" in body and "44100" not in body and "halRateOk" not in body:
        failures.append("passing HAL rate row still always shows the set-44100 hint")

german_expected = {
    "cubase_control_room_hint": "Monitor 1 Geräteanschlüsse auf APM44 Bridge links und rechts legen",
    "no_output_devices_hint": "Kopfhörer oder Audiointerface anschließen",
    "enter_admin_password": "Admin-Passwort erforderlich",
    "stopped_latency_hint": "Geräte-, DAW- und Hardware-Latenz kommen hinzu",
    "buffer_target %lld": "~%lld ms",
    "buffer_target_minimum %lld": "~%lld ms (Pfadminimum)",
    "driver_reload_hint": "Installiert, nicht geladen",
    "driver_restart_hint": "Mac einmal neu starten, wenn er weiter fehlt",
    "driver_missing_detail": "Nicht installiert",
    "reconnecting_attempt %lld %lld": "Verbindet neu … (Versuch %lld von %lld)",
    "previous_output_unavailable %@": "Vorherige Ausgabe „%@“ ist nicht verfügbar — andere Ausgabe wählen",
}
for key, expected in german_expected.items():
    got = german_value(key)
    if got and got != expected:
        failures.append(f"German {key!r} should be {expected!r}, got {got!r}")

if failures:
    print("test_ui_chrome: FAIL")
    for item in failures:
        print(f"  - {item}")
    sys.exit(1)

print("test_ui_chrome: OK")
PY
