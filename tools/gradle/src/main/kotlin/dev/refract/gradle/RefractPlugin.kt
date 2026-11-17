package dev.refract.gradle

import com.android.build.api.variant.ApplicationAndroidComponentsExtension
import org.gradle.api.GradleException
import org.gradle.api.Plugin
import org.gradle.api.Project

class RefractPlugin : Plugin<Project> {
    override fun apply(project: Project) {
        project.plugins.apply("base")
        val extension = project.extensions.create("refract", RefractExtension::class.java)
        for (source in extension.sources) {
            if (source.inputs.files.isEmpty()) {
                throw GradleException("Refract source group '${source.name}' has no Swift inputs.")
            }
        }
        val executable = extension.executable.orElse(
            project.providers.environmentVariable("REFRACT_CLI_PATH").map { path ->
                project.layout.projectDirectory.file(path)
            },
        )

        project.pluginManager.withPlugin("com.android.application") {
            val androidComponents = project.extensions.getByType(ApplicationAndroidComponentsExtension::class.java)
            androidComponents.onVariants(androidComponents.selector().all()) { variant ->
                val suffix = variant.name.replaceFirstChar { it.uppercase() }
                val generate = project.tasks.register("generate${suffix}Refract") {
                    group = "refract"
                    description = "Generate all declared ${variant.name} Compose sources."
                }
                val check = project.tasks.register("check${suffix}Refract") {
                    group = "verification"
                    description = "Check committed Compose for all declared ${variant.name} sources."
                }
                project.tasks.named("check") { dependsOn(check) }

                for (source in extension.sources) {
                    source.committedOutputDirectory.convention(
                        project.layout.projectDirectory.dir("refract/generated/${source.name}"),
                    )
                    val taskName = "${suffix}${source.name.replaceFirstChar { it.uppercase() }}"
                    val generation = project.tasks.register(
                        "generate${taskName}Refract", RefractGenerateTask::class.java,
                    ) {
                        group = "refract"
                        description = "Generate ${source.name} Compose for ${variant.name}."
                        this.executable.from(executable)
                        swiftInputs.from(source.inputs)
                        mapping.convention(source.mapping)
                        resources.from(source.resources)
                        outputDirectory.convention(
                            project.layout.buildDirectory.dir("generated/refract/${source.name}/$suffix"),
                        )
                    }
                    variant.sources.java?.addGeneratedSourceDirectory(
                        generation, RefractGenerateTask::outputDirectory,
                    )
                    generate.configure { dependsOn(generation) }
                    val verification = project.tasks.register(
                        "check${taskName}Refract", RefractCheckTask::class.java,
                    ) {
                        group = "verification"
                        description = "Compare committed ${source.name} Compose with actual CLI generation."
                        this.executable.from(executable)
                        swiftInputs.from(source.inputs)
                        mapping.convention(source.mapping)
                        resources.from(source.resources)
                        committedOutputDirectory.convention(source.committedOutputDirectory)
                        harmonyCommittedOutputDirectory.convention(source.harmonyCommittedOutputDirectory)
                        verificationMarker.convention(
                            project.layout.buildDirectory.file("refract/check/$taskName/verified.txt"),
                        )
                    }
                    check.configure { dependsOn(verification) }
                }
            }
        }
        // Plain JVM consumers can use the same task type explicitly; Android uses variant wiring above.
        project.tasks.register("generateRefract") {
            group = "refract"
            description = "Generate Android sources for every Android application variant."
            dependsOn(project.tasks.matching { it.name.startsWith("generate") && it.name.endsWith("Refract") && it.name != "generateRefract" })
        }
        project.tasks.register("checkRefract") {
            group = "verification"
            description = "Check Android sources for every Android application variant."
            dependsOn(project.tasks.matching { it.name.startsWith("check") && it.name.endsWith("Refract") && it.name != "checkRefract" })
        }
    }
}
