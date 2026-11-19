package example.native

import androidx.activity.ComponentActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.State
import androidx.compose.ui.test.AndroidComposeUiTest
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.v2.runAndroidComposeUiTest
import androidx.compose.ui.semantics.SemanticsActions
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import refract.generated.ModalHostScreen

/** Real generated Compose on Native JVM, not an emulator, device or performance benchmark. */
@OptIn(ExperimentalTestApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class NativeModalHostTest {
    @Test
    fun sheetPresentsTypedContentAndAccessibilityDismissalReopens() = runAndroidComposeUiTest<ComponentActivity> {
        val sheetChanges = mutableListOf<Boolean>()
        setModalContent(onIsProfilePresentedChange = { sheetChanges += it })
        onNodeWithText("Profile details").assertDoesNotExist()
        onNodeWithText("Open profile").performClick()
        onNodeWithText("Profile details").assertIsDisplayed()
        onNodeWithText("Example profile").assertIsDisplayed()

        onNode(SemanticsMatcher.keyIsDefined(SemanticsActions.Dismiss)).performSemanticsAction(SemanticsActions.Dismiss)
        waitForIdle()
        onNodeWithText("Profile details").assertDoesNotExist()
        onNodeWithText("Open profile").performClick()
        onNodeWithText("Profile details").assertIsDisplayed()
        assertEquals(listOf(true, false, true), sheetChanges)
    }

    @Test
    fun alertHasNativeTextAndButtonsAndConfirmationClosesBeforeModelAction() = runAndroidComposeUiTest<ComponentActivity> {
        val deletes = mutableListOf<String>()
        var visible = true
        setModalContent(showDeleteConfirmation = true, onShowDeleteConfirmationChange = {
            visible = it
            if (!it) deletes += "dismissed"
        }, onConfirmDelete = { deletes += if (visible) "visible" else "closed" })

        onNodeWithText("Delete this profile?").assertIsDisplayed()
        onNodeWithText("This action cannot be undone.").assertIsDisplayed()
        onNodeWithText("Delete").assertHasClickAction().performClick()
        onNodeWithText("Delete this profile?").assertDoesNotExist()
        assertEquals(listOf("dismissed", "closed"), deletes)
    }

    @Test
    fun alertCancelClosesWithoutConfirmingAndCanReopen() = runAndroidComposeUiTest<ComponentActivity> {
        val changes = mutableListOf<Boolean>()
        var confirmations = 0
        setModalContent(showDeleteConfirmation = true, onShowDeleteConfirmationChange = { changes += it },
                        onConfirmDelete = { confirmations += 1 })
        onNodeWithText("Cancel").performClick()
        onNodeWithText("Delete this profile?").assertDoesNotExist()
        assertEquals(listOf(false), changes)
        assertEquals(0, confirmations)

        onNodeWithText("Delete profile").performClick()
        onNodeWithText("Delete this profile?").assertIsDisplayed()
        assertEquals(listOf(false, true), changes)
        assertEquals(0, confirmations)
    }

    @Test
    fun alertPresentationFollowsExternalBindingAndEachReopening() = runAndroidComposeUiTest<ComponentActivity> {
        var presentations = 0
        setModalContent(onShowDeleteConfirmationPresent = { presentations += 1 })
        assertEquals(0, presentations)
        onNodeWithText("Delete profile").performClick()
        onNodeWithText("Delete this profile?").assertIsDisplayed()
        assertEquals(1, presentations)
        onNodeWithText("Cancel").performClick()
        onNodeWithText("Delete this profile?").assertDoesNotExist()
        onNodeWithText("Delete profile").performClick()
        onNodeWithText("Delete this profile?").assertIsDisplayed()
        assertEquals(2, presentations)
    }

    private fun AndroidComposeUiTest<ComponentActivity>.setModalContent(
        showDeleteConfirmation: Boolean = false,
        onIsProfilePresentedChange: (Boolean) -> Unit = {},
        onShowDeleteConfirmationChange: (Boolean) -> Unit = {},
        onShowDeleteConfirmationPresent: () -> Unit = {},
        onConfirmDelete: () -> Unit = {},
    ) {
        var sheetPresented by mutableStateOf(false)
        var deletePresented by mutableStateOf(showDeleteConfirmation)
        setContent {
            ModalHostScreen(
                model = object : refract.generated.ProfileModel {
                    override val summary = mutableStateOf("Example profile")
                    override fun confirmDelete() = onConfirmDelete()
                },
                isProfilePresented = sheetPresented,
                onIsProfilePresentedChange = {
                    sheetPresented = it
                    onIsProfilePresentedChange(it)
                },
                showDeleteConfirmation = deletePresented,
                onShowDeleteConfirmationChange = {
                    deletePresented = it
                    onShowDeleteConfirmationChange(it)
                },
                onShowDeleteConfirmationPresent = onShowDeleteConfirmationPresent,
            )
        }
    }
}
