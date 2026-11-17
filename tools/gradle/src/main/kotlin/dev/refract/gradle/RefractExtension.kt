package dev.refract.gradle

import javax.inject.Inject
import org.gradle.api.Named
import org.gradle.api.NamedDomainObjectContainer
import org.gradle.api.file.ConfigurableFileCollection
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.provider.Property

/** Build-only configuration. No property is added to an application's runtime dependencies. */
interface RefractExtension {
    /** A version-matched CLI executable. REFRACT_CLI_PATH is the environment fallback. */
    val executable: RegularFileProperty

    /** The exact CLI version string, including its source revision, required on this build host. */
    val requiredVersion: Property<String>

    /** Explicit, independently mapped groups of Swift files. */
    val sources: NamedDomainObjectContainer<RefractSourceSet>

    /** Named source-generation configurations; these do not change the generated source semantics. */
    val configurations: NamedDomainObjectContainer<RefractGenerationConfiguration>
}

abstract class RefractSourceSet @Inject constructor(private val name: String) : Named {
    override fun getName(): String = name

    /** Cross-file Swift inputs must all be declared; no implicit directory discovery occurs. */
    abstract val inputs: ConfigurableFileCollection

    /** Optional refract.json. Omission preserves the CLI's unmapped generation behavior. */
    abstract val mapping: RegularFileProperty

    /** Every native resource catalog read through this group's mapping, on both platforms. */
    abstract val resources: ConfigurableFileCollection

    /** Existing production Kotlin directory, used when no configurations are declared. */
    abstract val committedOutputDirectory: DirectoryProperty

    /** Existing production ArkTS directory, used when no configurations are declared. */
    abstract val harmonyCommittedOutputDirectory: DirectoryProperty
}

abstract class RefractGenerationConfiguration @Inject constructor(private val name: String) : Named {
    override fun getName(): String = name

    init {
        require(name.matches(Regex("[a-z][A-Za-z0-9]*"))) {
            "Refract configuration '$name' must start with a lowercase letter and contain only ASCII letters/digits."
        }
        require(name != "main" && name != "test") {
            "Refract configuration '$name' is reserved for the Android source-set integration."
        }
    }

    /** A named Android build variant explicitly selects this configuration. */
    abstract val androidVariant: Property<String>

    /** Reviewed Kotlin for this configuration, compared by checkRefract and published only explicitly. */
    abstract val androidOutputDirectory: DirectoryProperty

    /** Reviewed ArkTS for this configuration; never published into an Android app by the normal build. */
    abstract val harmonyOutputDirectory: DirectoryProperty
}
