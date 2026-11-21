#!/usr/bin/env bash
# Probe, verify generated sources, measure and preserve complete macro evidence.
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "$here/../.." && pwd)"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/.local/opt/android-sdk}"
export ANDROID_USER_HOME="${ANDROID_USER_HOME:-$HOME/.local/share/refract-android}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$HOME/.local/share/refract-gradle}"
: "${JAVA_HOME:?Set JAVA_HOME to a supported JDK (17 or newer).}"
export PATH="$JAVA_HOME/bin:$PATH"
adb="$ANDROID_HOME/platform-tools/adb"
[ -x "$adb" ] || { printf 'Missing adb; install Android platform-tools.\n' >&2; exit 2; }

out="${1:-$root/tmp/macro-emulator-01}"
if [ -e "$out" ]; then
    printf 'Choose a new output directory; existing results are never overwritten.\n' >&2
    exit 2
fi
revision="$(git -C "$here" rev-parse --verify HEAD)"
if [ -n "$(git -C "$here" status --porcelain --untracked-files=normal)" ]; then
    printf 'Commit benchmark/generator changes before measuring an exact source revision.\n' >&2
    exit 2
fi
mkdir -p "$out/raw"
python3 -I "$here/probe_target.py" --adb "$adb" --source-revision "$revision" \
    --timeout "${TARGET_PROBE_TIMEOUT_SECONDS:-15}" --output "$out/environment.json"

export ANDROID_SERIAL="$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["android_serial"])' "$out/environment.json")"

# This checks that the actual CLI output is committed before compiling it. It
# never changes generated Kotlin/ArkTS or the hand-written reference.
"$here/generate-and-compile.sh" --check

# These are harness settings, not emulator boot/root/restart operations.
adb_target=("$adb")
if [ -n "${ANDROID_SERIAL:-}" ]; then
    adb_target+=(-s "$ANDROID_SERIAL")
fi
for setting in window_animation_scale transition_animation_scale animator_duration_scale; do
    timeout "${TARGET_PROBE_TIMEOUT_SECONDS:-15}" "${adb_target[@]}" shell settings put global "$setting" 0
done
python3 -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["animation_scales"]="disabled"; json.dump(d,open(p,"w"),indent=2,sort_keys=True)' "$out/environment.json"

# Never mix artifacts from an earlier connected-test invocation with this run.
additional_output="$here/benchmark/build/outputs/connected_android_test_additional_output"
if [ -e "$additional_output" ]; then
    [ -d "$additional_output" ] || { printf 'Unexpected additional-output path; preserve it manually.\n' >&2; exit 2; }
    mv -- "$additional_output" "$out/pre-existing-additional-output"
fi
python3 -I -c 'import pathlib,sys; pathlib.Path(sys.argv[1]).mkdir(exist_ok=False)' "$additional_output"

set +e
(
    cd "$here" || exit 1
    timeout "${BENCHMARK_TIMEOUT_SECONDS:-3600}" \
        ./gradlew --no-daemon --max-workers="${GRADLE_WORKERS:-2}" --console=plain \
        :benchmark:connectedReleaseAndroidTest \
        -Pandroid.testInstrumentationRunnerArguments.class=dev.refract.bench.test.SettingsMacrobenchmark \
        -Pandroid.test.devices="$ANDROID_SERIAL" \
        -Pandroid.testInstrumentationRunnerArguments.androidx.benchmark.output.payload.refract.sourceRevision="$revision"
)
instrumentation_status=$?
set -e
python3 -I -c 'import json,sys; json.dump({"status":"completed" if sys.argv[1]=="0" else "failed","exit_code":int(sys.argv[1])},open(sys.argv[2],"w"),indent=2)' \
    "$instrumentation_status" "$out/instrumentation-status.json"
if [ "$instrumentation_status" -ne 0 ]; then
    printf 'Instrumentation failed or timed out; no benchmark pass is claimed: %s\n' "$out" >&2
    exit 1
fi
if [ -n "$(git -C "$here" status --porcelain --untracked-files=normal)" ] || \
        [ "$(git -C "$here" rev-parse --verify HEAD)" != "$revision" ]; then
    printf 'Source changed during measurement; raw files are quarantined and no evidence is collected: %s\n' "$out" >&2
    exit 2
fi
python3 -I -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["source_tree"]="HEAD matched and worktree clean after generated-source verification, release compilation and measurement"; json.dump(d,open(p,"w"),indent=2,sort_keys=True)' "$out/environment.json"
set +e
python3 -I "$here/collect_results.py" \
    --input-directory "$here/benchmark/build/outputs/connected_android_test_additional_output" \
    --output "$out" --environment "$out/environment.json"
evidence_status=$?
set -e
if [ "$evidence_status" -ne 0 ]; then
    printf 'Required evidence was not preserved; no benchmark pass is claimed: %s\n' "$out" >&2
    exit 2
fi
inputs=()
while IFS= read -r file; do
    inputs+=("$out/$file")
done < "$out/json-files.txt"
python3 -I "$here/report.py" "${inputs[@]}" --output "$out" \
    --require-macro --evidence-manifest "$out/evidence-manifest.json"
printf 'Verified macro report and preserved evidence written to %s.\n' "$out"
