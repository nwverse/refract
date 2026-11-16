package com.example.refract.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/** This screen remains hand-written before and after adopting Refract. */
@Composable
fun HomeScreen(onOpenProfile: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Text("Native home", style = MaterialTheme.typography.headlineMedium)
        Text(
            "The next screen is generated, while navigation and this screen stay native.",
            modifier = Modifier.padding(top = 8.dp),
        )
        Button(
            onClick = onOpenProfile,
            modifier = Modifier.padding(top = 24.dp),
        ) {
            Text("Edit profile")
        }
    }
}
