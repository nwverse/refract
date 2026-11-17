package example.app

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.compose.foundation.Image
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTag
import java.io.ByteArrayInputStream
import java.io.IOException

/** The application chooses the transport, limits and cache; Refract supplies neither. */
fun interface RemoteImageLoader {
    suspend fun load(url: String): ByteArray
}

private enum class RemoteImageState { LOADING, SUCCESS, FAILURE }

@Composable
fun RemoteImage(
    url: String,
    placeholder: Int,
    failure: Int,
    contentDescription: String,
    loader: RemoteImageLoader,
    modifier: Modifier = Modifier,
) {
    var state by remember { mutableStateOf(RemoteImageState.LOADING) }
    var bitmap by remember { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(url, loader) {
        state = RemoteImageState.LOADING
        bitmap = null
        if (!isAllowedRemoteImageUrl(url)) {
            state = RemoteImageState.FAILURE
            return@LaunchedEffect
        }
        try {
            val decoded = decodeBoundedBitmap(loader.load(url))
            bitmap = decoded
            state = RemoteImageState.SUCCESS
        } catch (_: IOException) {
            state = RemoteImageState.FAILURE
        } catch (_: IllegalArgumentException) {
            state = RemoteImageState.FAILURE
        }
    }
    val imageModifier = modifier.semantics {
        this.contentDescription = contentDescription
        testTag = when (state) {
            RemoteImageState.LOADING -> "remote_image_placeholder"
            RemoteImageState.SUCCESS -> "remote_image_success"
            RemoteImageState.FAILURE -> "remote_image_failure"
        }
    }
    when (state) {
        RemoteImageState.LOADING -> Image(
            painter = painterResource(placeholder),
            contentDescription = null,
            modifier = imageModifier,
        )
        RemoteImageState.SUCCESS -> bitmap?.let { decoded ->
            Image(
                bitmap = decoded.asImageBitmap(),
                contentDescription = null,
                modifier = imageModifier,
            )
        }
        RemoteImageState.FAILURE -> Image(
            painter = painterResource(failure),
            contentDescription = null,
            modifier = imageModifier,
        )
    }
}

internal fun isAllowedRemoteImageUrl(value: String): Boolean {
    if (value.length > 2_048 || value != value.trim()) return false
    val parsed = try {
        Uri.parse(value)
    } catch (_: RuntimeException) {
        return false
    }
    return parsed.scheme == "https" &&
        !parsed.host.isNullOrEmpty() &&
        parsed.userInfo == null &&
        parsed.fragment == null &&
        parsed.port in -1..65_535
}

private const val MAX_IMAGE_BYTES = 8 * 1024 * 1024
private const val MAX_IMAGE_PIXELS = 16_777_216L

private fun decodeBoundedBitmap(bytes: ByteArray): Bitmap {
    if (bytes.isEmpty() || bytes.size > MAX_IMAGE_BYTES) throw IOException("Image byte limit exceeded")
    val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
    if (options.outWidth <= 0 || options.outHeight <= 0 ||
        options.outWidth.toLong() * options.outHeight.toLong() > MAX_IMAGE_PIXELS) {
        throw IOException("Image dimensions are invalid or exceed the pixel limit")
    }
    return BitmapFactory.decodeStream(ByteArrayInputStream(bytes))
        ?: throw IOException("Image decoding failed")
}
