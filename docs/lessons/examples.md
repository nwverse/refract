# Building the mixed-code examples

## Keep hand-written expectations distinct from generated evidence

A native app can compile an expected Kotlin or ArkTS file before the generator exists, but that only verifies the
native boundary. It does not verify that the source parses, that generation is deterministic, or that the generated
output is faithful. Label such files and every resulting build explicitly. Replace them with the canonical fixture's
outputs and add a regeneration diff when the backends land; do not grow a second set of semantic expectations inside
`examples/`.

## Download only completed archives

Do not unpack a Gradle distribution while another background download is still writing it. A `.zip` suffix and an
existing path do not mean the download has completed. Wait for its completion notification, verify the published
SHA-256, and only then inspect and unpack the archive. This prevents both corrupted builds and wasted duplicate
bandwidth on a shared machine.

## Android SDK setup

Keep the Android SDK outside the repository and serialize installation with the shared lock from the local agent
brief. Check whether command-line tools already exist before creating download directories: another workstream may
finish the installation while your script is being prepared. The examples accept `ANDROID_HOME` rather than
committing `local.properties` or a machine-specific path.

Pin the Gradle wrapper, Android Gradle Plugin, Kotlin plugin and Compose BOM to compatible versions. In particular,
Kotlin 2.x needs the Compose compiler Gradle plugin instead of the removed `composeOptions.kotlinCompilerExtensionVersion`
configuration. Use the same JDK target for Java and Kotlin compilation. Run an actual Gradle build rather than
treating successful Kotlin formatting or a copied golden file as compilation evidence.
