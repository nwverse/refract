package example.native

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.navigation.NavHostController
import refract.generated.DeepRoute
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TestRule
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

class NavigationDeepHostActivity : ComponentActivity() {
    var restoredControllerState: Bundle? = null
    var hostController: NavHostController? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            hostController = DeepNavigationHost()
            restoredControllerState?.let { hostController!!.restoreState(it) }
            restoredControllerState = null
        }
    }
}

/** Real Compose and Navigation on Robolectric: Native JVM, not an emulator/device. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class NavigationDeepRestorationTest {
    @get:Rule
    val rule = createAndroidComposeRule<NavigationDeepHostActivity>()

    @Test
    fun threeLevelsPopInNativeBackOrder() {
        openEditor()
        rule.runOnIdle { rule.activity.onBackPressedDispatcher.onBackPressed() }
        rule.onNodeWithText("Open editor").assertIsDisplayed()
        rule.onNodeWithText("Editor").assertDoesNotExist()

        rule.runOnIdle { rule.activity.onBackPressedDispatcher.onBackPressed() }
        rule.onNodeWithText("Open detail").assertIsDisplayed()
        rule.onNodeWithText("Open editor").assertDoesNotExist()
    }

    @Test
    fun activityRecreationRestoresEditorEntryAndNativeDestinationState() {
        openEditor()
        rule.onNodeWithTag("record-edit").performClick()
        rule.onNodeWithTag("editor-edits").assertTextEquals("Edits: 1")

        rule.activityRule.scenario.recreate()
        rule.waitForIdle()

        rule.onNodeWithText("Editor").assertIsDisplayed()
        rule.onNodeWithTag("editor-edits").assertTextEquals("Edits: 1")
        rule.runOnIdle { rule.activity.onBackPressedDispatcher.onBackPressed() }
        rule.onNodeWithText("Open editor").assertIsDisplayed()
        rule.runOnIdle { rule.activity.onBackPressedDispatcher.onBackPressed() }
        rule.onNodeWithText("Open detail").assertIsDisplayed()
    }

    @Test
    fun controllerSaveStateRestoresTypedRouteOrder() {
        openEditor()
        val restored = android.os.Bundle()
        rule.runOnIdle { restored.putAll(rule.activity.hostController!!.saveState()) }

        rule.activity.restoredControllerState = restored
        rule.activityRule.scenario.recreate()
        rule.waitForIdle()

        rule.onNodeWithText("Editor").assertIsDisplayed()
        rule.runOnIdle { rule.activity.onBackPressedDispatcher.onBackPressed() }
        rule.onNodeWithText("Open editor").assertIsDisplayed()
        rule.runOnIdle { rule.activity.onBackPressedDispatcher.onBackPressed() }
        rule.onNodeWithText("Open detail").assertIsDisplayed()
    }

    private fun openEditor() {
        rule.onNodeWithText("Open detail").performClick()
        rule.onNodeWithText("Open editor").assertIsDisplayed()
        rule.onNodeWithText("Open editor").performClick()
        rule.onNodeWithText("Editor").assertIsDisplayed()
    }
}
