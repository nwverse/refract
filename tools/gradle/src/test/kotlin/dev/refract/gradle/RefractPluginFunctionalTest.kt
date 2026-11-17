package dev.refract.gradle

import java.io.File
import org.gradle.testkit.runner.BuildResult
import org.gradle.testkit.runner.GradleRunner
import org.gradle.testkit.runner.TaskOutcome
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class RefractPluginFunctionalTest {
    @get:Rule
    val temporary = TemporaryFolder()

    private lateinit var project: File
    private lateinit var executable: File
    private lateinit var androidSdk: File
    private val cli = requireNotNull(System.getProperty("refract.test.cli")) {
        "Build the CLI and pass REFRACT_CLI_PATH before running the Gradle functional tests."
    }
    private val repository = File(requireNotNull(System.getProperty("refract.test.repository"))).canonicalFile

    @Before
    fun setUp() {
        project = temporary.newFolder("consumer")
        executable = File(cli).canonicalFile
        assertTrue("REFRACT_CLI_PATH must identify the actual CLI", executable.isFile)
        androidSdk = File(requireNotNull(System.getenv("ANDROID_HOME"))).canonicalFile
        assertTrue(File(androidSdk, "platforms").isDirectory)
        File(project, "gradle.properties").writeText("org.gradle.daemon=false\n")
        File(project, "local.properties").writeText("sdk.dir=${androidSdk.invariantSeparatorsPath}\n")
        File(project, "settings.gradle.kts").writeText(
            """
            pluginManagement {
                repositories { google(); mavenCentral(); gradlePluginPortal() }
            }
            dependencyResolutionManagement {
                repositories { google(); mavenCentral() }
            }
            rootProject.name = "consumer"
            includeBuild("${File(repository, "tools/gradle").invariantSeparatorsPath}")
            """.trimIndent(),
        )
        File(project, "build.gradle.kts").writeText(
            """
            import dev.refract.gradle.RefractGenerateTask
            plugins {
                id("com.android.application") version "9.5.0"
                id("org.jetbrains.kotlin.plugin.compose") version "2.4.21"
                id("dev.refract.generator")
            }
            refract {
                executable.set(layout.projectDirectory.file("${executable.invariantSeparatorsPath}"))
                sources.register("screens") {
                    inputs.from(layout.projectDirectory.file("Screen.swift"))
                    mapping.set(layout.projectDirectory.file("refract.json"))
                    resources.from(layout.projectDirectory.file("strings.xml"))
                    committedOutputDirectory.set(layout.projectDirectory.dir("committed"))
                }
            }
            android {
                namespace = "example.consumer"
                compileSdk = 37
                compileSdkMinor = 2
                defaultConfig { minSdk = 26 }
                buildFeatures { compose = true }
            }
            dependencies {
                implementation(platform("androidx.compose:compose-bom:2026.09.00"))
                implementation("androidx.compose.ui:ui")
            }
            tasks.register("sharedGeneration", RefractGenerateTask::class) {
                executable.from(refract.executable)
                swiftInputs.from(layout.projectDirectory.file("Screen.swift"))
                mapping.set(layout.projectDirectory.file("refract.json"))
                resources.from(layout.projectDirectory.file("strings.xml"))
                outputDirectory.set(layout.buildDirectory.dir("generated/shared"))
            }
            """.trimIndent(),
        )
        File(project, "Screen.swift").writeText(
            """
            import SwiftUI
            struct Screen: View {
                var body: some View {
                    Text("example.hello")
                }
            }
            """.trimIndent(),
        )
        File(project, "refract.json").writeText(
            """
            {
              "schemaVersion": 1,
              "android": {
                "output": { "directory": "generated", "packageName": "refract.generated" },
                "imports": [], "components": {}, "nativeComponents": {}, "modifiers": {},
                "tokens": { "spacing": {}, "radius": {}, "font": {}, "color": {} },
                "resources": { "className": "example.consumer.R", "catalog": "strings.xml", "strings": { "example.hello": "example_hello" } }
              },
              "harmonyOS": {
                "output": { "directory": "generated" },
                "imports": [], "components": {}, "nativeComponents": {}, "modifiers": {},
                "tokens": { "spacing": {}, "radius": {}, "font": {}, "color": {} },
                "resources": { "namespace": "app", "stringTable": "string", "catalog": "string.json", "strings": { "example.hello": "example_hello" } }
              }
            }
            """.trimIndent(),
        )
        File(project, "strings.xml").writeText(
            "<resources><string name=\"example_hello\">Hello</string></resources>\n",
        )
        File(project, "string.json").writeText(
            "{\"string\":[{\"name\":\"example_hello\",\"value\":\"Hello\"}]}\n",
        )
    }

    @Test
    fun realCliGenerationCompilesIsUpToDateAndTracksInputs() {
        val first = run("generateDebugScreensRefract", "compileDebugKotlin")
        assertEquals(TaskOutcome.SUCCESS, first.task(":generateDebugScreensRefract")?.outcome)
        assertEquals(TaskOutcome.SUCCESS, first.task(":compileDebugKotlin")?.outcome)
        val output = File(project, "build/generated/refract/screens/Debug/Screen.kt")
        assertTrue(output.isFile)
        val initial = output.readBytes()

        val second = run("generateDebugScreensRefract", "compileDebugKotlin")
        assertEquals(TaskOutcome.UP_TO_DATE, second.task(":generateDebugScreensRefract")?.outcome)
        assertEquals(TaskOutcome.UP_TO_DATE, second.task(":compileDebugKotlin")?.outcome)
        assertTrue(initial.contentEquals(output.readBytes()))

        File(project, "Screen.swift").appendText("\n// An input change must invalidate generation.\n")
        val changed = run("generateDebugScreensRefract")
        assertEquals(TaskOutcome.SUCCESS, changed.task(":generateDebugScreensRefract")?.outcome)
        assertTrue(initial.contentEquals(output.readBytes()))

        val clean = run("clean", "generateDebugScreensRefract")
        assertEquals(TaskOutcome.SUCCESS, clean.task(":generateDebugScreensRefract")?.outcome)
        assertTrue(initial.contentEquals(output.readBytes()))
    }

    @Test
    fun missingToolAndInvalidInputFailWithoutPublishingOutput() {
        File(project, "build.gradle.kts").appendText(
            "\ntasks.named<RefractGenerateTask>(\"generateDebugScreensRefract\") { executable.from(files(\"missing-cli\")) }\n",
        )
        val missing = runAndFail("generateDebugScreensRefract")
        assertTrue(missing.output, missing.output.contains("Refract CLI is not an executable file"))
        assertFalse(File(project, "build/generated/refract/screens/Debug/Screen.kt").exists())

        File(project, "build.gradle.kts").appendText(
            "\ntasks.named<RefractGenerateTask>(\"generateDebugScreensRefract\") { executable.from(refract.executable) }\n",
        )
        assertEquals(TaskOutcome.SUCCESS, run("generateDebugScreensRefract").task(":generateDebugScreensRefract")?.outcome)
        val output = File(project, "build/generated/refract/screens/Debug/Screen.kt")
        val previous = output.readBytes()
        File(project, "Screen.swift").appendText("\nthis is not Swift\n")
        val invalid = runAndFail("generateDebugScreensRefract")
        assertTrue(invalid.output, invalid.output.contains("existing generated and committed outputs were not changed"))
        assertTrue(previous.contentEquals(output.readBytes()))
    }

    @Test
    fun sharedTaskInvalidatesForSwiftMappingAndResourceChanges() {
        assertEquals(TaskOutcome.SUCCESS, run("sharedGeneration").task(":sharedGeneration")?.outcome)
        assertEquals(TaskOutcome.UP_TO_DATE, run("sharedGeneration").task(":sharedGeneration")?.outcome)
        for (path in listOf("Screen.swift", "refract.json", "strings.xml")) {
            File(project, path).appendText(if (path.endsWith(".json")) "\n" else "\n// input changed\n")
            assertEquals(path, TaskOutcome.SUCCESS, run("sharedGeneration").task(":sharedGeneration")?.outcome)
            assertEquals(path, TaskOutcome.UP_TO_DATE, run("sharedGeneration").task(":sharedGeneration")?.outcome)
        }
    }

    @Test
    fun staleOutputFailsThroughTheRealCliWithoutWriting() {
        val committed = File(project, "committed/Screen.kt")
        committed.parentFile.mkdirs()
        committed.writeText("stale\n")
        val before = committed.readBytes()
        val failure = runAndFail("checkDebugScreensRefract")
        assertTrue(failure.output, failure.output.contains("Refract committed-output check failed"))
        assertTrue(before.contentEquals(committed.readBytes()))

        val generated = File(project, "build/generated/refract/screens/Debug/Screen.kt")
        run("generateDebugScreensRefract")
        committed.writeBytes(generated.readBytes())
        assertEquals(TaskOutcome.SUCCESS, run("checkDebugScreensRefract").task(":checkDebugScreensRefract")?.outcome)
    }

    private fun run(vararg arguments: String): BuildResult = runner(*arguments).build()

    private fun runAndFail(vararg arguments: String): BuildResult = runner(*arguments).buildAndFail()

    private fun runner(vararg arguments: String): GradleRunner = GradleRunner.create()
        .withProjectDir(project)
        .withArguments(*arguments)
        .withTestKitDir(File(System.getProperty("java.io.tmpdir"), "refract-gradle-test-kit"))
}
