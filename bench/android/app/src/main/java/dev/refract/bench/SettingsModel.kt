package dev.refract.bench

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableStateOf

@Immutable
data class SettingRow(
    val id: Int,
    val title: String,
    val subtitle: String,
    val enabled: Boolean,
)

interface SettingsModel {
    val title: State<String>
    val rows: State<List<SettingRow>>

    fun setEnabled(id: Int, value: Boolean)
}

class BenchmarkSettingsModel : SettingsModel {
    override val title = mutableStateOf("Native settings")
    override val rows = mutableStateOf(
        List(ROW_COUNT) { index ->
            SettingRow(
                id = index,
                title = "Setting $index",
                subtitle = "Native setting row $index",
                enabled = index % 2 == 0,
            )
        },
    )

    override fun setEnabled(id: Int, value: Boolean) {
        rows.value = rows.value.map { row ->
            if (row.id == id) row.copy(enabled = value) else row
        }
    }

    companion object {
        const val ROW_COUNT = 200
    }
}

enum class ScreenVariant {
    Generated,
    Reference,
}
