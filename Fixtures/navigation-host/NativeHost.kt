package example.native

import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableStateOf
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import refract.generated.DetailModel
import refract.generated.NavigationScreenDestinations
import refract.generated.NavigationScreen
import refract.generated.Route

private class HostModel : DetailModel {
    override val title: State<String> = mutableStateOf("Shared title")
}

/** The native host owns the only controller, back stack and destination lifecycle. */
@Composable
fun TypedNavigationHost(model: DetailModel = HostModel()) {
    val controller = rememberNavController()
    NavHost(navController = controller, startDestination = "home") {
        composable("home") {
            NavigationScreen(model = model, onPathNavigate = { destination: Route ->
                controller.navigate(destination.name)
            })
        }
        composable(Route.detail.name) {
            NavigationScreenDestinations(destination = Route.detail, model = model)
        }
    }
}
