#!/usr/bin/env bash
# Build the shared Swift source and independent native reference on macOS.
# This command never creates, boots, reboots or selects a simulator.
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "$here/../.." && pwd)"
: "${DERIVED_DATA:?Set DERIVED_DATA to a new, issue-owned output directory outside the repository.}"
if [ -e "$DERIVED_DATA" ]; then
    printf 'Refusing to overwrite an existing DERIVED_DATA directory.\n' >&2
    exit 2
fi
revision="$(git -C "$root" rev-parse HEAD)"
if [ -n "$(git -C "$root" status --porcelain)" ]; then
    printf 'Build provenance requires a clean committed source revision.\n' >&2
    exit 2
fi
xcodebuild -project "$here/RefractBench.xcodeproj" \
    -scheme RefractBench -configuration Release \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO build-for-testing
if [ "$(git -C "$root" rev-parse HEAD)" != "$revision" ] || [ -n "$(git -C "$root" status --porcelain)" ]; then
    printf 'Source changed during the build; refusing to assign its products to a revision.\n' >&2
    exit 2
fi
python3 -I "$here/record_build_provenance.py" --derived-data "$DERIVED_DATA" --source-revision "$revision"
printf 'Compiled only. No simulator/device was selected, created, booted or measured.\n'
