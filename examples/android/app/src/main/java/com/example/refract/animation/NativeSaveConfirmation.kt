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
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.snapshotFlow
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
    // WindowRecomposer supplies the platform animator-duration scale through this context.
    // Reading it during composition also observes preference changes; no independent policy is used.
    val scale = rememberCoroutineScope().coroutineContext[MotionDurationScale]?.scaleFactor ?: 1f
    val motionEnabled = scale > 0f
    key(identity) {
        val transitionState = remember { MutableTransitionState(visible) }
        transitionState.targetState = visible
        val observer = LocalSaveConfirmationObserver.current
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
