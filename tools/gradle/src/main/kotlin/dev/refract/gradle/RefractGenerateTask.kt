package dev.refract.gradle

import java.io.File
import org.gradle.api.GradleException
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.TaskAction

abstract class RefractGenerateTask : RefractTask() {
    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @TaskAction
    fun generate() {
        val destination = outputDirectory.get().asFile
        val buildRoot = project.layout.buildDirectory.get().asFile.canonicalFile
        val ownedDestination = destination.canonicalFile
        if (!ownedDestination.toPath().startsWith(buildRoot.toPath()) || ownedDestination == buildRoot) {
            throw GradleException(
                "Refract outputDirectory must be a dedicated directory below the Gradle build directory. " +
                    "Keep reviewed source in committedOutputDirectory; this task never publishes into the source tree.",
            )
        }

        val staging = File(temporaryDir, "cli")
        project.delete(staging)
        generateInto(staging)
        // Only build-owned output is replaceable, and only after the complete CLI invocation succeeds.
        project.delete(destination)
        project.copy {
            from(File(staging, "android"))
            into(destination)
        }
    }
}
