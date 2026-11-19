package com.example.refract.form

import androidx.activity.ComponentActivity
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.AndroidComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.v2.runAndroidComposeUiTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import refract.generated.SignupModel
import refract.generated.SignupScreen

/**
 * Native JVM (Robolectric) Compose behavior of the CLI-generated signup form from
 * `Fixtures/form-validation`. Not an emulator, a device or a performance measurement.
 *
 * The generated composable is staged verbatim by scripts/check_fixture_compilation.py;
 * only the app-owned model is written by hand here, exactly as a consuming app supplies it.
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class GeneratedSignupFormTest {
    @Test
    fun emptyDraftIsRejectedBeforeTheModelIsCalled() = runAndroidComposeUiTest<ComponentActivity> {
        val model = FakeSignupModel()
        setContent { SignupScreen(model = model) }

        onNodeWithText("Create account").performClick()
        waitForIdle()
        assertTrue("an empty draft must not reach the model", model.calls.isEmpty())
    }

    @Test
    fun mismatchedCrossFieldRuleKeepsTheModelUntouchedAndPreservesTheDraft() =
        runAndroidComposeUiTest<ComponentActivity> {
            val model = FakeSignupModel()
            setContent { SignupScreen(model = model) }

            onNodeWithText("Email").performTextInput("me@example.com")
            onNodeWithText("Password").performTextInput("secret1")
            onNodeWithText("Confirm password").performTextInput("secret2")
            onNodeWithText("Create account").performClick()
            waitForIdle()

            assertTrue("a cross-field mismatch must not reach the model", model.calls.isEmpty())

            onNodeWithText("Confirm password").performTextClearance()
            onNodeWithText("Confirm password").performTextInput("secret1")
            onNodeWithText("Create account").performClick()
            waitForIdle()

            assertEquals(
                "the corrected draft must survive the rejected attempt and reach the model",
                listOf("submit:me@example.com:secret1:secret1"),
                model.calls,
            )
        }

    @Test
    fun pendingStateDisablesTheButtonAndPreventsDuplicateSubmission() =
        runAndroidComposeUiTest<ComponentActivity> {
            val model = FakeSignupModel()
            setContent { SignupScreen(model = model) }
            fillValidDraft()

            onNodeWithText("Create account").performClick()
            waitForIdle()
            assertEquals(1, model.calls.size)
            onNodeWithText("Submitting…").assertIsDisplayed()
            onNodeWithText("Create account").assertIsNotEnabled()

            onNodeWithText("Create account").performClick()
            waitForIdle()
            assertEquals("a second click while pending must not call the model again", 1, model.calls.size)
            assertEquals(listOf("me@example.com"), model.submittedEmails)
        }

    @Test
    fun failedAttemptRendersTheModelErrorAndRetriesWithTheSameDraft() =
        runAndroidComposeUiTest<ComponentActivity> {
            val model = FakeSignupModel()
            setContent { SignupScreen(model = model) }
            fillValidDraft()

            onNodeWithText("Create account").performClick()
            waitForIdle()
            runOnIdle { model.finishAttempt(error = "Email is already registered") }
            waitForIdle()

            onNodeWithText("Email is already registered").assertIsDisplayed()
            onNodeWithText("Create account").assertIsEnabled()
            onNodeWithText("Retry").assertIsDisplayed()

            onNodeWithText("Retry").performClick()
            waitForIdle()
            assertEquals(
                "retry must reuse the preserved draft rather than reset the fields",
                listOf(
                    "submit:me@example.com:secret1:secret1",
                    "retry:me@example.com:secret1:secret1",
                ),
                model.calls,
            )
            onNodeWithText("Email").assertDraft("me@example.com")
        }

    @Test
    fun draftSurvivesRecompositionDrivenByModelStateChanges() = runAndroidComposeUiTest<ComponentActivity> {
        val model = FakeSignupModel()
        setContent { SignupScreen(model = model) }
        fillValidDraft()
        runOnIdle {
            model.submittingState.value = true
            model.submittingState.value = false
        }
        waitForIdle()
        onNodeWithText("Email").assertDraft("me@example.com")
        onNodeWithText("Password").assertDraft("secret1")
    }

    private fun androidx.compose.ui.test.SemanticsNodeInteraction.assertDraft(expected: String) {
        val value = fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.InputText]
        assertEquals("the draft must be preserved in the native text field", expected, value.text)
    }

    private fun AndroidComposeUiTest<ComponentActivity>.fillValidDraft() {
        onNodeWithText("Email").performTextInput("me@example.com")
        onNodeWithText("Password").performTextInput("secret1")
        onNodeWithText("Confirm password").performTextInput("secret1")
        waitForIdle()
    }
}

/** App-owned model: owns the pending flag, the error text and every attempt. */
private class FakeSignupModel : SignupModel {
    val submittingState = mutableStateOf(false)
    private val errorState = mutableStateOf<String?>(null)
    val calls = mutableListOf<String>()
    val submittedEmails = mutableListOf<String>()

    override val submitting: State<Boolean> = submittingState
    override val submissionError: State<String?> = errorState

    override fun submit(email: String, password: String, confirmation: String): Boolean {
        return beginAttempt("submit", email, password, confirmation)
    }

    override fun retry(email: String, password: String, confirmation: String): Boolean {
        return beginAttempt("retry", email, password, confirmation)
    }

    private fun beginAttempt(kind: String, email: String, password: String, confirmation: String): Boolean {
        if (submittingState.value) return false
        calls += "$kind:$email:$password:$confirmation"
        submittedEmails += email
        submittingState.value = true
        errorState.value = null
        return true
    }

    fun finishAttempt(error: String?) {
        submittingState.value = false
        errorState.value = error
    }
}
