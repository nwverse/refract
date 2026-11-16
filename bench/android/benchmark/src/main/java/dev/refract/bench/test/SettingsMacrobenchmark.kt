package dev.refract.bench.test

import android.content.ComponentName
import android.content.Intent
import androidx.benchmark.macro.CompilationMode
import androidx.benchmark.macro.ExperimentalMetricApi
import androidx.benchmark.macro.FrameTimingMetric
import androidx.benchmark.macro.MemoryUsageMetric
import androidx.benchmark.macro.StartupMode
import androidx.benchmark.macro.StartupTimingMetric
import androidx.benchmark.macro.junit4.MacrobenchmarkRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@OptIn(ExperimentalMetricApi::class)
@RunWith(AndroidJUnit4::class)
class SettingsMacrobenchmark {
    @get:Rule
    val benchmarkRule = MacrobenchmarkRule()

    @Test
    fun generatedStartup() = startup("generated")

    @Test
    fun referenceStartup() = startup("reference")

    @Test
    fun generatedMacrobenchmark() = scroll("generated")

    @Test
    fun referenceMacrobenchmark() = scroll("reference")

    @Test
    fun generatedStateUpdate() = stateUpdate("generated")

    @Test
    fun referenceStateUpdate() = stateUpdate("reference")

    private fun startup(variant: String) = benchmarkRule.measureRepeated(
        packageName = PACKAGE_NAME,
        metrics = listOf(StartupTimingMetric()),
        compilationMode = CompilationMode.Partial(),
        iterations = 10,
        startupMode = StartupMode.COLD,
        setupBlock = { pressHome() },
    ) {
        startActivityAndWait(
            Intent(Intent.ACTION_MAIN)
                .setComponent(ComponentName(PACKAGE_NAME, "$PACKAGE_NAME.BenchmarkActivity"))
                .addCategory(Intent.CATEGORY_LAUNCHER)
                .putExtra("dev.refract.bench.variant", variant)
        )
        device.wait(Until.hasObject(By.text("Native settings")), 20_000)
    }

    private fun scroll(variant: String) = benchmarkRule.measureRepeated(
        packageName = PACKAGE_NAME,
        metrics = listOf(FrameTimingMetric(), MemoryUsageMetric(MemoryUsageMetric.Mode.Last)),
        compilationMode = CompilationMode.Partial(),
        iterations = 10,
        startupMode = StartupMode.WARM,
        setupBlock = { launchScreen(variant) },
    ) {
        repeat(4) {
            device.swipe(540, 1550, 540, 250, 10)
            device.waitForIdle(2_000)
        }
        device.swipe(540, 400, 540, 1800, 12)
        device.waitForIdle(2_000)
    }

    private fun stateUpdate(variant: String) = benchmarkRule.measureRepeated(
        packageName = PACKAGE_NAME,
        metrics = listOf(FrameTimingMetric(), MemoryUsageMetric(MemoryUsageMetric.Mode.Last)),
        compilationMode = CompilationMode.Partial(),
        iterations = 10,
        startupMode = StartupMode.WARM,
        setupBlock = { launchScreen(variant) },
    ) {
        repeat(8) {
            device.findObject(By.desc("Setting 0")).click()
            device.waitForIdle(2_000)
        }
    }

    private fun androidx.benchmark.macro.MacrobenchmarkScope.launchScreen(variant: String) {
        startActivityAndWait(
            Intent(Intent.ACTION_MAIN)
                .setComponent(ComponentName(PACKAGE_NAME, "$PACKAGE_NAME.BenchmarkActivity"))
                .addCategory(Intent.CATEGORY_LAUNCHER)
                .putExtra("dev.refract.bench.variant", variant)
        )
        device.wait(Until.hasObject(By.desc("Setting 0")), 20_000)
    }

    companion object {
        const val PACKAGE_NAME = "dev.refract.bench"
    }
}
