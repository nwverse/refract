package com.example.refract.nativehost

import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import refract.generated.BackgroundWorkScreen
import refract.generated.LifecycleScreen
import refract.generated.NotificationScreen
import refract.generated.RefractBackgroundWorkCorrelation
import refract.generated.RefractBackgroundWorkEventState
import refract.generated.RefractNotificationCorrelation
import refract.generated.RefractNotificationEventState
import refract.generated.RefractScenePhase
import refract.generated.SyntheticBackgroundHost
import refract.generated.SyntheticLifecycleHost
import refract.generated.SyntheticNotificationHost

/** Real Compose on Robolectric with synthetic values only. No OS notification or background job. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class NativeHostContractTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun lifecycleForwardsSyntheticForegroundAndBackground() {
        val events = mutableListOf<String>()
        val host = object : SyntheticLifecycleHost {
            override fun foreground() { events += "foreground" }
            override fun background() { events += "background" }
        }
        var visible by mutableStateOf(true)
        var phase by mutableStateOf(RefractScenePhase.foreground)
        compose.setContent {
            if (visible) LifecycleScreen(lifecycle = host, phase = phase)
        }
        compose.onNodeWithText("Synthetic foreground").assertIsDisplayed()
        compose.runOnIdle { phase = RefractScenePhase.background }
        compose.onNodeWithText("Synthetic background").assertIsDisplayed()
        assertEquals(listOf("foreground"), events)
        compose.runOnIdle { visible = false }
        compose.onNodeWithText("Synthetic background").assertDoesNotExist()
        compose.waitUntil(timeoutMillis = 5_000) { events == listOf("foreground", "background") }
        assertEquals(listOf("foreground", "background"), events)
    }

    @Test
    fun notificationRendersAbsenceStaleCancellationAndConfirmation() {
        val requests = mutableListOf<String>()
        val host = object : SyntheticNotificationHost {
            override fun present(id: String, revision: Int) { requests += "present:$id:$revision" }
            override fun cancel(id: String, revision: Int) { requests += "cancel:$id:$revision" }
            override fun confirm(id: String, revision: Int) { requests += "confirm:$id:$revision" }
        }
        val correlation = RefractNotificationCorrelation("synthetic-sync", 2)
        var event by mutableStateOf(RefractNotificationEventState.unavailable("synthetic-sync", 2))
        compose.setContent {
            NotificationScreen(notifications = host, notification = event, correlation = correlation)
        }
        compose.onNodeWithText("Synthetic request: synthetic-sync").assertIsDisplayed()
        compose.onNodeWithText("Capability unavailable; permission remains app-owned").assertIsDisplayed()
        compose.onNodeWithText("Present synthetic request").performClick()
        assertEquals(listOf("present:synthetic-sync:2"), requests)

        compose.runOnIdle { event = RefractNotificationEventState.confirmationRequired("synthetic-sync", 2) }
        compose.onNodeWithText("Explicit native confirmation required").assertIsDisplayed()
        compose.onNodeWithText("Confirm synthetic request").performClick()
        compose.onNodeWithText("Cancel synthetic request").performClick()
        assertEquals(listOf(
            "present:synthetic-sync:2", "confirm:synthetic-sync:2", "cancel:synthetic-sync:2",
        ), requests)

        compose.runOnIdle { event = RefractNotificationEventState.stale("synthetic-sync", 1) }
        compose.onNodeWithText("Stale revision; no delivery claim").assertIsDisplayed()
        compose.runOnIdle { event = RefractNotificationEventState.cancelled("synthetic-sync", 2) }
        compose.onNodeWithText("App confirms cancellation").assertIsDisplayed()
        compose.runOnIdle { event = RefractNotificationEventState.confirmed("synthetic-sync", 2) }
        compose.onNodeWithText("App confirms the synthetic request").assertIsDisplayed()
    }

    @Test
    fun backgroundWorkDoesNotTurnAcceptanceIntoExecution() {
        var event by mutableStateOf(RefractBackgroundWorkEventState.accepted("synthetic-sync", 1))
        val requests = mutableListOf<String>()
        val host = object : SyntheticBackgroundHost {
            override fun schedule(id: String, revision: Int) { requests += "schedule:$id:$revision" }
            override fun cancel(id: String, revision: Int) { requests += "cancel:$id:$revision" }
            override fun confirm(id: String, revision: Int) { requests += "confirm:$id:$revision" }
        }
        compose.setContent {
            BackgroundWorkScreen(
                work = host,
                workEvent = event,
                correlation = RefractBackgroundWorkCorrelation("synthetic-sync", 1),
            )
        }
        compose.onNodeWithText("Synthetic work: synthetic-sync").assertIsDisplayed()
        compose.onNodeWithText("Accepted by the app; no execution claim").assertIsDisplayed()
        compose.onNodeWithText("Schedule synthetic work").performClick()
        assertEquals(listOf("schedule:synthetic-sync:1"), requests)
        compose.runOnIdle { event = RefractBackgroundWorkEventState.scheduled("synthetic-sync", 1) }
        compose.onNodeWithText("App confirms scheduling; still not executed").assertIsDisplayed()
        compose.runOnIdle { event = RefractBackgroundWorkEventState.completed("synthetic-sync", 1) }
        compose.onNodeWithText("App confirms synthetic completion").assertIsDisplayed()
    }
}
