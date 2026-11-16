// Generated from Fixtures/performance/compose-lazy-list/Input.swift by Refract.
// DO NOT EDIT. Hand-written expected pattern pending generator support.

package performance.composeLazyList

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable

@Immutable
public data class SettingItem(
    public val id: Int,
    public val title: String,
    public val enabled: Boolean,
)

@Composable
public fun SettingsList(items: List<SettingItem>) {
    LazyColumn {
        items(
            items = items,
            key = { item -> item.id },
            contentType = { "setting" },
        ) { item ->
            SettingRow(item = item)
        }
    }
}

@Composable
private fun SettingRow(item: SettingItem) {
    Row {
        Text(text = item.title)
        Text(text = if (item.enabled) "Enabled" else "Disabled")
    }
}
