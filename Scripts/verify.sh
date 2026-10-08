#!/bin/bash
#
# verify.sh: the one command that says whether OpenClinic is sound.
#
#   ./Scripts/verify.sh           unit tests on macOS, then an iOS Simulator build
#   ./Scripts/verify.sh tests     unit tests only
#   ./Scripts/verify.sh build     iOS Simulator build only
#
# Build products go to a DerivedData folder outside the repository, because the
# repository lives in iCloud Drive and an in-place build picks up extended
# attributes that break code signing.
#
# The test target is hosted by the macOS app. The app's entitlements file asks
# for HealthKit, which needs a development certificate, so the test run signs
# ad hoc and leaves the entitlements file out. No test exercises HealthKit.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="${OPENCLINIC_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/OpenClinic-verify}"
LOGS="$DERIVED/verify-logs"
MODE="${1:-all}"
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
        CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS= \
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

case "$MODE" in
    tests) run_tests ;;
    build) run_build ;;
    all)   run_tests; run_build ;;
    *)     fail "unknown mode '$MODE' (use: tests, build, or no argument)" ;;
esac

echo "verify: OK"
