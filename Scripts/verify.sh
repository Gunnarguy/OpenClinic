#!/bin/bash
#
# verify.sh: the one command that says whether OpenClinic is sound.
#
#   ./Scripts/verify.sh           unit tests on macOS, then an iOS Simulator build
#   ./Scripts/verify.sh tests     unit tests only
#   ./Scripts/verify.sh build     iOS Simulator build only
#   ./Scripts/verify.sh live      a real SMART on FHIR sign-in against launch.smarthealthit.org
#   ./Scripts/verify.sh device    build, install and self-check on a connected iPhone or iPad
#
# Build products go to a DerivedData folder outside the repository, because the
# repository lives in iCloud Drive and an in-place build picks up extended
# attributes that break code signing.
#
# The test target is hosted by the macOS app and signed ad hoc.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="${OPENCLINIC_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/OpenClinic-verify}"
LOGS="$DERIVED/verify-logs"
MODE="${1:-all}"
DEVICE_ID="${2:-}"
MIN_FREE_GB=4

cd "$REPO"
mkdir -p "$LOGS"

fail() { echo "verify: FAIL: $*" >&2; exit 1; }

# 1. iCloud writes "Foo 2.swift" conflict copies that Xcode compiles for real.
conflicts="$(find OpenClinic OpenClinicTests -name '* [0-9].*' -print 2>/dev/null || true)"
[ -z "$conflicts" ] || fail "iCloud conflict copies present:
$conflicts"

# 2. A build needs room; a full disk fails in ways that look like code defects.
free_gb="$(df -g /System/Volumes/Data | awk 'NR==2 {print $4}')"
[ "${free_gb:-0}" -ge "$MIN_FREE_GB" ] || fail "only ${free_gb} GB free on the data volume, need ${MIN_FREE_GB}"

# 3. The demo fixture must be valid JSON before anything compiles against it.
if [ -f OpenClinic/Resources/Demo/DemoPanel.json ]; then
    python3 -m json.tool OpenClinic/Resources/Demo/DemoPanel.json > /dev/null || fail "DemoPanel.json is not valid JSON"
fi

run_tests() {
    local log="$LOGS/test.log"
    echo "verify: unit tests (macOS host), log: $log"
    if ! xcodebuild test \
        -project OpenClinic.xcodeproj \
        -scheme OpenClinic \
        -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED/mac" \
        CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
        > "$log" 2>&1; then
        grep -E "error:|failed|XCTAssert|PANEL EVAL" "$log" | grep -v "Connection\]" | head -60 || true
        fail "unit tests failed"
    fi
    grep -E "PANEL EVAL" "$log" | tail -1 || true
    grep -E "Executed [0-9]+ tests" "$log" | tail -1 | sed 's/^[[:space:]]*/verify: /'
    local warnings
    warnings="$(grep -c "warning:" "$log" || true)"
    echo "verify: test build warnings: $warnings"
}

run_build() {
    local log="$LOGS/build-ios.log"
    echo "verify: iOS Simulator build, log: $log"
    if ! xcodebuild build \
        -project OpenClinic.xcodeproj \
        -scheme OpenClinic \
        -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath "$DERIVED/ios" \
        CODE_SIGNING_ALLOWED=NO \
        > "$log" 2>&1; then
        grep -E "error:" "$log" | head -40 || true
        fail "iOS Simulator build failed"
    fi
    local warnings
    warnings="$(grep -c "warning:" "$log" || true)"
    echo "verify: iOS Simulator build succeeded, warnings: $warnings"
    echo "verify: app at $DERIVED/ios/Build/Products/Debug-iphonesimulator/OpenClinic.app"
}

