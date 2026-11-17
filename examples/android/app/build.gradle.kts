import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension

val robolectricRuntime = configurations.create("robolectricRuntime") {
    isCanBeConsumed = false
    isCanBeResolved = true
}

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.example.refract"
    compileSdk = 37
    compileSdkMinor = 2

    defaultConfig {
        applicationId = "com.example.refract"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
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
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    debugImplementation("androidx.compose.ui:ui-tooling")

    // Native JVM test-only dependencies. They never enter the app's runtime
    // classpath or the generated screen, and the source set contains no
    // substitute for the CLI-generated SettingsScreen under test.
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.18")
    robolectricRuntime("org.robolectric:android-all-instrumented:15-robolectric-14663667-2-i7")
    testImplementation("androidx.compose.ui:ui-test-junit4")
    testImplementation("androidx.compose.ui:ui-test-manifest")
}

val stageRobolectricRuntime = tasks.register<Copy>("stageRobolectricRuntime") {
    from(robolectricRuntime)
    into(layout.buildDirectory.dir("robolectric-runtime"))
    include("android-all-instrumented-*.jar")
}

tasks.withType<Test>().configureEach {
    dependsOn(stageRobolectricRuntime)
    // Use the exact public artifact resolved by Gradle, not a second runtime
    // downloader whose default repository may differ from this build's.
    systemProperty("robolectric.offline", "true")
    systemProperty("robolectric.dependency.dir", stageRobolectricRuntime.get().destinationDir.absolutePath)
    systemProperty(
        "refract.render.output",
        layout.buildDirectory.dir("reports/native-jvm-compose").get().asFile.absolutePath,
    )
}
