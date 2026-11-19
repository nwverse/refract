package example.app

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag

/** Application-owned immutable values; there is no arbitrary Intent action or dispatch target. */
@Stable
data class LinkDestination(
    val kind: Kind,
    val scheme: String,
    val host: String,
    val path: String,
) {
    enum class Kind { EXTERNAL, DEEP_LINK }
}

@Stable
data class LinkAllowlistEntry(val scheme: String, val host: String)

@Stable
data class LinkPolicy(val allowed: List<LinkAllowlistEntry>) {
    fun permits(destination: LinkDestination): Boolean = allowed.any {
        it.scheme == destination.scheme && it.host == destination.host
    }
}

enum class LinkHandoffResult { HANDED_OFF, CANCELLED, DISALLOWED, UNSUPPORTED_SCHEME, UNAVAILABLE }

/** The host chooses its router or external handler and owns the activity/page lifecycle. */
interface LinkHandoff {
    fun begin(destination: LinkDestination, completion: (LinkHandoffResult) -> Unit)
    fun cancel(destination: LinkDestination)
}

private data class PendingRequest(
    val destination: LinkDestination,
    val handoff: LinkHandoff,
    var finished: Boolean = false,
)

private sealed interface LinkUiState {
    data object Idle : LinkUiState
    data class Confirming(val destination: LinkDestination) : LinkUiState
    data class HandingOff(val destination: LinkDestination) : LinkUiState
    data class Result(val value: LinkHandoffResult) : LinkUiState
}

/** The source supplies immutable values; only this app component confirms and calls the injected host. */
@Composable
fun NativeHelpLink(
    destination: LinkDestination,
    policy: LinkPolicy,
    handoff: LinkHandoff,
    modifier: Modifier = Modifier,
) {
    var state by remember { mutableStateOf<LinkUiState>(LinkUiState.Idle) }
    var pending by remember { mutableStateOf<PendingRequest?>(null) }
    val currentPending by rememberUpdatedState(pending)
    fun cancelPending(request: PendingRequest) {
        if (request.finished) return
        request.finished = true
        request.handoff.cancel(request.destination)
    }
    pending?.let { request ->
        if (request.destination != destination || request.handoff !== handoff) {
            SideEffect {
                cancelPending(request)
                if (currentPending == request) {
                    pending = null
                    state = LinkUiState.Idle
                }
            }
        } else {
            DisposableEffect(request) {
                onDispose {
                    cancelPending(request)
                    if (currentPending == request) pending = null
                }
            }
        }
    }

    Column(modifier = modifier) {
        Button(
            onClick = {
                val outcome = validateDestination(destination, policy)
                state = if (outcome == null) LinkUiState.Confirming(destination) else LinkUiState.Result(outcome)
            },
            modifier = Modifier.testTag("link_open_${destination.kind.name.lowercase()}"),
        ) { Text(if (destination.kind == LinkDestination.Kind.EXTERNAL) "Open help" else "Open article") }
        Text(
            text = when (val current = state) {
                is LinkUiState.Result -> "Result: ${current.value.name.lowercase()}"
                else -> "No link opened"
            },
            modifier = Modifier.testTag("link_result_${destination.kind.name.lowercase()}"),
        )
    }

    val confirming = state as? LinkUiState.Confirming
    if (confirming != null) {
        AlertDialog(
            onDismissRequest = {
                state = LinkUiState.Result(LinkHandoffResult.CANCELLED)
            },
            title = { Text("Confirm link") },
            text = { Text("${confirming.destination.scheme}://${confirming.destination.host}${confirming.destination.path}") },
            confirmButton = {
                TextButton(
                    onClick = {
                        val candidate = confirming.destination
                        val outcome = validateDestination(candidate, policy)
                        if (outcome != null) {
                            state = LinkUiState.Result(outcome)
                            return@TextButton
                        }
                        state = LinkUiState.HandingOff(candidate)
                        val request = PendingRequest(candidate, handoff)
                        pending = request
                        handoff.begin(candidate) { result ->
                            if (!request.finished) {
                                request.finished = true // Completed requests have nothing left to cancel.
                                pending = null
                                state = LinkUiState.Result(result)
                            }
                        }
                    },
                    modifier = Modifier.testTag("link_confirm_${destination.kind.name.lowercase()}"),
                ) { Text("Continue") }
            },
            dismissButton = {
                TextButton(
                    onClick = {
                        state = LinkUiState.Result(LinkHandoffResult.CANCELLED)
                    },
                    modifier = Modifier.testTag("link_cancel_${destination.kind.name.lowercase()}"),
                ) { Text("Cancel") }
            },
        )
    }
}

internal fun validateDestination(destination: LinkDestination, policy: LinkPolicy): LinkHandoffResult? {
    if (destination.scheme == "http" || destination.scheme in setOf("file", "content", "intent", "javascript", "data")) {
        return LinkHandoffResult.UNSUPPORTED_SCHEME
    }
    if (destination.scheme.length > 32 || !destination.scheme.matches(Regex("[a-z][a-z0-9+.-]*"))) {
        return LinkHandoffResult.UNSUPPORTED_SCHEME
    }
    if (destination.kind == LinkDestination.Kind.EXTERNAL && destination.scheme != "https" ||
        destination.kind == LinkDestination.Kind.DEEP_LINK && destination.scheme == "https") {
        return LinkHandoffResult.UNSUPPORTED_SCHEME
    }
    val validHost = destination.host.length <= 253 && destination.host.contains('.') &&
        destination.host.split('.').all { label ->
            label.length in 1..63 && label.all { it in 'a'..'z' || it in '0'..'9' || it == '-' } &&
                (label.first() in 'a'..'z' || label.first() in '0'..'9') &&
                (label.last() in 'a'..'z' || label.last() in '0'..'9')
        }
    if (!validHost) {
        return LinkHandoffResult.DISALLOWED
    }
    if (destination.path.length > 512 || !destination.path.matches(Regex("/[A-Za-z0-9._~/-]*")) ||
        destination.path.contains("//") || destination.path.split('/').any { it == "." || it == ".." } ||
        destination.path.length > 1 && destination.path.endsWith('/')) {
        return LinkHandoffResult.DISALLOWED
    }
    return if (policy.permits(destination)) null else LinkHandoffResult.DISALLOWED
}
