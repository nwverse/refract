import SwiftUI

enum PlaybackCapabilityState {
    case unavailable
    case permissionRequired
    case permissionDenied
    case approvalRequired
    case ready
    case cancelled
}

enum CameraCapabilityState {
    case unavailable
    case permissionRequired
    case permissionDenied
    case approvalRequired
    case ready
    case cancelled
}

enum ShareCapabilityState {
    case unavailable
    case permissionRequired
    case permissionDenied
    case approvalRequired
    case ready
    case cancelled
}

protocol PlaybackCapabilityModel: RefractModel {
    func requestPlaybackApproval()
    func cancelPlayback()
}

protocol CameraCapabilityModel: RefractModel {
    func requestCameraApproval()
    func cancelCamera()
}

protocol ShareCapabilityModel: RefractModel {
    func requestShareApproval()
    func cancelShare()
}

struct NativePlaybackCapability: RefractNativeView {
    let identifier: String
    let revision: Int
    let onCancel: () -> Void

    var body: some View {
        // An app-owned iOS player, not a media implementation supplied by Refract.
        Button("media.playback.cancel") { onCancel() }
    }
}

struct NativeCameraCapability: RefractNativeView {
    let identifier: String
    let revision: Int
    let onCancel: () -> Void

    var body: some View {
        // An app-owned iOS camera surface, not a camera supplied by Refract.
        Button("media.camera.cancel") { onCancel() }
    }
}

struct NativeShareCapability: RefractNativeView {
    let identifier: String
    let revision: Int
    let onCancel: () -> Void

    var body: some View {
        // An app-owned iOS sharing surface, not a share sheet supplied by Refract.
        Button("media.share.cancel") { onCancel() }
    }
}

struct PlaybackCapabilityScreen: View {
    let state: PlaybackCapabilityState
    let identifier: String
    let revision: Int
    let model: PlaybackCapabilityModel

    var body: some View {
        switch state {
        case .unavailable:
            Text("media.playback.unavailable")
        case .permissionRequired:
            Text("media.playback.permissionrequired")
        case .permissionDenied:
            Text("media.playback.permissiondenied")
        case .approvalRequired:
            VStack {
                Text("media.playback.approvalrequired")
                Button("media.playback.approve") { model.requestPlaybackApproval() }
                Button("media.playback.cancel") { model.cancelPlayback() }
            }
        case .ready:
            NativePlaybackCapability(
                identifier: identifier,
                revision: revision,
                onCancel: { model.cancelPlayback() }
            )
        case .cancelled:
            Text("media.playback.cancelled")
        }
    }
}

struct CameraCapabilityScreen: View {
    let state: CameraCapabilityState
    let identifier: String
    let revision: Int
    let model: CameraCapabilityModel

    var body: some View {
        switch state {
        case .unavailable:
            Text("media.camera.unavailable")
        case .permissionRequired:
            Text("media.camera.permissionrequired")
        case .permissionDenied:
            Text("media.camera.permissiondenied")
        case .approvalRequired:
            VStack {
                Text("media.camera.approvalrequired")
                Button("media.camera.approve") { model.requestCameraApproval() }
                Button("media.camera.cancel") { model.cancelCamera() }
            }
        case .ready:
            NativeCameraCapability(
                identifier: identifier,
                revision: revision,
                onCancel: { model.cancelCamera() }
            )
        case .cancelled:
            Text("media.camera.cancelled")
        }
    }
}

struct ShareCapabilityScreen: View {
    let state: ShareCapabilityState
    let identifier: String
    let revision: Int
    let model: ShareCapabilityModel

    var body: some View {
        switch state {
        case .unavailable:
            Text("media.share.unavailable")
        case .permissionRequired:
            Text("media.share.permissionrequired")
        case .permissionDenied:
            Text("media.share.permissiondenied")
        case .approvalRequired:
            VStack {
                Text("media.share.approvalrequired")
                Button("media.share.approve") { model.requestShareApproval() }
                Button("media.share.cancel") { model.cancelShare() }
            }
        case .ready:
            NativeShareCapability(
                identifier: identifier,
                revision: revision,
                onCancel: { model.cancelShare() }
            )
        case .cancelled:
            Text("media.share.cancelled")
        }
    }
}
