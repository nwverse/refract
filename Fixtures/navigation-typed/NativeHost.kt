package example.nativeescape

import example.native.NativeDetail
import androidx.compose.runtime.Composable
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import refract.generated.DetailModel
import refract.generated.NavigationScreen
import refract.generated.NavigationScreenDestinations
import refract.generated.Route

/** The host owns the only controller and native back stack. */
@Composable
fun TypedNativeEscapeNavigationHost(model: DetailModel) {
    val controller = rememberNavController()
    NavHost(navController = controller, startDestination = "home") {
        composable("home") {
            NavigationScreen(model = model, onPathNavigate = { destination ->
                controller.navigate(destination.name)
            })
        }
        composable(Route.detail.name) {
            NavigationScreenDestinations(destination = Route.detail, model = model)
        }
        composable(Route.native.name) {
            NavigationScreenDestinations(destination = Route.native, model = model)
        }
    }
}
