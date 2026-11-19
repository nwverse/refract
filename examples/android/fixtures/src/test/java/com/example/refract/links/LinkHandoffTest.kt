package com.example.refract.links

import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.AndroidComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.v2.runAndroidComposeUiTest
import example.app.LinkAllowlistEntry
import example.app.LinkDestination
import example.app.LinkHandoff
import example.app.LinkHandoffResult
import example.app.LinkPolicy
import example.app.NativeHelpLink
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import refract.generated.HelpLinkScreen

/** Native JVM Compose interaction tests. No URL is opened, no network or emulator is used. */
@OptIn(ExperimentalTestApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class LinkHandoffTest {
    @Test
    fun generatedExternalAndDeepLinksRequireConfirmationBeforeHandoff() = runLinkTest {
        val handoff = ControlledLinkHandoff()
        setContent { HelpLinkScreen(handoff = handoff) }
        onNodeWithTag("link_open_external").performClick()
        assertEquals(emptyList<LinkDestination>(), handoff.started)
        onNodeWithTag("link_confirm_external").performClick()
        assertEquals(listOf(external), handoff.started)
        handoff.complete(external, LinkHandoffResult.HANDED_OFF)
        onNodeWithTag("link_result_external").assertTextEquals("Result: handed_off")
        assertEquals(emptyList<LinkDestination>(), handoff.cancelled)

        onNodeWithTag("link_open_deep_link").performClick()
        onNodeWithTag("link_confirm_deep_link").performClick()
        assertEquals(listOf(external, deepLink), handoff.started)
        handoff.complete(deepLink, LinkHandoffResult.HANDED_OFF)
        onNodeWithTag("link_result_deep_link").assertTextEquals("Result: handed_off")
        assertEquals(emptyList<LinkDestination>(), handoff.cancelled)
    }

    @Test
    fun confirmationCancellationNeverStartsAHandoff() = runLinkTest {
        val handoff = ControlledLinkHandoff()
        setContent { HelpLinkScreen(handoff = handoff) }
        onNodeWithTag("link_open_external").performClick()
        onNodeWithTag("link_cancel_external").performClick()
        assertEquals(emptyList<LinkDestination>(), handoff.started)
        assertEquals(emptyList<LinkDestination>(), handoff.cancelled)
        onNodeWithTag("link_result_external").assertTextEquals("Result: cancelled")
    }

    @Test
    fun disallowedHostNeverShowsConfirmationOrStartsAHandoff() = runLinkTest {
        val handoff = ControlledLinkHandoff()
        setContent {
            NativeHelpLink(destination = external.copy(host = "other.example.test"), policy = policy, handoff = handoff)
        }
        onNodeWithTag("link_open_external").performClick()
        onNodeWithTag("link_confirm_external").assertDoesNotExist()
        assertEquals(emptyList<LinkDestination>(), handoff.started)
        onNodeWithTag("link_result_external").assertTextEquals("Result: disallowed")
    }

    @Test
    fun unsupportedSchemeIsRejectedBeforeConfirmation() = runLinkTest {
        val handoff = ControlledLinkHandoff()
        val destination = external.copy(scheme = "javascript")
        setContent {
            NativeHelpLink(destination = destination, policy = LinkPolicy(
                allowed = listOf(LinkAllowlistEntry("javascript", external.host)),
            ), handoff = handoff)
        }
        onNodeWithTag("link_open_external").performClick()
        assertEquals(emptyList<LinkDestination>(), handoff.started)
        onNodeWithTag("link_result_external").assertTextEquals("Result: unsupported_scheme")
    }

    @Test
    fun invalidHostLabelsAreRejectedBeforeHandoff() = runLinkTest {
        val handoff = ControlledLinkHandoff()
        val destination = external.copy(host = "docs.-bad.example.test")
        setContent {
            NativeHelpLink(destination = destination, policy = LinkPolicy(
                allowed = listOf(LinkAllowlistEntry(destination.scheme, destination.host)),
            ), handoff = handoff)
        }
        onNodeWithTag("link_open_external").performClick()
        assertEquals(emptyList<LinkDestination>(), handoff.started)
        onNodeWithTag("link_result_external").assertTextEquals("Result: disallowed")
    }

    @Test
    fun changingPolicyAfterConfirmationRechecksBeforeHandoff() = runLinkTest {
        val handoff = ControlledLinkHandoff()
        var currentPolicy by mutableStateOf(policy)
        setContent {
            NativeHelpLink(destination = external, policy = currentPolicy, handoff = handoff)
        }
        onNodeWithTag("link_open_external").performClick()
        runOnIdle { currentPolicy = LinkPolicy(emptyList()) }
        onNodeWithTag("link_confirm_external").performClick()
        assertEquals(emptyList<LinkDestination>(), handoff.started)
        onNodeWithTag("link_result_external").assertTextEquals("Result: disallowed")
    }

    @Test
    fun leavingCompositionCancelsPendingAndIgnoresLateCompletion() = runLinkTest {
        val handoff = ControlledLinkHandoff()
        var visible by mutableStateOf(true)
        setContent { if (visible) HelpLinkScreen(handoff = handoff) }
        onNodeWithTag("link_open_external").performClick()
        onNodeWithTag("link_confirm_external").performClick()
        runOnIdle { visible = false }
        waitForIdle()
        assertEquals(listOf(external), handoff.cancelled)
        handoff.complete(external, LinkHandoffResult.HANDED_OFF)
        assertEquals(listOf(external), handoff.started)
    }

    @Test
    fun replacingDestinationCancelsOldPendingBeforeNewConfirmation() = runLinkTest {
        val handoff = ControlledLinkHandoff()
        var destination by mutableStateOf(external)
        setContent { NativeHelpLink(destination = destination, policy = policy, handoff = handoff) }
        onNodeWithTag("link_open_external").performClick()
        onNodeWithTag("link_confirm_external").performClick()
        runOnIdle { destination = replacement }
        waitForIdle()
        assertEquals(listOf(external), handoff.cancelled)
        onNodeWithTag("link_open_external").performClick()
        onNodeWithTag("link_result_external").assertTextEquals("No link opened")
        onNodeWithTag("link_confirm_external").performClick()
        assertEquals(listOf(external, replacement), handoff.started)
        runOnIdle { handoff.complete(external, LinkHandoffResult.HANDED_OFF) }
        onNodeWithTag("link_result_external").assertTextEquals("No link opened")
        runOnIdle { handoff.complete(replacement, LinkHandoffResult.HANDED_OFF) }
        onNodeWithTag("link_result_external").assertTextEquals("Result: handed_off")
    }

    @Test
    fun staleCompletionCannotOverwriteACancelledResult() = runLinkTest {
        val handoff = ControlledLinkHandoff()
        setContent { HelpLinkScreen(handoff = handoff) }
        onNodeWithTag("link_open_external").performClick()
        onNodeWithTag("link_confirm_external").performClick()
        runOnIdle { handoff.complete(external, LinkHandoffResult.CANCELLED) }
        runOnIdle { handoff.complete(external, LinkHandoffResult.HANDED_OFF) }
        onNodeWithTag("link_result_external").assertTextEquals("Result: cancelled")
    }

    private fun runLinkTest(block: AndroidComposeUiTest<ComponentActivity>.() -> Unit) =
        runAndroidComposeUiTest<ComponentActivity>(block = block)

    private val external = LinkDestination(LinkDestination.Kind.EXTERNAL, "https", "docs.example.test", "/help/start")
    private val replacement = LinkDestination(LinkDestination.Kind.EXTERNAL, "https", "docs.example.test", "/help/next")
    private val deepLink = LinkDestination(LinkDestination.Kind.DEEP_LINK, "app+test", "router.example.test", "/article/42")
    private val policy = LinkPolicy(listOf(
        LinkAllowlistEntry("https", "docs.example.test"),
        LinkAllowlistEntry("app+test", "router.example.test"),
    ))

    private class ControlledLinkHandoff : LinkHandoff {
        val started = mutableListOf<LinkDestination>()
        val cancelled = mutableListOf<LinkDestination>()
        val results = mutableMapOf<LinkDestination, LinkHandoffResult>()
        private val completions = mutableMapOf<LinkDestination, (LinkHandoffResult) -> Unit>()

        override fun begin(destination: LinkDestination, completion: (LinkHandoffResult) -> Unit) {
            started += destination
            completions[destination] = completion
        }

        override fun cancel(destination: LinkDestination) {
            cancelled += destination
            completions.remove(destination)
        }

        fun complete(destination: LinkDestination, result: LinkHandoffResult) {
            results[destination] = result
            completions[destination]?.invoke(result)
        }
    }
}
