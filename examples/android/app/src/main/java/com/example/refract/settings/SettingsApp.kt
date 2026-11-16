package com.example.refract.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import refract.generated.Hello
import refract.generated.NativeComponentScreen

private enum class Destination {
    Home,
    GeneratedLayout,
}

@Composable
fun SettingsApp() {
    var destination by rememberSaveable { mutableStateOf(Destination.Home) }

    MaterialTheme {
        Surface(modifier = Modifier.fillMaxSize()) {
            when (destination) {
                Destination.Home -> HomeScreen(
                    onOpenProfile = { destination = Destination.GeneratedLayout },
                )
                Destination.GeneratedLayout -> Column {
                    Hello()
                    // Native navigation calls generated code, which calls native code in turn.
                    NativeComponentScreen()
                }
            }
        }
    }
}
