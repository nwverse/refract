package com.example.refract.media

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import refract.generated.CameraCapabilityModel
import refract.generated.CameraCapabilityState
import refract.generated.PlaybackCapabilityModel
import refract.generated.PlaybackCapabilityState
import refract.generated.ShareCapabilityModel
import refract.generated.ShareCapabilityState

enum class SyntheticMediaKind { playback, camera, share }
enum class SyntheticPhase { unavailable, permissionRequired, permissionDenied, approvalRequired, ready, cancelled }

/** A synthetic request. Its identifier is not a URI, file, media item or recipient. */
data class SyntheticMediaRequest(
    val kind: SyntheticMediaKind,
    val identifier: String,
    val revision: Int,
    val phase: SyntheticPhase,
)

/**
 * Synthetic controller for state transitions and cancellation only.
 * A production app separately supplies its own policy and native implementation.
 */
class SyntheticMediaController : PlaybackCapabilityModel, CameraCapabilityModel, ShareCapabilityModel {
    var request by mutableStateOf(
        SyntheticMediaRequest(SyntheticMediaKind.playback, "synthetic-playback-1", 1, SyntheticPhase.unavailable)
    )
        private set
    var screenRevision by mutableIntStateOf(1)
        private set
    private var pending: SyntheticMediaRequest? = null
    private var nextRevision = 2
    val actions = mutableListOf<String>()

    fun select(kind: SyntheticMediaKind, phase: SyntheticPhase) {
        pending = null
        request = SyntheticMediaRequest(kind, "synthetic-${kind.name}-1", nextRevision++, phase)
        screenRevision = request.revision
    }

    fun beginSyntheticApproval(kind: SyntheticMediaKind) {
        require(request.kind == kind && request.phase == SyntheticPhase.approvalRequired)
        pending = request
    }

    /** Only this synthetic test controller supplies the result, never a platform permission API. */
    fun deliverSyntheticApproval() {
        val current = pending ?: return
        if (request.phase != SyntheticPhase.approvalRequired || request.revision != current.revision) return
        pending = null
        request = request.copy(phase = SyntheticPhase.ready)
    }

    fun cancelCurrent() {
        pending = null
        request = request.copy(phase = SyntheticPhase.cancelled)
    }

    override fun requestPlaybackApproval() {
        actions += "approve:${request.identifier}:${request.revision}"
        beginSyntheticApproval(SyntheticMediaKind.playback)
    }

    override fun requestCameraApproval() {
        actions += "approve:${request.identifier}:${request.revision}"
        beginSyntheticApproval(SyntheticMediaKind.camera)
    }

    override fun requestShareApproval() {
        actions += "approve:${request.identifier}:${request.revision}"
        beginSyntheticApproval(SyntheticMediaKind.share)
    }

    override fun cancelPlayback() {
        actions += "cancel:${request.identifier}:${request.revision}"
        cancelCurrent()
    }

    override fun cancelCamera() {
        actions += "cancel:${request.identifier}:${request.revision}"
        cancelCurrent()
    }

    override fun cancelShare() {
        actions += "cancel:${request.identifier}:${request.revision}"
        cancelCurrent()
    }

    fun playbackState(): PlaybackCapabilityState = when (request.phase) {
        SyntheticPhase.unavailable -> PlaybackCapabilityState.unavailable
        SyntheticPhase.permissionRequired -> PlaybackCapabilityState.permissionRequired
        SyntheticPhase.permissionDenied -> PlaybackCapabilityState.permissionDenied
        SyntheticPhase.approvalRequired -> PlaybackCapabilityState.approvalRequired
        SyntheticPhase.ready -> PlaybackCapabilityState.ready
        SyntheticPhase.cancelled -> PlaybackCapabilityState.cancelled
    }

    fun cameraState(): CameraCapabilityState = when (request.phase) {
        SyntheticPhase.unavailable -> CameraCapabilityState.unavailable
        SyntheticPhase.permissionRequired -> CameraCapabilityState.permissionRequired
        SyntheticPhase.permissionDenied -> CameraCapabilityState.permissionDenied
        SyntheticPhase.approvalRequired -> CameraCapabilityState.approvalRequired
        SyntheticPhase.ready -> CameraCapabilityState.ready
        SyntheticPhase.cancelled -> CameraCapabilityState.cancelled
    }

    fun shareState(): ShareCapabilityState = when (request.phase) {
        SyntheticPhase.unavailable -> ShareCapabilityState.unavailable
        SyntheticPhase.permissionRequired -> ShareCapabilityState.permissionRequired
        SyntheticPhase.permissionDenied -> ShareCapabilityState.permissionDenied
        SyntheticPhase.approvalRequired -> ShareCapabilityState.approvalRequired
        SyntheticPhase.ready -> ShareCapabilityState.ready
        SyntheticPhase.cancelled -> ShareCapabilityState.cancelled
    }
}
