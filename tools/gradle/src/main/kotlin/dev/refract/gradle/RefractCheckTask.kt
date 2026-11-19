package dev.refract.gradle

import org.gradle.api.GradleException
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.tasks.IgnoreEmptyDirectories
import org.gradle.api.tasks.InputDirectory
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

    @TaskAction
    fun check() {
        val tool = validatedTool()
        val arguments = mutableListOf("check")
        for (input in swiftInputs.files.sortedBy { it.absolutePath }) {
            arguments += listOf("--input", input.absolutePath)
        }
        mapping.orNull?.let { arguments += listOf("--mapping", it.asFile.absolutePath) }
        arguments += listOf(
            "--android-out", committedOutputDirectory.get().asFile.absolutePath,
            "--harmony-out", harmonyCommittedOutputDirectory.get().asFile.absolutePath,
        )
        val output = runTool(tool, arguments)
        if (output.exitCode != 0) {
            throw GradleException(
                "Refract committed-output check failed with exit code ${output.exitCode}. " +
                    "Publish with the same CLI version, review the generated diff and commit it.\n${output.text}",
            )
        }
    }
}
