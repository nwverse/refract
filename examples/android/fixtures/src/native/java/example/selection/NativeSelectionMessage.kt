package example.selection

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable

@Immutable
public data class RefractSelectionRange(val start: Int, val end: Int)

@Immutable
public data class RefractSelectionLink(
    val range: RefractSelectionRange,
    val destination: String,
)

@Immutable
public data class RefractSelectionContext(
    val text: String,
    val range: RefractSelectionRange,
)

@Immutable
public data class RefractSelectionContent(
    val text: String,
    val links: List<RefractSelectionLink>,
)

/**
 * Application-owned native host. Current selection stays native and selection movement
 * never calls either context action. An explicit button captures a scalar-safe snapshot.
 */
@Composable
public fun NativeSelectionMessage(
    content: RefractSelectionContent,
    onLink: (String) -> Unit,
    onUseAsContext: (RefractSelectionContext) -> Unit,
    onEditWithAI: (RefractSelectionContext) -> Unit,
) {
    val host = SelectionMessageHost(content, onLink, onUseAsContext, onEditWithAI)
    Column {
        Text(content.text)
        Button(onClick = { host.useAsContext() }) { Text("Use as context") }
        Button(onClick = { host.editWithAI() }) { Text("Edit with AI") }
    }
}

/** Native state and validation shared by the app-owned host and plain Native JVM tests. */
public class SelectionMessageHost(
    private val content: RefractSelectionContent,
    private val onLink: (String) -> Unit,
    private val onUseAsContext: (RefractSelectionContext) -> Unit,
    private val onEditWithAI: (RefractSelectionContext) -> Unit,
) {
    public var selectionStart: Int = 0
        private set
    public var selectionEnd: Int = 0
        private set

    init {
        require(content.links.all {
            it.range.start >= 0 && it.range.start < it.range.end &&
                it.range.end <= content.text.length &&
                isScalarBoundary(content.text, it.range.start) &&
                isScalarBoundary(content.text, it.range.end)
        })
        require(content.links.zipWithNext().all { (first, second) -> first.range.end <= second.range.start })
    }

    public fun moveSelection(start: Int, end: Int) {
        require(start >= 0 && start <= end && end <= content.text.length)
        require(isScalarBoundary(content.text, start) && isScalarBoundary(content.text, end))
        selectionStart = start
        selectionEnd = end
    }

    public fun activateLink(index: Int) {
        onLink(content.links[index].destination)
    }

    public fun useAsContext() {
        onUseAsContext(snapshot())
    }

    public fun editWithAI() {
        onEditWithAI(snapshot())
    }

    private fun snapshot(): RefractSelectionContext =
        RefractSelectionContext(content.text, RefractSelectionRange(selectionStart, selectionEnd))

    private companion object {
        fun isScalarBoundary(text: String, offset: Int): Boolean {
            if (offset == 0 || offset == text.length) return true
            return !(Character.isHighSurrogate(text[offset - 1]) && Character.isLowSurrogate(text[offset]))
        }
    }
}
