package example.native

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import refract.generated.DeepNavigationModel
import refract.generated.DeepNavigationScreen
import refract.generated.DeepNavigationScreenDestinations
import refract.generated.DeepRoute

private class DeepHostModel : DeepNavigationModel {
    override val title: State<String> = mutableStateOf("Home")
}

/**
 * The application owns the only back stack. The graph has root, detail and editor
 * levels; no destination objects, runtime registry or parallel source stack exist.
 */
@Composable
fun DeepNavigationHost(model: DeepNavigationModel = DeepHostModel()): NavHostController {
    val controller = rememberNavController()
    fun push(destination: DeepRoute) {
        controller.navigate(destination.name)
    }
    NavHost(navController = controller, startDestination = "home") {
        composable("home") {
            DeepNavigationScreen(model = model, onPathNavigate = ::push)
        }
        composable(DeepRoute.detail.name) {
            DeepNavigationScreenDestinations(
                destination = DeepRoute.detail,
                model = model,
                onPathNavigate = ::push,
            )
        }
        composable(DeepRoute.editor.name) {
            // Native saveable destination state travels with this back-stack entry.
            var edits by rememberSaveable { mutableIntStateOf(0) }
            Column {
                Text("Edits: $edits", modifier = Modifier.testTag("editor-edits"))
                Button(onClick = { edits += 1 }, modifier = Modifier.testTag("record-edit")) {
                    Text("Record edit")
                }
                DeepNavigationScreenDestinations(
                    destination = DeepRoute.editor,
                    model = model,
                    onPathNavigate = ::push,
                )
            }
        }
    }
    return controller
}
