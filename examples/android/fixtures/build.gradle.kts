import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension

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

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }

    sourceSets.getByName("main").kotlin.srcDir("src/native/java")
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
    implementation("androidx.navigation:navigation-compose:2.9.8")
}
