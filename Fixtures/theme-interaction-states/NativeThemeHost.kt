package example.design

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.semantics
import refract.generated.ThemedSettingsControl

/** App-owned native control: one real interaction source supplies all generated state arguments. */
@Composable
fun ThemedSettingsAction(
    interactionSource: MutableInteractionSource,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val pressed = interactionSource.collectIsPressedAsState().value
    val focused = interactionSource.collectIsFocusedAsState().value
    Box(
        modifier = modifier
            .semantics { if (!enabled) disabled() }
            .focusProperties { canFocus = enabled }
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                enabled = enabled,
                role = Role.Button,
                onClick = onClick,
            ),
    ) {
        ThemedSettingsControl(
            isEnabled = enabled,
            onIsEnabledChange = {},
            isPressed = pressed,
            onIsPressedChange = {},
            isFocused = focused,
            onIsFocusedChange = {},
        )
    }
}
