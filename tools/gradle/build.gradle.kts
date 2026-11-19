plugins {
    `kotlin-dsl`
    `java-gradle-plugin`
}

group = "dev.refract"
version = "0.1.0"

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("com.android.tools.build:gradle-api:9.5.0")
    testImplementation(gradleTestKit())
    testImplementation("junit:junit:4.13.2")
}

gradlePlugin {
    plugins {
        create("generator") {
            id = "dev.refract.generator"
            implementationClass = "dev.refract.gradle.RefractPlugin"
            displayName = "Refract build-time native source generation"
            description = "Generates Android Compose source through an explicitly configured Refract CLI."
        }
    }
}

tasks.test {
    maxParallelForks = 1
    systemProperty("refract.test.repository", layout.settingsDirectory.dir("../..").asFile.absolutePath)
    systemProperty("refract.test.cli", providers.environmentVariable("REFRACT_CLI_PATH").get())
    systemProperty("refract.test.version", providers.environmentVariable("REFRACT_REQUIRED_VERSION").get())
    testLogging {
        events("failed", "skipped")
        // Full failure messages retain nested TestKit BuildResult.output; standard streams expose CLI diagnostics.
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
        showStandardStreams = true
    }
}
