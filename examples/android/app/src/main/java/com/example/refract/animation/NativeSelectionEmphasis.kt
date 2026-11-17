package com.example.refract.animation

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.MotionDurationScale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.flow.distinctUntilChanged

/** Application-owned stateful native transition; Refract only emits the typed call. */
@Composable
fun NativeSelectionEmphasis(
    emphasized: Boolean,
    identity: String,
    modifier: Modifier = Modifier,
) {
    // Read the recomposer's native motion policy. No duration or animation spec crosses the source boundary.
    var scale by remember { mutableFloatStateOf(1f) }
    val motionEnabled = scale > 0f
    LaunchedEffect(Unit) {
        val motion = currentCoroutineContext()[MotionDurationScale] ?: return@LaunchedEffect
        snapshotFlow { motion.scaleFactor }.collect { scale = it }
    }
    key(identity) {
        val emphasis = remember { Animatable(0f) }
        val observer = LocalSelectionEmphasisObserver.current
        LaunchedEffect(emphasis, emphasized, motionEnabled) {
            if (motionEnabled) {
                // animateTo retains the current value and velocity when a new target interrupts this one.
                emphasis.animateTo(
                    targetValue = if (emphasized) 1f else 0f,
                    animationSpec = tween(durationMillis = 400, easing = LinearEasing),
                )
            } else {
                emphasis.snapTo(if (emphasized) 1f else 0f)
            }
        }
        if (observer != null) {
            SideEffect {
                observer.onStateChanged(identity, emphasis.value, emphasis.isRunning)
            }
            LaunchedEffect(emphasis, observer) {
                snapshotFlow { Triple(identity, emphasis.value, emphasis.isRunning) }
                    .distinctUntilChanged()
                    .collect { (currentIdentity, progress, isRunning) ->
                        observer.onStateChanged(currentIdentity, progress, isRunning)
                    }
            }
        }
        DisposableEffect(observer) {
            observer?.onAppear(identity)
            onDispose { observer?.onDispose(identity) }
        }
        Text(
            text = "Selection",
            color = Color.Black,
            modifier = modifier
                .graphicsLayer { alpha = 0.5f + emphasis.value * 0.5f }
                .semantics { contentDescription = identity }
                .testTag("selection_emphasis"),
        )
    }
}

/** Optional app-owned lifecycle observation, absent from every generated entry point. */
val LocalSelectionEmphasisObserver = compositionLocalOf<SelectionEmphasisObserver?> { null }

interface SelectionEmphasisObserver {
    fun onAppear(identity: String)
    fun onStateChanged(identity: String, progress: Float, isRunning: Boolean)
    fun onDispose(identity: String)
}
