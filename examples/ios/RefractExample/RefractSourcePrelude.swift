import SwiftUI

public protocol RefractModel {}
public protocol RefractNativeView: View {}

public extension Array {
    /// The SwiftUI source already performs the bounded filter and sort; naming the
    /// projection for native generation must not change its iOS value or ordering.
    @inlinable
    @inline(__always)
    func refractProjection(name: String) -> Self { self }
}

/// Typed design spacing for the shared source's named container-spacing values.
public struct RefractSpacing: Sendable {
    public let value: CGFloat

    public init(value: CGFloat) {
        self.value = value
    }

    public static let small = Self(value: 4)
    public static let medium = Self(value: 8)
}

public extension VStack {
    init(alignment: HorizontalAlignment = .center,
         spacing: RefractSpacing,
         @ViewBuilder content: () -> Content) {
        self.init(alignment: alignment, spacing: spacing.value, content: content)
    }
}

public extension HStack {
    init(alignment: VerticalAlignment = .center,
         spacing: RefractSpacing,
         @ViewBuilder content: () -> Content) {
        self.init(alignment: alignment, spacing: spacing.value, content: content)
    }
}

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
