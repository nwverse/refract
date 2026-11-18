#!/usr/bin/env bash
# Build the shared Swift source and independent native reference on macOS.
# This command never creates, boots, reboots or selects a simulator.
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
: "${DERIVED_DATA:?Set DERIVED_DATA to a new, issue-owned output directory outside the repository.}"
if [ -e "$DERIVED_DATA" ]; then
    printf 'Refusing to overwrite an existing DERIVED_DATA directory.\n' >&2
    exit 2
fi
xcodebuild -project "$here/RefractBench.xcodeproj" \
    -scheme RefractBench -configuration Release \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO build-for-testing
printf 'Compiled only. No simulator/device was selected, created, booted or measured.\n'
