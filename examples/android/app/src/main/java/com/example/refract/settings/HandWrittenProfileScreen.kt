package com.example.refract.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/** The hand-written profile that remains available during incremental adoption. */
@Composable
fun HandWrittenProfileScreen() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
    ) {
        Text("Hand-written profile")
        Text("Navigation and this screen remain native when adopting a generated layout.")
    }
}
