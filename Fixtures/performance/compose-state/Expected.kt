// Generated from Fixtures/performance/compose-state/Input.swift by Refract.
// DO NOT EDIT. Hand-written expected pattern pending generator support.

package performance.composeState

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State

public interface CounterModel {
    public val title: State<String>
    public val count: State<Int>
    public fun increment()
}

@Composable
public fun CounterView(model: CounterModel) {
    Column {
        Text(text = model.title.value)
        Text(text = "Count: ${model.count.value}")
        Button(onClick = { model.increment() }) {
            Text(text = "Increment")
        }
    }
}
