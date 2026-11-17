package dev.refract.gradle

import com.android.build.api.variant.AndroidComponentsExtension
import org.gradle.api.GradleException
import org.gradle.api.NamedDomainObjectContainer
import org.gradle.api.file.Directory
import org.gradle.api.provider.Provider
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
        val version = project.tasks.register("verifyRefractVersion", RefractVersionTask::class.java) {
            group = "verification"
            description = "Verify the exact version and source revision of the explicit host CLI."
            this.executable.from(executable)
            requiredVersion.convention(extension.requiredVersion)
            report.convention(project.layout.buildDirectory.file("refract/version.txt"))
        }

        project.pluginManager.withPlugin("com.android.application") {
            val androidComponents = project.extensions.getByType(AndroidComponentsExtension::class.java)
            androidComponents.onVariants(androidComponents.selector().all()) { variant ->
                val configurations = extension.configurations
                val legacyDefaults = configurations.isEmpty()
                if (legacyDefaults) {
                    registerDefaults(project, configurations, extension.sources)
                }
                val selected = configurations.filter { it.androidVariant.orNull == variant.name }
                if (selected.size != 1) {
                    throw GradleException(
                        "Android variant '${variant.name}' must select exactly one Refract generation " +
                            "configuration with androidVariant = \"${variant.name}\". Found ${selected.size}. " +
                            "Do not infer a production generation configuration from a build environment.",
                    )
                }
                val configuration = selected.single()
                val androidRoots = mutableMapOf<String, String>()
                val harmonyRoots = mutableMapOf<String, String>()
                for (other in configurations) {
                    for ((kind, roots, directory) in listOf(
                        Triple("Android", androidRoots, other.androidOutputDirectory),
                        Triple("HarmonyOS", harmonyRoots, other.harmonyOutputDirectory),
                    )) {
                        if (!directory.isPresent) {
                            throw GradleException(
                                "Refract configuration '${other.name}' must set its $kind output root explicitly.",
                            )
                        }
                        val path = directory.get().asFile.canonicalPath
                        val previous = roots.put(path, other.name)
                        if (previous != null && previous != other.name &&
                            setOf(previous, other.name) != setOf("debug", "release")
                        ) {
                            throw GradleException(
                                "Refract configurations '$previous' and '${other.name}' share the $kind " +
                                    "reviewed output root '$path'. Give each configuration a separate root; " +
                                    "a generation configuration cannot toggle production output in place.",
                            )
                        }
                    }
                }
                val suffix = variant.name.replaceFirstChar { it.uppercase() }
                val generate = project.tasks.register("generate${suffix}Refract") {
                    group = "refract"
                    description = "Generate all ${configuration.name} Compose and ArkTS sources."
                    dependsOn(version)
                }
                val check = project.tasks.register("check${suffix}Refract") {
                    group = "verification"
                    description = "Check committed Kotlin and ArkTS for the ${configuration.name} configuration."
                    dependsOn(version)
                }
                project.tasks.named("check") { dependsOn(check) }
                val publish = project.tasks.register("publish${suffix}Refract") {
                    group = "refract"
                    description = "Explicitly publish reviewed Kotlin and ArkTS for ${configuration.name}."
                    dependsOn(version)
                }

                for (source in extension.sources) {
                    val taskName = "${suffix}${source.name.replaceFirstChar { it.uppercase() }}"
                    val generation = project.tasks.register(
                        "generate${taskName}Refract", RefractGenerateTask::class.java,
                    ) {
                        group = "refract"
                        description = "Generate ${source.name} for the ${configuration.name} configuration."
                        this.executable.from(executable)
                        swiftInputs.from(source.inputs)
                        mapping.convention(source.mapping)
                        resources.from(source.resources)
                        outputDirectory.convention(
                            project.layout.buildDirectory.dir("generated/refract/${configuration.name}/${source.name}/android"),
                        )
                        harmonyOutputDirectory.convention(
                            project.layout.buildDirectory.dir("generated/refract/${configuration.name}/${source.name}/harmony"),
                        )
                        dependsOn(version)
                    }
                    variant.sources.java?.addGeneratedSourceDirectory(
                        generation, RefractGenerateTask::outputDirectory,
                    )
                    generate.configure { dependsOn(generation) }
                    val verification = project.tasks.register(
                        "check${taskName}Refract", RefractCheckTask::class.java,
                    ) {
                        group = "verification"
                        description = "Compare committed ${source.name} Kotlin/ArkTS with actual CLI generation."
                        this.executable.from(executable)
                        swiftInputs.from(source.inputs)
                        mapping.convention(source.mapping)
                        resources.from(source.resources)
                        committedOutputDirectory.convention(
                            if (legacyDefaults) {
                                configuration.androidOutputDirectory.map { it.dir(source.name) }
                            } else {
                                configuration.androidOutputDirectory.map { it.dir(source.name).dir("android") }
                            },
                        )
                        harmonyCommittedOutputDirectory.convention(
                            if (legacyDefaults) {
                                configuration.harmonyOutputDirectory
                            } else {
                                configuration.harmonyOutputDirectory.map { it.dir(source.name).dir("harmony") }
                            },
                        )
                        dependsOn(version)
                    }
                    check.configure { dependsOn(verification) }
                    val publication = project.tasks.register(
                        "publish${taskName}Refract", RefractPublishTask::class.java,
                    ) {
                        group = "refract"
                        description = "Explicitly publish the ${source.name} Kotlin/ArkTS source set."
                        this.executable.from(executable)
                        swiftInputs.from(source.inputs)
                        mapping.convention(source.mapping)
                        resources.from(source.resources)
                        configurationName.convention(configuration.name)
                        androidDestination.convention(
                            if (legacyDefaults) {
                                configuration.androidOutputDirectory.map { it.dir(source.name) }
                            } else {
                                configuration.androidOutputDirectory.map { it.dir(source.name).dir("android") }
                            },
                        )
                        harmonyDestination.convention(
                            if (legacyDefaults) {
                                configuration.harmonyOutputDirectory
                            } else {
                                configuration.harmonyOutputDirectory.map { it.dir(source.name).dir("harmony") }
                            },
                        )
                        stagingDirectory.convention(
                            project.layout.buildDirectory.dir("refract/publish/${configuration.name}/${source.name}"),
                        )
                        dependsOn(version)
                    }
                    publish.configure { dependsOn(publication) }
                }
            }
        }
        project.tasks.register("generateRefract") {
            group = "refract"
            description = "Generate sources for every explicitly bound Android application variant."
            dependsOn(
                project.tasks.matching {
                    it.name.startsWith("generate") && it.name.endsWith("Refract") && it.name != "generateRefract"
                },
            )
        }
        project.tasks.register("checkRefract") {
            group = "verification"
            description = "Check sources for every explicitly bound Android application variant."
            dependsOn(
                project.tasks.matching {
                    it.name.startsWith("check") && it.name.endsWith("Refract") && it.name != "checkRefract"
                },
            )
        }
    }

    /** Existing consumers retain their production defaults until they explicitly bind another configuration. */
    private fun registerDefaults(
        project: Project,
        configurations: NamedDomainObjectContainer<RefractGenerationConfiguration>,
        sources: NamedDomainObjectContainer<RefractSourceSet>,
    ) {
        for (name in listOf("debug", "release")) {
            configurations.register(name) {
                androidVariant.set(name)
            }
        }
        if (sources.size == 1) {
            for (configuration in configurations) {
                val defaultRoot = project.layout.projectDirectory.dir("refract/generated")
                val defaultHarmony: Provider<Directory> = project.provider {
                    defaultRoot.dir("screens/harmony")
                }
                configuration.androidOutputDirectory.convention(defaultRoot)
                configuration.harmonyOutputDirectory.convention(defaultHarmony)
            }
        }
    }
}
