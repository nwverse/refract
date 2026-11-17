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
                    resources.from(layout.projectDirectory.file("res/values/strings.xml"))
                    committedOutputDirectory.set(layout.projectDirectory.dir("committed"))
                    harmonyCommittedOutputDirectory.set(layout.projectDirectory.dir("harmony"))
                }
            }
            android {
                namespace = "example.consumer"
                compileSdk = 37
                compileSdkMinor = 2
                defaultConfig { minSdk = 26 }
                buildFeatures { compose = true }
                sourceSets.getByName("main").res.directories.add("res")
            }
            dependencies {
                implementation(platform("androidx.compose:compose-bom:2026.09.00"))
                implementation("androidx.compose.ui:ui")
                implementation("androidx.compose.material3:material3")
            }
            tasks.register("sharedGeneration", RefractGenerateTask::class) {
                executable.from(refract.executable)
                swiftInputs.from(layout.projectDirectory.file("Screen.swift"))
                mapping.set(layout.projectDirectory.file("refract.json"))
                resources.from(layout.projectDirectory.file("res/values/strings.xml"))
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
                "resources": { "className": "example.consumer.R", "catalog": "res/values/strings.xml", "strings": { "example.hello": "example_hello" } }
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
        File(project, "res/values").mkdirs()
        File(project, "res/values/strings.xml").writeText(
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
        val output = File(project, "build/generated/java/generateDebugScreensRefract/Screen.kt")
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
        File(project, "custom.gradle").writeText(
            """
            refract.executable.set(layout.projectDirectory.file("missing-cli"))
            """.trimIndent(),
        )
        File(project, "build.gradle.kts").appendText(
            "\napply(from = \"custom.gradle\")\n",
        )
        val missing = runAndFail("generateDebugScreensRefract")
        assertTrue(missing.output, missing.output.contains("Refract CLI is not an executable file"))
        assertFalse(File(project, "build/generated/java/generateDebugScreensRefract/Screen.kt").exists())

        File(project, "custom.gradle").writeText("")
        assertEquals(TaskOutcome.SUCCESS, run("generateDebugScreensRefract").task(":generateDebugScreensRefract")?.outcome)
        File(project, "Screen.swift").appendText("\n// Restore the valid CLI.\n")
        val generated = run("generateDebugScreensRefract")
        assertEquals(generated.output, TaskOutcome.SUCCESS, generated.task(":generateDebugScreensRefract")?.outcome)
        val previous = requireNotNull(File(project, "build/generated/java/generateDebugScreensRefract/Screen.kt").takeIf { it.isFile }) {
            "Expected successful generation output. Gradle output:\n${generated.output}"
        }.readBytes()
        val output = File(project, "build/generated/java/generateDebugScreensRefract/Screen.kt")
        File(project, "Screen.swift").appendText("\nthis is not Swift\n")
        val invalid = runAndFail("generateDebugScreensRefract")
        assertTrue(invalid.output, invalid.output.contains("existing generated and committed outputs were not changed"))
        assertTrue(previous.contentEquals(output.readBytes()))
    }

    @Test
    fun sharedTaskInvalidatesForSwiftMappingAndResourceChanges() {
        assertEquals(TaskOutcome.SUCCESS, run("sharedGeneration").task(":sharedGeneration")?.outcome)
        assertEquals(TaskOutcome.UP_TO_DATE, run("sharedGeneration").task(":sharedGeneration")?.outcome)
        for (path in listOf("Screen.swift", "refract.json", "res/values/strings.xml")) {
            File(project, path).appendText(if (path.endsWith(".json")) "\n" else "\n// input changed\n")
            assertEquals(path, TaskOutcome.SUCCESS, run("sharedGeneration").task(":sharedGeneration")?.outcome)
            assertEquals(path, TaskOutcome.UP_TO_DATE, run("sharedGeneration").task(":sharedGeneration")?.outcome)
        }
    }

    @Test
    fun staleOutputFailsThroughTheRealCliWithoutWriting() {
        val committed = File(project, "committed/Screen.kt")
        val harmony = File(project, "harmony/Screen.ets")
        harmony.parentFile.mkdirs()
        harmony.writeText("stale\n")
        committed.parentFile.mkdirs()
        committed.writeText("stale\n")
        val before = committed.readBytes()
        val harmonyBefore = harmony.readBytes()
        val failure = runAndFail("checkDebugScreensRefract")
        assertTrue(failure.output, failure.output.contains("Refract committed-output check failed"))
        assertTrue(before.contentEquals(committed.readBytes()))
        assertTrue(harmonyBefore.contentEquals(harmony.readBytes()))

        val generated = File(project, "build/generated/java/generateDebugScreensRefract/Screen.kt")
        run("generateDebugScreensRefract")
        committed.writeBytes(generated.readBytes())
        harmony.writeBytes(File(project, "build/tmp/generateDebugScreensRefract/cli/harmony/Screen.ets").readBytes())
        assertEquals(TaskOutcome.SUCCESS, run("checkDebugScreensRefract").task(":checkDebugScreensRefract")?.outcome)
    }

    private fun run(vararg arguments: String): BuildResult = runner(*arguments).build()

    private fun runAndFail(vararg arguments: String): BuildResult = runner(*arguments).buildAndFail()

    private fun runner(vararg arguments: String): GradleRunner = GradleRunner.create()
        .withProjectDir(project)
        .withArguments(*arguments)
        .withTestKitDir(File(System.getProperty("java.io.tmpdir"), "refract-gradle-test-kit"))
}
