pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

// The example opts into the repository's build-only plugin; ordinary consumers use a published plugin.
includeBuild("../../tools/gradle")

rootProject.name = "RefractExample"
include(":app")
include(":fixtures")