# A real SMART on FHIR sign-in against launch.smarthealthit.org (synthetic patients, no password).
# It needs the network, so it is not part of the default run. The test host is the sandboxed Mac
# app, so this also shows that the outgoing-network entitlement lets the Mac build reach a server.
run_live() {
    local log="$LOGS/live.log"
    echo "verify: live SMART sign-in against launch.smarthealthit.org, log: $log"
    if ! TEST_RUNNER_OPENCLINIC_LIVE_SMART=1 xcodebuild test \
        -project OpenClinic.xcodeproj \
        -scheme OpenClinic \
        -destination 'platform=macOS' \
        -derivedDataPath "$DERIVED/mac" \
        -only-testing:OpenClinicTests/SMARTLiveSignInTests \
        CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
        > "$log" 2>&1; then
        grep -E "error:|failed|XCTAssert|SMART LIVE" "$log" | grep -v "Connection\]" | head -40 || true
        fail "live SMART sign-in failed"
    fi
    grep -E "SMART LIVE" "$log" | sed 's/^.*SMART LIVE/verify: SMART LIVE/' || true
    grep -E "Executed [0-9]+ tests" "$log" | tail -1 | sed 's/^[[:space:]]*/verify: /'
    if grep -q "skipped" "$log" && ! grep -q "SMART LIVE" "$log"; then
        fail "the live tests were skipped: the environment variable did not reach the test runner"
    fi
}

# Builds for a connected iPhone or iPad, installs, and launches with -OpenClinicSelfCheck, which
# makes a debug build check itself and print SELFCHECK lines (OpenClinic/Demo/DeviceSelfCheck.swift).
# The device has to be unlocked. Pass a device id as the second argument, or the first paired
# iPhone or iPad that devicectl lists as available is used.
run_device() {
    local device="${DEVICE_ID:-}"
    if [ -z "$device" ]; then
        device="$(xcrun devicectl list devices 2>/dev/null | grep 'available (paired)' | grep -E 'iPhone|iPad' | grep -oE '[0-9A-F]{8}-[0-9A-F]{16}' | head -1 || true)"
    fi
    [ -n "$device" ] || fail "no paired iPhone or iPad is available (xcrun devicectl list devices)"

    local log="$LOGS/build-device.log"
    echo "verify: device build for $device, log: $log"
    if ! xcodebuild build \
        -project OpenClinic.xcodeproj \
        -scheme OpenClinic \
        -destination "id=$device" \
        -derivedDataPath "$DERIVED/device" \
        > "$log" 2>&1; then
        grep -E "error:" "$log" | head -40 || true
        fail "device build failed"
    fi

    local app="$DERIVED/device/Build/Products/Debug-iphoneos/OpenClinic.app"
    local run="$LOGS/device-run.log"
    echo "verify: installing on the device"
    xcrun devicectl device install app --device "$device" "$app" > "$LOGS/device-install.log" 2>&1 \
        || { tail -5 "$LOGS/device-install.log"; fail "install failed"; }

    echo "verify: launching with -OpenClinicSelfCheck, log: $run"
    # --console stays attached until the app exits, so the run is cut off once DONE has been printed.
    # Everything after "--" is the bundle id and the app's own arguments, not an option of devicectl.
    ( xcrun devicectl device process launch --device "$device" --terminate-existing --console \
        -- Gunndamental.OpenClinic -OpenClinicSelfCheck > "$run" 2>&1 ) &
    local launcher=$!
    local waited=0
    while [ "$waited" -lt 300 ] && kill -0 "$launcher" 2>/dev/null && ! grep -q "SELFCHECK DONE" "$run" 2>/dev/null; do
        python3 -c "import time; time.sleep(2)"
        waited=$((waited + 2))
    done
    kill "$launcher" 2>/dev/null || true
    grep "SELFCHECK" "$run" | sed 's/^/verify: /' || true
    grep -q "SELFCHECK DONE" "$run" || { tail -5 "$run"; fail "the self-check did not finish (is the device unlocked?)"; }
    grep -q "SELFCHECK DONE passed=[0-9]* failed=0" "$run" || fail "the self-check reported a failure"
}

case "$MODE" in
    tests)  run_tests ;;
    build)  run_build ;;
    live)   run_live ;;
    device) run_device ;;
    all)    run_tests; run_build ;;
    *)      fail "unknown mode '$MODE' (use: tests, build, live, device, or no argument)" ;;
esac

echo "verify: OK"
