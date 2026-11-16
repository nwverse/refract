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
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

@Composable
fun ReferenceSettingsScreen(model: SettingsModel) {
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
                ReferenceSettingRow(
                    title = row.title,
                    subtitle = row.subtitle,
                    checked = row.enabled,
                    onCheckedChange = { enabled -> model.setEnabled(row.id, enabled) },
                    modifier = Modifier.testTag("setting_row_${row.id}"),
                )
            }
        }
    }
}

@Composable
private fun ReferenceSettingRow(
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(text = title, style = MaterialTheme.typography.bodyLarge)
            Text(text = subtitle, style = MaterialTheme.typography.bodySmall)
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            modifier = Modifier
                .testTag("setting_toggle_${rowNumber(title)}")
                .semantics { contentDescription = title },
        )
    }
}

private fun rowNumber(title: String): String = title.substringAfter(' ')
