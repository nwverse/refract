package com.example.refract.document

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import refract.generated.DocumentPreviewModel
import refract.generated.DocumentPreviewState
import refract.generated.R

/** One already classified document, including its explicit lifecycle state. */
data class AuthorizedDocument(
    val uri: Uri,
    val displayName: String,
    val mimeType: String,
    val byteCount: Int,
    val revision: Int,
    val state: DocumentPreviewState,
    val decodedText: String = "",
)

/** A bounded text load. The app decides whether and when to start it. */
class PendingDocumentLoad internal constructor(
    internal val document: AuthorizedDocument,
    internal val bytes: ByteArray,
)

/**
 * Application-owned document permission, decoding, cancellation and close.
 * Refract supplies neither this controller nor any URI/network implementation.
 */
class SyntheticDocumentController(private val context: Context) : DocumentPreviewModel {
    var document by mutableStateOf(
        AuthorizedDocument(Uri.EMPTY, "", "", 0, 0, DocumentPreviewState.closed)
    )
        private set
    var screenRevision by mutableIntStateOf(0)
        private set
    private var pending: PendingDocumentLoad? = null
    private var nextRevision = 1

    /** Permission is granted only to this local, synthetic fixture URI. */
    fun authorizeSyntheticTextFixture(): AuthorizedDocument {
        val uri = Uri.Builder()
            .scheme(ContentResolver.SCHEME_ANDROID_RESOURCE)
            .authority(context.packageName)
            .appendPath("raw")
            .appendPath("synthetic_document")
            .build()
        val bytes = context.resources.openRawResource(
            R.raw.synthetic_document
        ).use { input ->
            val bounded = input.readNBytes(MAX_SYNTHETIC_BYTES + 1)
            check(bounded.size <= MAX_SYNTHETIC_BYTES) { "Synthetic fixture exceeds its byte limit." }
            bounded
        }
        check(bytes.contentEquals(SYNTHETIC_DOCUMENT_BYTES)) { "Unexpected synthetic fixture bytes." }
        val revision = nextRevision++
        pending = PendingDocumentLoad(
            AuthorizedDocument(
                uri = uri,
                displayName = "Synthetic document",
                mimeType = "text/plain",
                byteCount = bytes.size,
                revision = revision,
                state = DocumentPreviewState.loading,
            ),
            bytes,
        )
        document = pending!!.document.copy(state = DocumentPreviewState.loading)
        screenRevision = revision
        return document
    }

    fun openWithMissingResult(): AuthorizedDocument = missingResult()
    fun openWithUnsupportedResult(): AuthorizedDocument = unsupportedResult("application/pdf")

    /** Only the app advances a pending load; Refract never schedules this work. */
    fun finishOpening() {
        val current = pending ?: return
        if (document.state == DocumentPreviewState.cancelled) {
            pending = null
            return
        }
        check(document.revision == current.document.revision) { "Stale synthetic load." }
        check(current.bytes.contentEquals(SYNTHETIC_DOCUMENT_BYTES)) { "Unexpected synthetic fixture bytes." }
        val text = current.bytes.toString(Charsets.UTF_8).trimEnd('\r', '\n')
        check(text == SYNTHETIC_DOCUMENT_TEXT) { "Unexpected synthetic fixture contents." }
        document = current.document.copy(state = DocumentPreviewState.ready, decodedText = text)
        pending = null
    }

    override fun cancelPreview() {
        if (document.state != DocumentPreviewState.loading) return
        pending = null
        document = document.copy(state = DocumentPreviewState.cancelled, decodedText = "")
    }

    override fun closePreview() {
        pending = null
        document = document.copy(state = DocumentPreviewState.closed, decodedText = "")
        // A different key lets the native component release its own resources.
        screenRevision = nextRevision++
    }

    private fun missingResult(): AuthorizedDocument {
        pending = null
        val revision = nextRevision++
        document = AuthorizedDocument(
            uri = Uri.parse("urn:refract:synthetic:missing"),
            displayName = "Missing synthetic document",
            mimeType = "text/plain",
            byteCount = 0,
            revision = revision,
            state = DocumentPreviewState.missing,
        )
        screenRevision = revision
        return document
    }

    private fun unsupportedResult(mimeType: String): AuthorizedDocument {
        pending = null
        val revision = nextRevision++
        document = AuthorizedDocument(
            uri = Uri.parse("urn:refract:synthetic:unsupported"),
            displayName = "Unsupported synthetic document",
            mimeType = mimeType,
            byteCount = 0,
            revision = revision,
            state = DocumentPreviewState.unsupported,
        )
        screenRevision = revision
        return document
    }

    companion object {
        const val MAX_SYNTHETIC_BYTES = 4096
        const val SYNTHETIC_DOCUMENT_TEXT = "Synthetic document body; no personal data."
        private val SYNTHETIC_DOCUMENT_BYTES =
            (SYNTHETIC_DOCUMENT_TEXT + "\n").toByteArray(Charsets.UTF_8)
    }
}
