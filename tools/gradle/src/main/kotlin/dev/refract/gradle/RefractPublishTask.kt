package dev.refract.gradle

import java.io.File
import java.nio.file.Files
import org.gradle.api.GradleException
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.provider.Property
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.Internal
import org.gradle.api.tasks.TaskAction

/** Explicit publication of both native backends; ordinary builds never write these source directories. */
abstract class RefractPublishTask : RefractTask() {
    @get:Input
    abstract val configurationName: Property<String>

    @get:Internal
    abstract val androidDestination: DirectoryProperty

    @get:Internal
    abstract val harmonyDestination: DirectoryProperty

    /** Build-only scratch space; reviewed outputs are external effects of this explicit command. */
    @get:Internal
    abstract val stagingDirectory: DirectoryProperty

    @TaskAction
    fun publish() {
        val projectRoot = project.layout.projectDirectory.asFile.canonicalFile
        val requestedDestinations = listOf(androidDestination, harmonyDestination).map { it.get().asFile }
        val destinations = requestedDestinations.map { it.canonicalFile }
        for ((index, destination) in destinations.withIndex()) {
            if (Files.isSymbolicLink(requestedDestinations[index].toPath())) {
                throw GradleException("Refract reviewed output cannot be a symbolic link: ${destination.path}")
            }
            if (!destination.toPath().startsWith(projectRoot.toPath()) || destination == projectRoot) {
                throw GradleException(
                    "Refract ${configurationName.get()} reviewed output must be a dedicated directory " +
                        "inside the consumer project: ${destination.path}",
                )
            }
        }
        if (destinations[0] == destinations[1]) {
            throw GradleException(
                "Refract ${configurationName.get()} Android and HarmonyOS reviewed outputs must be separate.",
            )
        }

        val staging = stagingDirectory.get().asFile
        project.delete(staging)
        generateInto(staging)
        // Refract owns this complete source set. Refuse unrelated files rather than silently discarding them.
        for ((backend, destination) in destinations.withIndex()) {
            val extension = if (backend == 0) ".kt" else ".ets"
            val label = if (backend == 0) "Android" else "HarmonyOS"
            if (destination.exists()) {
                verifyGeneratedDirectory(destination, expectedFilenames(extension), "reviewed $label")
            }
            if (destination.exists() && !destination.isDirectory) {
                throw GradleException("Refract reviewed output is not a directory: ${destination.path}")
            }
        }

        // Reuse the CLI's checked dual-backend writer; no second publication or rollback policy.
        generateFiles(destinations[0], destinations[1])
    }
}
