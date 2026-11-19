#!/usr/bin/env bash
# Explicit target-only benchmark driver. It performs no target lifecycle action.
set -euo pipefail
here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "$here/../.." && pwd)"
: "${TARGET_UDID:?Pass an explicitly owned, already-booted target UDID.}"
: "${RUN_DIRECTORY:?Pass a new, issue-owned run directory outside the repository.}"
: "${DERIVED_DATA:?Pass the build.sh output directory.}"
if [ -e "$RUN_DIRECTORY" ]; then
    printf 'Refusing to reuse a run directory; incomplete evidence must not be replaced.\n' >&2
    exit 2
fi
mkdir -p "$RUN_DIRECTORY"
revision="$(git -C "$root" rev-parse HEAD)"
[ "$(git -C "$root" status --porcelain)" = "" ] || {
    printf 'Timing requires a committed source revision.\n' >&2
    exit 2
}
if ! xcrun devicectl list devices --json-output "$RUN_DIRECTORY/targets.json" --quiet; then
    printf 'Unable to inspect devicectl targets; no target was started.\n' >&2
    exit 2
fi
export REFRACT_BENCH_REVISION="$revision"
# This preflight deliberately rejects unknown/unavailable targets; no device or
# simulator is started, restarted, erased, paired or reconfigured here.
if ! xcrun simctl list devices available --json > "$RUN_DIRECTORY/simulators.json"; then
    printf 'Unable to inspect the explicitly named target.\n' >&2
    exit 2
fi
python3 -I "$here/probe_target.py" --udid "$TARGET_UDID" \
    --simulators "$RUN_DIRECTORY/simulators.json" \
    --targets "$RUN_DIRECTORY/targets.json" --output "$RUN_DIRECTORY/target.json"
xcodebuild -project "$here/RefractBench.xcodeproj" \
    -scheme RefractBench -configuration Release \
    -destination "platform=iOS Simulator,id=$TARGET_UDID" \
    -derivedDataPath "$DERIVED_DATA" -resultBundlePath "$RUN_DIRECTORY/results.xcresult" \
    CODE_SIGNING_ALLOWED=NO REFRACT_BENCH_REVISION="$revision" test
printf 'The raw result bundle is in %s. It is not a report until bench/common/report.py validates a manifest.\n' "$RUN_DIRECTORY"
