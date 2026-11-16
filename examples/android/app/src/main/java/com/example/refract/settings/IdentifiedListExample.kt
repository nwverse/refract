package com.example.refract.settings

import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableStateOf
import refract.generated.IdentifiedList
import refract.generated.SettingItem
import refract.generated.SettingsListModel

private class ExampleSettingsListModel : SettingsListModel {
    override val items: State<List<SettingItem>> = mutableStateOf(
        listOf(
            SettingItem(id = "profile", title = "Profile"),
            SettingItem(id = "notifications", title = "Notifications"),
        ),
    )
}

@Composable
fun IdentifiedListExample() {
    IdentifiedList(model = ExampleSettingsListModel())
}
