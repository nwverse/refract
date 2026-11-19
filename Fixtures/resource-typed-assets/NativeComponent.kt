package example.app

import androidx.annotation.RawRes
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext

/** An app-owned consumer; generated code never opens this resource. */
@Composable
fun AppPolicyDocument(@RawRes document: Int) {
    val text = LocalContext.current.resources.openRawResource(document).bufferedReader().use { it.readText() }
    Text(text = text)
}
