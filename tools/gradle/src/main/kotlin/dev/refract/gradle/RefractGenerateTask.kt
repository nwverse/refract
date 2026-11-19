package dev.refract.gradle

import java.io.File
import org.gradle.api.GradleException
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.TaskAction

abstract class RefractGenerateTask : RefractTask() {
    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @get:OutputDirectory
    abstract val harmonyOutputDirectory: DirectoryProperty

    @TaskAction
    fun generate() {
        val destination = outputDirectory.get().asFile
        val harmonyDestination = harmonyOutputDirectory.get().asFile
        val buildRoot = project.layout.buildDirectory.get().asFile.canonicalFile
        for (output in listOf(destination, harmonyDestination)) {
            val ownedDestination = output.canonicalFile
            if (!ownedDestination.toPath().startsWith(buildRoot.toPath()) || ownedDestination == buildRoot) {
                throw GradleException(
                    "Refract build output must be a dedicated directory below the Gradle build directory: " +
                        output.path + ". Use publish<Variant>Refract to update reviewed source explicitly.",
                )
            }
        }
        if (destination.canonicalFile == harmonyDestination.canonicalFile) {
            throw GradleException("Refract Android and HarmonyOS build output directories must be separate.")
        }

        val staging = File(temporaryDir, "cli")
        project.delete(staging)
        generateInto(staging)
        // Only build-owned output is replaceable, and only after complete dual-backend generation succeeds.
        project.delete(destination, harmonyDestination)
        project.copy {
            from(File(staging, "android"))
            into(destination)
        }
        project.copy {
            from(File(staging, "harmony"))
            into(harmonyDestination)
        }
    }
}
