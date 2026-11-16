// Generated from bench/android/SettingsScreen.swift by Refract.
// DO NOT EDIT. Contract stand-in until the generator produces this file.

package dev.refract.bench

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

@Composable
fun GeneratedSettingsScreen(model: SettingsModel) {
    Column(modifier = Modifier.fillMaxSize()) {
        Text(
            text = model.title.value,
            style = MaterialTheme.typography.headlineSmall,
            modifier = Modifier.padding(16.dp),
        )
        LazyColumn(modifier = Modifier.testTag("settings_list")) {
            items(
                items = model.rows.value,
                key = { row -> row.id },
                contentType = { "setting" },
            ) { row ->
                GeneratedSettingRow(model = model, row = row)
            }
        }
    }
}

@Composable
private fun GeneratedSettingRow(model: SettingsModel, row: SettingRow) {
    val onCheckedChange = remember(model, row.id) {
        { enabled: Boolean -> model.setEnabled(row.id, enabled) }
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .testTag("setting_row_${row.id}"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(text = row.title, style = MaterialTheme.typography.bodyLarge)
            Text(text = row.subtitle, style = MaterialTheme.typography.bodySmall)
        }
        Switch(
            checked = row.enabled,
            onCheckedChange = onCheckedChange,
            modifier = Modifier
                .testTag("setting_toggle_${row.id}")
                .semantics { contentDescription = row.title },
        )
    }
}
