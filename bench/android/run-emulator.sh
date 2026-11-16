#!/usr/bin/env bash
# Build, measure and report. No device result is inferred from an emulator run.
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/.local/opt/android-sdk}"
export ANDROID_USER_HOME="${ANDROID_USER_HOME:-$HOME/.local/share/refract-android}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$HOME/.local/share/refract-gradle}"
: "${JAVA_HOME:?Set JAVA_HOME to a supported JDK (17 or newer).}"
export PATH="$JAVA_HOME/bin:$PATH"
adb="$ANDROID_HOME/platform-tools/adb"
[ -x "$adb" ] || { printf 'Missing adb; install Android platform-tools.\n' >&2; exit 2; }
[ -n "${ANDROID_SERIAL:-}" ] || {
    devices="$($adb devices | python3 -I -c 'import sys; print(sum(line.endswith("\tdevice\n") for line in sys.stdin))')"
    [ "$devices" = 1 ] || { printf 'Set ANDROID_SERIAL when zero or multiple devices are attached.\n' >&2; exit 2; }
}
model="$($adb shell getprop ro.product.model | tr -d '\r')"
qemu="$($adb shell getprop ro.kernel.qemu | tr -d '\r')"
sdk="$($adb shell getprop ro.build.version.sdk | tr -d '\r')"
boot="$($adb shell getprop sys.boot_completed | tr -d '\r')"
[ "$boot" = 1 ] || { printf 'Android system has not finished booting.\n' >&2; exit 2; }
[ "$qemu" = 1 ] || { printf 'Physical-device runs require a device-labelled report; this harness currently supports emulators.\n' >&2; exit 2; }
printf 'Environment: EMULATOR (%s), not a physical device.\n' "$model"
output_root=/sdcard/Android/media/dev.refract.bench.test
$adb shell "mkdir -p '$output_root' && test -w '$output_root'" || {
    printf 'External storage transport is not ready for benchmark output.\n' >&2
    exit 2
}
$adb shell settings put global window_animation_scale 0
$adb shell settings put global transition_animation_scale 0
$adb shell settings put global animator_duration_scale 0

out="${1:-$here/results/emulator-01}"
if [ -e "$out" ]; then
    printf 'Choose a new output directory; existing results are never overwritten.\n' >&2
    exit 2
fi
mkdir -p "$out/raw"
python3 -I -c 'import json,sys; json.dump({"emulator":True,"source":"adb ro.kernel.qemu","model":sys.argv[1],"sdk":int(sys.argv[2])},open(sys.argv[3],"w"),indent=2)' "$model" "$sdk" "$out/environment.json"
(
    cd "$here"
    ./gradlew --no-daemon --max-workers="${GRADLE_WORKERS:-2}" --console=plain \
        :app:assembleRelease :benchmark:assembleRelease || exit 1
    timeout "${BENCHMARK_TIMEOUT_SECONDS:-3600}" \
        ./gradlew --no-daemon --max-workers="${GRADLE_WORKERS:-2}" --console=plain \
        :benchmark:connectedReleaseAndroidTest || {
            printf 'Instrumentation failed or timed out; no benchmark pass is claimed.\n' >&2
            exit 1
        }
)
find "$here/benchmark/build/outputs/connected_android_test_additional_output" \
    -type f -name '*benchmarkData.json' 2>/dev/null | sort -u > "$out/json-files.txt"
[ -s "$out/json-files.txt" ] || { printf 'No AndroidX JSON results: benchmark did not run or failed.\n' >&2; exit 2; }
inputs=()
while IFS= read -r file; do
    cp -- "$file" "$out/raw/$(basename -- "$file")"
    inputs+=("$out/raw/$(basename -- "$file")")
done < "$out/json-files.txt"
python3 -I "$here/report.py" "${inputs[@]}" --output "$out" --environment "$out/environment.json"
printf 'Report written to %s. Raw results are in %s/raw.\n' "$out" "$out"
