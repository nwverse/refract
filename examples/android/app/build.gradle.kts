import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension

val robolectricRuntime = configurations.create("robolectricRuntime") {
    isCanBeConsumed = false
    isCanBeResolved = true
}

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
    id("dev.refract.generator")
}

refract {
    // An environment override keeps machine-specific CLI paths out of the build script.
    executable.set(providers.environmentVariable("REFRACT_CLI_PATH").map { layout.projectDirectory.file(it) })
    sources.register("screens") {
        inputs.from(
            rootProject.file("../shared/Hello.swift"),
            rootProject.file("../shared/NativeComponentScreen.swift"),
            rootProject.file("../shared/IdentifiedList.swift"),
            rootProject.file("../shared/SettingsScreen.swift"),
        )
        mapping.set(rootProject.file("../refract.json"))
        harmonyCommittedOutputDirectory.set(rootProject.file("../harmony/entry/src/main/ets/generated"))
        resources.from(
            rootProject.file("app/src/main/res/values/strings.xml"),
            rootProject.file("../harmony/entry/src/main/resources/base/element/string.json"),
        )
    }
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

    // The fixture compiler stages the exact remote-image CLI output and its
    // app-owned resources here for Native JVM tests in the real R namespace.
    sourceSets.getByName("test").kotlin.srcDir("src/fixtureTest/java")
    sourceSets.getByName("main").res.srcDir("src/fixtureTest/res")
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
    implementation("androidx.compose.animation:animation")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    debugImplementation("androidx.compose.ui:ui-tooling")

    // Native JVM test-only dependencies. They never enter the app's runtime
    // classpath or the generated screen, and the source set contains no
    // substitute for the CLI-generated SettingsScreen under test.
    // Native JVM tests consume the app-owned implementation in the fixture
    // library; the fixture itself contains no JVM runtime or test dependency.
    testImplementation(project(":fixtures"))
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
