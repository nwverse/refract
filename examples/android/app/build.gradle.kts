import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension

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
            rootProject.file("../shared/SettingsScreen.swift"),
        )
        mapping.set(rootProject.file("../refract.json"))
        resources.from(
            rootProject.file("app/src/main/res/values/strings.xml"),
            rootProject.file("../harmony/entry/src/main/resources/base/element/string.json"),
        )
    }
    sources.register("list") {
        // This canonical list intentionally uses the unmapped CLI generation path.
        inputs.from(rootProject.file("../shared/IdentifiedList.swift"))
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
}
