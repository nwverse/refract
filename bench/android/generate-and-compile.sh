#!/usr/bin/env bash
# Regenerate the actual benchmark screen, review both outputs, and compile without an emulator.
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd -- "$here/../.." && pwd)"
: "${JAVA_HOME:?Set JAVA_HOME to a supported JDK (17 or newer).}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/.local/opt/android-sdk}"
export ANDROID_USER_HOME="${ANDROID_USER_HOME:-$HOME/.local/share/refract-android}"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$HOME/.local/share/refract-gradle}"
export PATH="$JAVA_HOME/bin:$PATH"
cli="$root/.build/debug/refract"
check_only=false
if [ "${1:-}" = "--check" ]; then
    check_only=true
    shift
fi
[ -x "$cli" ] || [ "$check_only" = true ] || { printf 'Build the real CLI with `swift build` first.\n' >&2; exit 2; }
if [ "$check_only" = true ]; then
    command -v swift >/dev/null || { printf 'Swift is required to rebuild and check the real CLI.\n' >&2; exit 2; }
    swift build --package-path "$root"
fi
out="${1:-$root/tmp/benchmark-generated}"
[ "$out" = "$root/tmp/benchmark-generated" ] || {
    printf 'Generated staging is restricted to the repository-ignored %s directory.\n' "$root/tmp/benchmark-generated" >&2
    exit 2
}
rm -rf -- "$out"
mkdir -p "$out/android" "$out/harmony"
"$cli" generate \
    --input "$here/SettingsScreen.swift" \
    --mapping "$here/refract.json" \
    --android-out "$out/android" \
    --harmony-out "$out/harmony"
[ -f "$out/android/SettingsScreen.kt" ] && [ -f "$out/harmony/SettingsScreen.ets" ] || {
    printf 'The CLI did not produce both native outputs.\n' >&2
    exit 2
}
if [ "$check_only" = true ]; then
    cmp -- "$out/android/SettingsScreen.kt" "$here/screen/src/main/java/dev/refract/bench/SettingsScreen.kt"
    cmp -- "$here/SettingsScreen.swift" "$root/Fixtures/benchmark-settings/Input.swift"
    # The fixture keeps its own canonical Input.swift filename and Android
    # package mapping; check its ArkTS from that exact source and mapping.
    mkdir -p "$out/fixture"
    "$cli" generate --input "$root/Fixtures/benchmark-settings/Input.swift" \
        --mapping "$root/Fixtures/benchmark-settings/refract.json" \
        --harmony-out "$out/fixture"
    cmp -- "$out/fixture/Input.ets" "$root/Fixtures/benchmark-settings/Expected.ets"
else
    cp -- "$out/android/SettingsScreen.kt" "$here/screen/src/main/java/dev/refract/bench/SettingsScreen.kt"
    cmp -- "$out/android/SettingsScreen.kt" "$here/screen/src/main/java/dev/refract/bench/SettingsScreen.kt"
fi
(
    cd "$here"
    ./gradlew --no-daemon --max-workers="${GRADLE_WORKERS:-2}" --console=plain \
        :app:assembleRelease :benchmark:assembleRelease
)
printf 'Generated Kotlin/ArkTS are in %s. Kotlin compiled; ArkTS and performance were not measured.\n' "$out"
