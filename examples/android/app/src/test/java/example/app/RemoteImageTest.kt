package example.app

import android.app.Application
import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.junit4.v2.AndroidComposeTestRule
import androidx.compose.ui.test.onNodeWithTag
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TestRule
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import refract.generated.ProfileImage
import refract.generated.R

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class RemoteImageTest {
    @get:Rule
    val compose = AndroidComposeTestRule(
        activityRule = TestRule { base, _ -> base },
        activityProvider = {
            Robolectric.buildActivity(RemoteImageTestActivity::class.java)
                .create()
                .start()
                .postCreate(null)
                .resume()
                .visible()
                .windowFocusChanged(true)
                .get()
        },
    )

    private val first = "https://example.com/first.png"
    private val second = "https://example.com/second.png"

    @Test
    fun placeholderSuccessAndLocalizedDescriptionUseGeneratedEntryPoint() {
        val loader = ControlledLoader()
        compose.setContent { ProfileImage(url = first, loader = loader) }
        compose.onNodeWithTag("remote_image_placeholder")
            .assertContentDescriptionEquals("Profile photo")
        loader.succeedNext()
        compose.onNodeWithTag("remote_image_success")
            .assertContentDescriptionEquals("Profile photo")
        assertEquals(listOf(first), loader.requests)
    }

    @Test
    fun failureKeepsDescriptionAndDoesNotRetryImplicitly() {
        val loader = ControlledLoader()
        compose.setContent { ProfileImage(url = first, loader = loader) }
        loader.failNext()
        compose.onNodeWithTag("remote_image_failure")
            .assertContentDescriptionEquals("Profile photo")
        assertEquals(listOf(first), loader.requests)
    }

    @Test
    fun urlReplacementCancelsOldRequestAndRejectsItsCompletion() {
        val loader = ControlledLoader()
        var url by mutableStateOf(first)
        compose.setContent { ProfileImage(url = url, loader = loader) }
        assertEquals(listOf(first), loader.requests)
        url = second
        compose.onNodeWithTag("remote_image_placeholder").assertExists()
        compose.waitForIdle()
        assertEquals(listOf(first, second), loader.requests)
        assertEquals(listOf(first), loader.cancelled)
        loader.complete(first)
        compose.onNodeWithTag("remote_image_placeholder").assertExists()
        loader.succeedNext()
        compose.onNodeWithTag("remote_image_success").assertExists()
    }

    @Test
    fun leavingCompositionCancelsInFlightLoad() {
        val loader = ControlledLoader()
        var visible by mutableStateOf(true)
        compose.setContent {
            if (visible) ProfileImage(url = first, loader = loader)
        }
        assertEquals(listOf(first), loader.requests)
        visible = false
        compose.waitForIdle()
        assertEquals(listOf(first), loader.cancelled)
    }

    @Test
    fun validInputCallsInjectedLoader() {
        val loader = ControlledLoader()
        compose.setContent { ProfileImage(url = first, loader = loader) }
        compose.waitForIdle()
        assertEquals(listOf(first), loader.requests)
    }

    @Test
    fun fileSchemeIsRejectedBeforeLoading() = assertRejectedBeforeLoading("file:///profile.png")

    @Test
    fun httpSchemeIsRejectedBeforeLoading() = assertRejectedBeforeLoading("http://example.com/profile.png")

    @Test
    fun userInfoIsRejectedBeforeLoading() =
        assertRejectedBeforeLoading("https://user:password@example.com/profile.png")

    @Test
    fun missingHostIsRejectedBeforeLoading() = assertRejectedBeforeLoading("https:///profile.png")

    @Test
    fun surroundingWhitespaceIsRejectedBeforeLoading() =
        assertRejectedBeforeLoading(" https://example.com/profile.png")

    private fun assertRejectedBeforeLoading(value: String) {
        val loader = ControlledLoader()
        compose.setContent { ProfileImage(url = value, loader = loader) }
        compose.onNodeWithTag("remote_image_failure")
            .assertContentDescriptionEquals("Profile photo")
        assertEquals(value, emptyList<String>(), loader.requests)
    }

    private class ControlledLoader : RemoteImageLoader {
        val requests = mutableListOf<String>()
        val cancelled = mutableListOf<String>()
        private val pending = mutableMapOf<String, CompletableDeferred<ByteArray>>()

        override suspend fun load(url: String): ByteArray {
            requests += url
            val result = CompletableDeferred<ByteArray>()
            pending[url] = result
            try {
                return result.await()
            } catch (error: CancellationException) {
                cancelled += url
                throw error
            }
        }

        fun succeedNext() = complete(requests.last())

        fun failNext() {
            pending.remove(requests.last())?.completeExceptionally(java.io.IOException("synthetic failure"))
        }

        fun complete(url: String) {
            pending.remove(url)?.complete(onePixelPng())
        }
    }
}

private fun onePixelPng(): ByteArray {
    val stream = java.io.ByteArrayOutputStream()
    Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
        .compress(Bitmap.CompressFormat.PNG, 100, stream)
    return stream.toByteArray()
}
