package com.example.refract.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.example.refract.R
import refract.generated.SettingsModel

/** The native original remains callable after generated settings is adopted. */
@Composable
fun HandWrittenSettingsScreen(
    model: SettingsModel,
    notificationsEnabled: Boolean,
    onNotificationsEnabledChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    var displayName by remember { mutableStateOf("") }
    Column(modifier = modifier) {
        Text(stringResource(R.string.settings_profile), style = MaterialTheme.typography.titleLarge)
        Text(model.title.value)
        TextField(
            value = displayName,
            onValueChange = { displayName = it },
            label = { Text(stringResource(R.string.settings_display_name)) },
        )
        Text(stringResource(R.string.settings_preferences))
        Switch(checked = notificationsEnabled, onCheckedChange = onNotificationsEnabledChange)
        Button(onClick = { model.save() }) {
            Text(stringResource(R.string.settings_save))
        }
    }
}
