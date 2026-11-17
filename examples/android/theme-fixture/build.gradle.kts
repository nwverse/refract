import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension

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
}
