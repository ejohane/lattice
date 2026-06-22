#!/usr/bin/env bash
set -euo pipefail

SIMULATOR_NAME="${1:-${SIMULATOR_NAME:-iPhone 17 Pro}}"
PROJECT_PATH="${PROJECT_PATH:-apps/ios/Lattice.xcodeproj}"
SCHEME="${SCHEME:-Lattice}"
BUNDLE_ID="${BUNDLE_ID:-com.ejohane.lattice.ios}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-.build/ios-derived-data}"

DEVICE_UDID="$(
  SIMULATOR_NAME="$SIMULATOR_NAME" node <<'NODE'
const { execFileSync } = require("node:child_process");

const requestedName = process.env.SIMULATOR_NAME;
const output = execFileSync("xcrun", ["simctl", "list", "devices", "available", "-j"], {
  encoding: "utf8",
});
const data = JSON.parse(output);
const devices = Object.entries(data.devices)
  .flatMap(([runtime, runtimeDevices]) =>
    runtimeDevices.map((device) => ({ ...device, runtime }))
  )
  .filter((device) => device.name === requestedName);

if (devices.length === 0) {
  const availableNames = [
    ...new Set(
      Object.values(data.devices)
        .flat()
        .map((device) => device.name)
    ),
  ].sort();

  console.error(`No available iOS Simulator named "${requestedName}".`);
  console.error("Available simulators:");
  for (const name of availableNames) {
    console.error(`  - ${name}`);
  }
  process.exit(1);
}

devices.sort((a, b) => b.runtime.localeCompare(a.runtime));
process.stdout.write(devices[0].udid);
NODE
)"

echo "Using simulator: ${SIMULATOR_NAME} (${DEVICE_UDID})"

xcrun simctl boot "$DEVICE_UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$DEVICE_UDID" -b
open -a Simulator --args -CurrentDeviceUDID "$DEVICE_UDID" >/dev/null 2>&1 || open -a Simulator

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=${DEVICE_UDID}" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Debug-iphonesimulator/Lattice.app"

xcrun simctl install "$DEVICE_UDID" "$APP_PATH"
xcrun simctl launch "$DEVICE_UDID" "$BUNDLE_ID"
