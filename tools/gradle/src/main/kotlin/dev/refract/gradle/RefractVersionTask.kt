package dev.refract.gradle

import java.nio.file.Files
import javax.inject.Inject
import org.gradle.api.DefaultTask
import org.gradle.api.GradleException
import org.gradle.api.file.ConfigurableFileCollection
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.provider.Property
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.InputFiles
import org.gradle.api.tasks.OutputFile
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.TaskAction
import org.gradle.process.ExecOperations

/** Validates the host tool before any generate, check or publish action. */
abstract class RefractVersionTask : DefaultTask() {
    @get:InputFiles
    @get:PathSensitive(PathSensitivity.NONE)
    abstract val executable: ConfigurableFileCollection

    /** The exact `refract --version` line, including the source revision. */
    @get:Input
    abstract val requiredVersion: Property<String>

    @get:OutputFile
    abstract val report: RegularFileProperty

    @get:Inject
    protected abstract val execOperations: ExecOperations

    @TaskAction
    fun verify() {
        val tool = executable.singleFile
        if (!tool.isFile || !Files.isExecutable(tool.toPath())) {
            throw GradleException("Refract CLI is not an executable file: ${tool.path}")
        }
        val expected = requiredVersion.get().trim()
        if (expected.isEmpty()) {
            throw GradleException(
                "Set refract.requiredVersion to the exact `refract --version` output, " +
                    "including the CLI source revision from its versioned package.",
            )
        }
        val output = java.io.ByteArrayOutputStream()
        val result = execOperations.exec {
            setExecutable(tool.absolutePath)
            setArgs(listOf("--version"))
            setWorkingDir(project.projectDir)
            setStandardOutput(output)
            setErrorOutput(output)
            setIgnoreExitValue(true)
        }
        val actual = output.toString(Charsets.UTF_8).trim()
        if (result.exitValue != 0 || actual != expected) {
            throw GradleException(
                "Refract CLI version mismatch. Expected `$expected`, actual `$actual` " +
                    "(exit ${result.exitValue}). Select the explicitly versioned CLI for this consumer; " +
                    "no sources were generated, checked or published.",
            )
        }
        val destination = report.get().asFile
        destination.parentFile.mkdirs()
        destination.writeText(actual + "\n")
    }
}
