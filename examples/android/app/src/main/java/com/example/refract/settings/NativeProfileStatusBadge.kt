package com.example.refract.settings

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

/** A hand-written native component callable from generated Compose. */
@Composable
fun NativeProfileStatusBadge(modifier: Modifier = Modifier) {
    Text(
        text = "Settings managed natively",
        modifier = modifier,
        color = MaterialTheme.colorScheme.primary,
        style = MaterialTheme.typography.labelMedium,
    )
}
