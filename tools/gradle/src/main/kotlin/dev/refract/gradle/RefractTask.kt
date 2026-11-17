package dev.refract.gradle

import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.file.Files
import javax.inject.Inject
import org.gradle.api.DefaultTask
import org.gradle.api.GradleException
import org.gradle.api.file.ConfigurableFileCollection
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.tasks.IgnoreEmptyDirectories
import org.gradle.api.tasks.InputFile
import org.gradle.api.tasks.InputFiles
import org.gradle.api.tasks.Internal
import org.gradle.api.tasks.Optional
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.gradle.process.ExecOperations

abstract class RefractTask : DefaultTask() {
    @get:InputFiles
    @get:PathSensitive(PathSensitivity.NONE)
    abstract val executable: ConfigurableFileCollection

    @get:InputFiles
    @get:IgnoreEmptyDirectories
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val swiftInputs: ConfigurableFileCollection

    @get:Optional
    @get:InputFile
    @get:PathSensitive(PathSensitivity.NONE)
    abstract val mapping: RegularFileProperty

    @get:InputFiles
    @get:IgnoreEmptyDirectories
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val resources: ConfigurableFileCollection

    @get:Inject
    protected abstract val execOperations: ExecOperations

    protected fun generateInto(staging: File) {
        val tool = executable.singleFile
        if (!tool.isFile || !Files.isExecutable(tool.toPath())) {
            throw GradleException(
                "Refract CLI is not an executable file: ${tool.path}. " +
                    "Set refract.executable or REFRACT_CLI_PATH to a version-matched executable " +
                    "built from the intended Refract revision.",
            )
        }
        val swiftFiles = swiftInputs.files.sortedBy { it.absolutePath }
        if (swiftFiles.isEmpty()) {
            throw GradleException("Refract has no Swift inputs. Declare at least one file in the refract.sources input group.")
        }
        for (input in swiftFiles) {
            if (!input.isFile || input.extension != "swift") {
                throw GradleException("Refract input must be a readable .swift file: ${input.path}")
            }
        }
        for (resource in resources.files) {
            if (!resource.isFile) {
                throw GradleException("Refract resource catalog is not a file: ${resource.path}")
            }
        }

        val android = File(staging, "android")
        val harmony = File(staging, "harmony")
        android.mkdirs()
        harmony.mkdirs()
        val arguments = mutableListOf("generate")
        for (input in swiftFiles) {
            arguments += listOf("--input", input.absolutePath)
        }
        mapping.orNull?.let { arguments += listOf("--mapping", it.asFile.absolutePath) }
        arguments += listOf(
            "--android-out", android.absolutePath,
            // The current CLI validates both backends. Do not publish ArkTS from an Android Gradle project.
            "--harmony-out", harmony.absolutePath,
        )

        val output = ByteArrayOutputStream()
        val result = execOperations.exec {
            setExecutable(tool.absolutePath)
            setArgs(arguments)
            setWorkingDir(project.projectDir)
            setStandardOutput(output)
            setErrorOutput(output)
            setIgnoreExitValue(true)
        }
        if (result.exitValue != 0) {
            throw GradleException(
                "Refract generation failed with exit code ${result.exitValue}; " +
                    "existing generated and committed outputs were not changed.\n${output.toString(Charsets.UTF_8)}",
            )
        }
        verifyGeneratedDirectory(android, expectedFilenames(".kt"), "staged Android")
    }

    protected fun expectedFilenames(extension: String): Set<String> =
        swiftInputs.files.map { it.nameWithoutExtension + extension }.toSet()

    protected fun verifyGeneratedDirectory(directory: File, expected: Set<String>, label: String) {
        val actual = directory.listFiles().orEmpty()
        if (actual.any { !it.isFile }) {
            throw GradleException("Refract $label output contains an unexpected directory: ${directory.path}")
        }
        val filenames = actual.map { it.name }.toSet()
        val missing = expected - filenames
        val unexpected = filenames - expected
        if (missing.isNotEmpty() || unexpected.isNotEmpty()) {
            throw GradleException(
                "Refract $label output is incomplete. Missing: ${missing.sorted()}; " +
                    "unexpected: ${unexpected.sorted()}. Check duplicate input basenames and CLI diagnostics.",
            )
        }
    }
}
