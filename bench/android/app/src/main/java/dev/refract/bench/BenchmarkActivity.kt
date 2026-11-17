package dev.refract.bench

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.view.doOnPreDraw

class BenchmarkActivity : ComponentActivity() {
    val benchmarkModel = BenchmarkSettingsModel()
    private var variant by mutableStateOf(ScreenVariant.Generated)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        selectVariant(intent.getStringExtra(EXTRA_VARIANT))
        setContent {
            MaterialTheme {
                when (variant) {
                    ScreenVariant.Generated -> SettingsScreen(benchmarkModel)
                    ScreenVariant.Reference -> ReferenceSettingsScreen(benchmarkModel)
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        findViewById<android.view.View>(android.R.id.content).doOnPreDraw {
            reportFullyDrawn()
        }
    }

    private fun selectVariant(name: String?) {
        variant = when (name) {
            "reference" -> ScreenVariant.Reference
            "generated" -> ScreenVariant.Generated
            else -> ScreenVariant.Generated
        }
    }

    companion object {
        const val EXTRA_VARIANT = "dev.refract.bench.variant"
    }
}
