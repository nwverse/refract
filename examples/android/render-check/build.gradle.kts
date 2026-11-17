import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.plugin.compose")
}

val robolectricRuntime = configurations.create("robolectricRuntime") {
    isCanBeConsumed = false
    isCanBeResolved = true
}

// Test-only Native JVM Compose verification. This module is not an app runtime
// dependency and never changes or substitutes the generated screen under test.
android {
    namespace = "com.example.refract.rendercheck"
    compileSdk = 37
    compileSdkMinor = 2

    defaultConfig {
        minSdk = 26
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
    }
}

configure<KotlinAndroidProjectExtension> {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2026.09.00")
    implementation(composeBom)
    implementation("androidx.compose.ui:ui")

    // :app contains the actual CLI-generated SettingsScreen.kt, checked by
    // scripts/check_examples.py before this module is compiled or tested.
    implementation(project(":app"))

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.18")
    robolectricRuntime("org.robolectric:android-all-instrumented:15-robolectric-14663667-2-i7")
    testImplementation("androidx.compose.material3:material3")
    testImplementation("androidx.compose.ui:ui-test-junit4")
    testImplementation("androidx.compose.ui:ui-test-manifest")
}

val stageRobolectricRuntime by tasks.registering(Copy::class) {
    from(robolectricRuntime)
    into(layout.buildDirectory.dir("robolectric-runtime"))
    include("android-all-instrumented-*.jar")
}

tasks.withType<Test>().configureEach {
    dependsOn(stageRobolectricRuntime)
    // Gradle already resolved this exact public test dependency; do not let
    // Robolectric silently select a different, inaccessible runtime repository.
    systemProperty("robolectric.offline", "true")
    systemProperty("robolectric.dependency.dir", stageRobolectricRuntime.get().destinationDir.absolutePath)
    systemProperty(
        "refract.render.output",
        layout.buildDirectory.dir("reports/native-jvm-compose").get().asFile.absolutePath,
    )
}
