package example.designsystem

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

@Composable
fun ReadOnlyRow(value: String, modifier: Modifier = Modifier) {
    androidx.compose.material3.Text(value, modifier = modifier)
}
