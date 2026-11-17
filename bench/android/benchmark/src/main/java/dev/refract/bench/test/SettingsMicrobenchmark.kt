package dev.refract.bench.test

import androidx.benchmark.junit4.BenchmarkRule
import androidx.benchmark.junit4.measureRepeated
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.platform.testTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.refract.bench.BenchmarkSettingsModel
import dev.refract.bench.GeneratedSettingRow
import dev.refract.bench.ReferenceSettingRow
import dev.refract.bench.SettingRow
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SettingsMicrobenchmark {
    @get:Rule
    val benchmarkRule = BenchmarkRule()

    private val model = BenchmarkSettingsModel()
    private val revision = mutableStateOf(0)

    @get:Rule
    val composeRule = createAndroidComposeRule<MicrobenchmarkActivity>()

    @Test
    fun generatedRowRecomposition() = rowRecomposition { model, row ->
        GeneratedSettingRow(row = row, model = model)
    }

    @Test
    fun referenceRowRecomposition() = rowRecomposition { model, row ->
        ReferenceSettingRow(
            title = row.title,
            subtitle = row.subtitle,
            checked = row.enabled,
            onCheckedChange = { enabled -> model.setEnabled(row.id, enabled) },
            modifier = androidx.compose.ui.Modifier.testTag("setting_row_0"),
        )
    }

    private fun rowRecomposition(row: @androidx.compose.runtime.Composable (BenchmarkSettingsModel, SettingRow) -> Unit) {
        model.setEnabled(0, false)
        composeRule.setContent {
            MaterialTheme {
                row(model, model.rows.value.first())
            }
        }
        composeRule.waitForIdle()
        composeRule.mainClock.autoAdvance = false
        benchmarkRule.measureRepeated {
            runWithMeasurementDisabled {
                composeRule.runOnIdle {
                    revision.value += 1
                    model.setEnabled(0, revision.value % 2 == 0)
                }
            }
            composeRule.mainClock.advanceTimeByFrame()
            composeRule.waitForIdle()
        }
        composeRule.mainClock.autoAdvance = true
        composeRule.waitForIdle()
        composeRule.onNodeWithTag("setting_row_0").assertExists()
    }
}
