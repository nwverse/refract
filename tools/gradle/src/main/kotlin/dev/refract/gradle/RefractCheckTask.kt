package dev.refract.gradle

import java.io.ByteArrayOutputStream
import org.gradle.api.GradleException
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.tasks.IgnoreEmptyDirectories
import org.gradle.api.tasks.InputDirectory
import org.gradle.api.tasks.Internal
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.TaskAction

abstract class RefractCheckTask : RefractTask() {
    @get:InputDirectory
    @get:IgnoreEmptyDirectories
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val committedOutputDirectory: DirectoryProperty

    @get:InputDirectory
    @get:IgnoreEmptyDirectories
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val harmonyCommittedOutputDirectory: DirectoryProperty

    @get:Internal
    abstract val verificationMarker: RegularFileProperty

    @TaskAction
    fun check() {
        val tool = executable.singleFile
        val arguments = mutableListOf("check")
        for (input in swiftInputs.files.sortedBy { it.absolutePath }) {
            arguments += listOf("--input", input.absolutePath)
        }
        mapping.orNull?.let { arguments += listOf("--mapping", it.asFile.absolutePath) }
        arguments += listOf(
            "--android-out", committedOutputDirectory.get().asFile.absolutePath,
            // #164 owns the CLI's read-only check contract; Android does not publish ArkTS here.
            "--harmony-out", harmonyCommittedOutputDirectory.get().asFile.absolutePath,
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
                "Refract committed-output check failed with exit code ${result.exitValue}. " +
                    "Regenerate with the same CLI version, review the generated diff and commit it.\n" +
                    output.toString(Charsets.UTF_8),
            )
        }
        verificationMarker.get().asFile.writeText("verified\n")
    }
}
