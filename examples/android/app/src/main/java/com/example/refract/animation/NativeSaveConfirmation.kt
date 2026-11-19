package com.example.refract.animation

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import kotlinx.coroutines.currentCoroutineContext
import androidx.compose.ui.Modifier
import androidx.compose.ui.MotionDurationScale
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import kotlinx.coroutines.flow.distinctUntilChanged

/** Application-owned native implementation; Refract only emits the typed call. */
@Composable
fun NativeSaveConfirmation(
    visible: Boolean,
    identity: String,
    modifier: Modifier = Modifier,
) {
    // The composition effect context carries the platform MotionDurationScale. A snapshot-backed
    // scale factor recomposes when the platform value changes, rather than using a parallel policy.
    var scale by remember { mutableFloatStateOf(1f) }
    val motionEnabled = scale > 0f
    LaunchedEffect(Unit) {
        val motion = currentCoroutineContext()[MotionDurationScale]
        if (motion == null) return@LaunchedEffect
        snapshotFlow { motion.scaleFactor }.collect { scale = it }
    }
    key(identity) {
        val transitionState = remember { MutableTransitionState(visible) }
        transitionState.targetState = visible
        val observer = LocalSaveConfirmationObserver.current
        observer?.onTransitionStateChanged(transitionState.currentState, transitionState.isIdle)
        if (observer != null) {
            LaunchedEffect(transitionState, observer) {
                snapshotFlow { transitionState.currentState to transitionState.isIdle }
                    .distinctUntilChanged()
                    .collect { (visible, idle) ->
                        observer.onTransitionStateChanged(visible, idle)
                    }
            }
        }
        AnimatedVisibility(
            visibleState = transitionState,
            modifier = modifier,
            enter = if (motionEnabled) fadeIn(animationSpec = tween(200)) else EnterTransition.None,
            exit = if (motionEnabled) fadeOut(animationSpec = tween(200)) else ExitTransition.None,
        ) {
            DisposableEffect(observer) {
                observer?.onAppear(identity)
                onDispose {
                    observer?.onDispose(identity)
                }
            }
            Text(
                text = "Saved",
                modifier = Modifier
                    .semantics { contentDescription = identity }
                    .testTag("save_confirmation"),
            )
        }
    }
}

/** Optional app-owned observation; it is never a generated parameter or Refract dependency. */
val LocalSaveConfirmationObserver = compositionLocalOf<SaveConfirmationObserver?> { null }

interface SaveConfirmationObserver {
    fun onAppear(identity: String)
    fun onDispose(identity: String)
    fun onTransitionStateChanged(visible: Boolean, isIdle: Boolean)
}
