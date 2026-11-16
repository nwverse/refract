package com.example.refract.settings

import androidx.compose.runtime.State
import androidx.compose.runtime.mutableStateOf
import refract.generated.SettingsModel

/** Existing native state implements the generated protocol; no adapter is required. */
class AppSettingsModel(initialTitle: String) : SettingsModel {
    private val titleState = mutableStateOf(initialTitle)

    override val title: State<String>
        get() = titleState

    override fun save() {
        // The native application owns persistence and side effects.
    }
}
