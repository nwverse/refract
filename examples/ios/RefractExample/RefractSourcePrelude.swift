import SwiftUI

public protocol RefractModel {}
public protocol RefractNativeView: View {}

/// Source-level measurement declarations. The generator selects and lowers these
/// operations for their native targets; they have no effect on the iOS branch.
public enum RefractNativeModifier {
    case testTag(String)
    case contentDescription(String)
    case retainCallback(identity: String)
    case contentType(String)
}

public extension View {
    @inlinable
    @inline(__always)
    func refractNativeModifier(_ operations: RefractNativeModifier...) -> some View {
        self
    }

    @inlinable
    @inline(__always)
    func padding(horizontal: CGFloat, vertical: CGFloat) -> some View {
        padding(EdgeInsets(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal))
    }
}

@inlinable
@inline(__always)
public func refractValue<Value>(ios: Value, android: Value, harmonyOS: Value) -> Value {
    ios
}

@inlinable
@inline(__always)
@ViewBuilder
public func refractView<IOS: View, Android: View, HarmonyOS: View>(
    @ViewBuilder ios: () -> IOS,
    @ViewBuilder android: () -> Android,
    @ViewBuilder harmonyOS: () -> HarmonyOS
) -> IOS {
    ios()
}
