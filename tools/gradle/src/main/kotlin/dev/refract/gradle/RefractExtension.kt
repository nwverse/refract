package dev.refract.gradle

import javax.inject.Inject
import org.gradle.api.Named
import org.gradle.api.file.ConfigurableFileCollection
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.file.RegularFileProperty

/** Build-only configuration. No property is added to an application's runtime dependencies. */
interface RefractExtension {
    /** A version-matched CLI executable. REFRACT_CLI_PATH is the environment fallback. */
    val executable: RegularFileProperty

    /** Explicit, independently mapped groups of Swift files. */
    val sources: org.gradle.api.NamedDomainObjectContainer<RefractSourceSet>
}

abstract class RefractSourceSet @Inject constructor(private val name: String) : Named {
    override fun getName(): String = name

    /** Cross-file Swift inputs must all be declared; no implicit directory discovery occurs. */
    abstract val inputs: ConfigurableFileCollection

    /** Optional refract.json. Omission preserves the CLI's unmapped generation behavior. */
    abstract val mapping: RegularFileProperty

    /** Every native resource catalog read through this group's mapping, on both platforms. */
    abstract val resources: ConfigurableFileCollection

    /** Reviewed Kotlin for this group, compared by checkRefract and excluded from default Android source. */
    abstract val committedOutputDirectory: DirectoryProperty

    /** Reviewed ArkTS for this group; supplied to the CLI check, never published into an Android app. */
    abstract val harmonyCommittedOutputDirectory: DirectoryProperty
}
