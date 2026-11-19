@file:OptIn(androidx.compose.material3.windowsizeclass.ExperimentalMaterial3WindowSizeClassApi::class)

package example.native

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.windowsizeclass.WindowWidthSizeClass
import androidx.compose.material3.windowsizeclass.calculateWindowSizeClass
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import refract.generated.AdaptiveNavigationScreen
import refract.generated.AdaptiveNavigationScreenDestinations
import refract.generated.AdaptiveRoute
import refract.generated.AdaptiveSettingsModel
import refract.generated.AdaptiveSettingsScreen

/** Native host: one model, controller and measurement lifecycle; no generated navigation stack. */
@Composable
fun AdaptiveSettingsHost(model: AdaptiveSettingsModel, notificationsEnabled: Boolean,
                         onNotificationsEnabledChange: (Boolean) -> Unit) {
    val controller = rememberNavController()
    val widthSizeClass = calculateWindowSizeClass(LocalContext.current as android.app.Activity).widthSizeClass
    var displayName by androidx.compose.runtime.saveable.rememberSaveable { mutableStateOf("") }
    NavHost(navController = controller, startDestination = "settings") {
        composable("settings") {
            Box(modifier = Modifier.fillMaxSize()) {
                AdaptiveSettingsScreen(
                    model = model,
                    widthSizeClass = widthSizeClass,
                    notificationsEnabled = notificationsEnabled,
                    onNotificationsEnabledChange = onNotificationsEnabledChange,
                    displayName = displayName,
                    onDisplayNameChange = { displayName = it },
                )
                AdaptiveNavigationScreen(model = model, onPathNavigate = {
                    controller.navigate(AdaptiveRoute.detail.name)
                })
            }
        }
        composable(AdaptiveRoute.detail.name) {
            AdaptiveNavigationScreenDestinations(destination = AdaptiveRoute.detail, model = model)
        }
    }
}
