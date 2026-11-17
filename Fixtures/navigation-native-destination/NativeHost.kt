package example.nativeescape

import example.native.NativeDetail
import androidx.compose.runtime.Composable
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import refract.generated.EscapeDetailModel
import refract.generated.EscapeRoute
import refract.generated.EscapeScreen
import refract.generated.EscapeScreenDestinations

/** The host owns the only controller and native back stack. */
@Composable
fun TypedNativeEscapeNavigationHost(model: EscapeDetailModel) {
    val controller = rememberNavController()
    NavHost(navController = controller, startDestination = "home") {
        composable("home") {
            EscapeScreen(model = model, onPathNavigate = { destination: EscapeRoute ->
                controller.navigate(destination.name)
            })
        }
        composable(EscapeRoute.detail.name) {
            EscapeScreenDestinations(destination = EscapeRoute.detail, model = model)
        }
        composable(EscapeRoute.native.name) {
            EscapeScreenDestinations(destination = EscapeRoute.native, model = model)
        }
    }
}
