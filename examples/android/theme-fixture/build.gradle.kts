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

/**
 * Compiles the exact CLI-generated theme fixture and its app-owned design resources.
 * The source sets contain no replacement for the generated component.
 */
android {
    namespace = "refract.generated"
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

    sourceSets.getByName("main").apply {
        kotlin.srcDir("../../../Fixtures/theme-interaction-states/Expected.kt")
        kotlin.srcDir("../../../Fixtures/theme-interaction-states/NativeTheme.kt")
        kotlin.srcDir("../../../Fixtures/theme-interaction-states/NativeThemeHost.kt")
        res.srcDir("../../../Fixtures/theme-interaction-states")
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
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")

    // Native JVM verification only. None of these test dependencies enters the
    // generated component, the fixture's production ABI, or an application.
    testImplementation("androidx.activity:activity-compose:1.9.3")
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
    systemProperty("robolectric.offline", "true")
    systemProperty("robolectric.dependency.dir", stageRobolectricRuntime.get().destinationDir.absolutePath)
    systemProperty(
        "refract.theme.render.output",
        layout.buildDirectory.dir("reports/native-jvm-theme").get().asFile.absolutePath,
    )
}
