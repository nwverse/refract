// Generated from Fixtures/performance/arkui-reuse/Input.swift by Refract.
// DO NOT EDIT. Hand-written expected pattern pending generator support.

package performance.arkuiReuse

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable

@Composable
public fun SettingRowView(
    title: String,
    subtitle: String,
    enabled: Boolean,
    onEnabledChange: (Boolean) -> Unit,
) {
    Row {
        Column {
            Text(text = title)
            Text(text = subtitle)
        }
        Switch(checked = enabled, onCheckedChange = onEnabledChange)
    }
}
