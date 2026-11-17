import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension

val robolectricRuntime = configurations.create("robolectricRuntime") {
    isCanBeConsumed = false
    isCanBeResolved = true
}

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Compiles the canonical Refract fixture corpus. The package `refract.generated`
// matches the package declared by Fixtures/<case>/Expected.kt so the generated
// code's R class is `refract.generated.R`, exactly what the fixtures reference.
//
// The Kotlin sources under src/main/java/refract/generated/ and the resources
// under src/main/res/values/strings.xml are written by
// scripts/check_fixture_compilation.py, which regenerates each fixture through
// the actual refract CLI, diffs the output against the committed Expected.kt,
// and stages the Kotlin and resources under this module. The staged files are
// .gitignored: they must be regenerated on every CI run, never committed.
// Running :fixtures:compileDebugKotlin without staging first is a build error
// because the source set will be empty.
android {
    namespace = "refract.generated"
    compileSdk = 37
    compileSdkMinor = 2

    defaultConfig {
        minSdk = 26
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }

    sourceSets.getByName("main").kotlin.directories.addAll(
        listOf(
            "src/native/java",
            "../app/src/main/java/com/example/refract/animation",
            "../../../Fixtures/theme-interaction-states/Expected.kt",
            "../../../Fixtures/theme-interaction-states/NativeTheme.kt",
            "../../../Fixtures/theme-interaction-states/NativeThemeHost.kt",
        ),
    )
    sourceSets.getByName("main").res.srcDir("../../../Fixtures/theme-interaction-states")
}

configure<KotlinAndroidProjectExtension> {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2026.09.00")
    implementation(composeBom)
    implementation("androidx.compose.animation:animation")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.navigation:navigation-compose:2.9.8")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.18")
    robolectricRuntime("org.robolectric:android-all-instrumented:15-robolectric-14663667-2-i7")
    testImplementation("androidx.test.ext:junit:1.3.0")
    testImplementation("androidx.core:core:1.17.0")
    testImplementation("androidx.compose.ui:ui-test-junit4")
}

// The test injects observation into the app-owned native implementation through
// a CompositionLocal. The CLI-generated screen is staged and called verbatim;
// no generated code is rewritten to add test-only parameters.
val stageRobolectricRuntime = tasks.register<Copy>("stageRobolectricRuntime") {
    from(robolectricRuntime)
    into(layout.buildDirectory.dir("robolectric-runtime"))
    include("android-all-instrumented-*.jar")
}

tasks.withType<Test>().configureEach {
    dependsOn(stageRobolectricRuntime)
    // Resolve the public runtime through Gradle, then run without a second downloader.
    systemProperty("robolectric.offline", "true")
    systemProperty("robolectric.dependency.dir", stageRobolectricRuntime.get().destinationDir.absolutePath)
    systemProperty(
        "refract.render.output",
        layout.buildDirectory.dir("reports/native-jvm-compose").get().asFile.absolutePath,
    )
}
