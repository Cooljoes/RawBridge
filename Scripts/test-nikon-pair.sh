#!/bin/bash
# Adds test assets to the specified simulator. Never targets a physical device.
set -euo pipefail
cd "$(dirname "$0")/.."
sim=${1:?Pass the UDID of a disposable, available iOS simulator}
fixture=build/rawbridge-fixture
derived=build/Derived
bundle=io.github.cooljoes.RawBridge
mkdir -p "$fixture"
xcrun simctl boot "$sim" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$sim" -b
if [[ ! -f "$fixture/iss030e122639.NEF" ]]; then
    curl --fail --location --retry 2 'https://raw.githubusercontent.com/letmaik/rawpy/main/test/iss030e122639.NEF' -o "$fixture/iss030e122639.NEF"
fi
expected=5922721d13f11795557d97fdeb0a60b900086c402bc82a848ff280d15b99ffd4
actual=$(shasum -a 256 "$fixture/iss030e122639.NEF" | cut -d' ' -f1)
[[ "$expected" == "$actual" ]] || { echo 'Nikon fixture SHA-256 mismatch' >&2; exit 1; }
sips -s format jpeg -Z 1400 "$fixture/iss030e122639.NEF" --out "$fixture/iss030e122639.JPG" >/dev/null
args=(-project RawBridge.xcodeproj -scheme RawBridge -destination "id=$sim" -derivedDataPath "$derived" -parallel-testing-enabled NO)
xcodebuild "${args[@]}" build-for-testing
xcrun simctl install "$sim" "$derived/Build/Products/Debug-iphonesimulator/RawBridge.app"
xcrun simctl privacy "$sim" grant photos "$bundle"
container=$(xcrun simctl get_app_container "$sim" "$bundle" data)
mkdir -p "$container/Documents/RawBridgeTestFixture"
cp "$fixture"/iss030e122639.{NEF,JPG} "$container/Documents/RawBridgeTestFixture/"
if [[ -n "${2:-}" ]]; then
    dng_hash=$(shasum -a 256 "$2" | cut -d' ' -f1)
    [[ "$dng_hash" == e91e77a4533ed7cce551d83330676ea5c47dd5e55fb38adda7819366afdbdfc2 ]] || {
        echo 'Apple DNG fixture SHA-256 mismatch' >&2; exit 1;
    }
    cp "$2" "$container/Documents/RawBridgeTestFixture/IMG_1361.DNG"
fi
xcodebuild "${args[@]}" test-without-building
