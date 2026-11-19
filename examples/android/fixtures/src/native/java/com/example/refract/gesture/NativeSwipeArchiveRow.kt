package com.example.refract.gesture

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.MotionDurationScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.launch

/**
 * Application-owned native swipe and accessible action host.
 * Every request opens the same pending confirmation; only its confirm action archives.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NativeSwipeArchiveRow(
    identifier: String,
    title: String,
    onRequest: (String) -> Unit,
    onConfirm: (String) -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val scope = rememberCoroutineScope()
    val motion = remember { mutableFloatStateOf(1f) }
    val motionEnabled = motion.floatValue > 0f
    LaunchedEffect(Unit) {
        currentCoroutineContext()[MotionDurationScale]?.let { scale ->
            snapshotFlow { scale.scaleFactor }.collect { motion.floatValue = it }
        }
    }
    val dismissState = rememberSwipeToDismissBoxState()
    var pending by remember(identifier) { mutableStateOf<String?>(null) }
    var pendingGeneration by remember(identifier) { mutableIntStateOf(0) }
    var generation by remember { mutableIntStateOf(0) }
    var menuExpanded by remember(identifier) { mutableStateOf(false) }
    val observer = LocalSwipeArchiveObserver.current

    DisposableEffect(identifier) {
        val ownedGeneration = pendingGeneration
        onDispose {
            if (pendingGeneration == ownedGeneration) {
                val cancelled = pending != null
                pendingGeneration = ownedGeneration + 1
                generation += 1
                pending = null
                // The existing app-owned action clears only this obsolete pending request.
                if (cancelled) onCancel()
            }
        }
    }

    fun settle(target: SwipeToDismissBoxValue) {
        observer.onSettle(identifier, target, motionEnabled)
        if (!motionEnabled) {
            scope.launch { dismissState.snapTo(target) }
        } else {
            scope.launch { dismissState.reset() }
        }
    }

    fun request() {
        if (pending != null) return
        // A revealed action and the menu share this exact pending path.
        if (dismissState.currentValue != SwipeToDismissBoxValue.Settled) settle(SwipeToDismissBoxValue.Settled)
        pending = identifier
        pendingGeneration = generation
        onRequest(identifier)
    }

    LaunchedEffect(identifier, onRequest) {
        snapshotFlow {
            Triple(dismissState.currentValue, dismissState.targetValue, dismissState.progress)
        }.collect { (current, target, progress) ->
            observer.onProgress(identifier, current, target, progress)
            if (target == SwipeToDismissBoxValue.EndToStart) {
                // A full swipe may reveal the same native action. Settling first prevents a
                // subsequent action click from requesting a second confirmation.
                if (pending == null) request()
                settle(SwipeToDismissBoxValue.Settled)
            }
        }
    }

    Box(modifier = modifier) {
        SwipeToDismissBox(
            state = dismissState,
            enableDismissFromStartToEnd = false,
            backgroundContent = {
                if (dismissState.currentValue != SwipeToDismissBoxValue.Settled || pending != null) {
                    TextButton(onClick = ::request, modifier = Modifier.testTag("swipe_revealed_archive")) {
                        Text("Archive")
                    }
                }
            },
            content = {
                Row(modifier = Modifier.fillMaxWidth().testTag("swipe_archive_row").semantics {
                    customActions = listOf(
                        CustomAccessibilityAction(label = "Archive", action = {
                            request()
                            true
                        }),
                    )
                }) {
                    Text(text = title, modifier = Modifier.weight(1f))
                    Box {
                        TextButton(
                            onClick = { menuExpanded = true },
                            modifier = Modifier.semantics { contentDescription = "Row actions" },
                        ) {
                            Text("Row actions")
                        }
                        DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                            DropdownMenuItem(
                                text = { Text("Archive") },
                                onClick = {
                                    menuExpanded = false
                                    request()
                                },
                            )
                        }
                    }
                }
            },
        )
    }

    pending?.let { selected ->
        AlertDialog(
            onDismissRequest = {
                val cancelled = pending != null
                pending = null
                settle(SwipeToDismissBoxValue.Settled)
                if (cancelled) onCancel()
            },
            title = { Text("Archive this item?") },
            text = { Text("The app will archive the selected item after confirmation.") },
            confirmButton = {
                TextButton(onClick = {
                    if (canConfirmSwipeArchive(
                        pendingIdentifier = pending,
                        currentIdentifier = identifier,
                        pendingGeneration = pendingGeneration,
                        currentGeneration = generation,
                    )) {
                        pending = null
                        settle(SwipeToDismissBoxValue.Settled)
                        onConfirm(selected)
                    } else {
                        pending = null
                        settle(SwipeToDismissBoxValue.Settled)
                    }
                }) { Text("Archive item") }
            },
            dismissButton = {
                TextButton(onClick = {
                    val cancelled = pending != null
                    pending = null
                    settle(SwipeToDismissBoxValue.Settled)
                    if (cancelled) onCancel()
                }) { Text("Cancel") }
            },
        )
    }
}

internal fun canConfirmSwipeArchive(
    pendingIdentifier: String?,
    currentIdentifier: String,
    pendingGeneration: Int,
    currentGeneration: Int,
): Boolean = pendingIdentifier == currentIdentifier && pendingGeneration == currentGeneration

internal interface SwipeArchiveObserver {
    fun onSettle(identifier: String, target: SwipeToDismissBoxValue, animated: Boolean)
    fun onProgress(identifier: String, current: SwipeToDismissBoxValue, target: SwipeToDismissBoxValue, progress: Float) {}
}

internal object NoopSwipeArchiveObserver : SwipeArchiveObserver {
    override fun onSettle(identifier: String, target: SwipeToDismissBoxValue, animated: Boolean) {}
}

internal val LocalSwipeArchiveObserver = androidx.compose.runtime.staticCompositionLocalOf<SwipeArchiveObserver> {
    NoopSwipeArchiveObserver
}
