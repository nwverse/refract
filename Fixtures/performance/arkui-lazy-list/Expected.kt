// Generated from Fixtures/performance/arkui-lazy-list/Input.swift by Refract.
// DO NOT EDIT. Hand-written expected pattern pending generator support.

package performance.arkuiLazyList

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.State
import androidx.compose.ui.Modifier

@Immutable
public data class SettingItem(
    public val id: Int,
    public val title: String,
    public val enabled: Boolean,
)

public interface SettingsListModel {
    public val items: State<List<SettingItem>>
}

@Composable
public fun SettingsList(
    model: SettingsListModel,
    modifier: Modifier = Modifier,
) {
    LazyColumn(modifier = modifier) {
        items(
            items = model.items.value,
            key = { item -> item.id },
            contentType = { "setting" },
        ) { item ->
            Row {
                Text(text = item.title)
                Text(text = if (item.enabled) "Enabled" else "Disabled")
            }
        }
    }
}
