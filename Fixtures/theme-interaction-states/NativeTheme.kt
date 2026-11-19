package example.design

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.colorResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Application-owned style values. The generated screen never chooses RGB values or a second theme. */
object AppColors {
    val content: Color
        @Composable get() = colorResource(refract.generated.R.color.theme_content)
}

object AppTypography {
    val body = TextStyle(fontSize = 16.sp, lineHeight = 24.sp)
}

object AppSpacing {
    val medium: Dp = 12.dp
}

object AppRadius {
    val medium: Dp = 8.dp
}

object AppInteractionColors {
    /**
     * Disabled wins over interaction feedback; pressed wins over focused. The caller passes observations
     * from its actual control, not a detached source. This is application code, not a Refract runtime.
     */
    @Composable
    fun resolve(
        enabled: Boolean,
        pressed: Boolean,
        focused: Boolean,
        normal: Int,
        pressedColor: Int,
        focusedColor: Int,
        disabledColor: Int,
    ): Color = colorResource(
        when {
            !enabled -> disabledColor
            pressed -> pressedColor
            focused -> focusedColor
            else -> normal
        },
    )
}
