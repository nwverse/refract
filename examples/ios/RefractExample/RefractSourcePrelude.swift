import SwiftUI

public protocol RefractModel {}
public protocol RefractNativeView: View {}

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

/// Application-owned semantic color roles. The values are system colors, so the existing light/dark theme wins.
public struct DesignColorToken {
    public let normal: Color
    public let disabled: Color
    public let pressed: Color
    public let focused: Color

    public init(normal: Color, disabled: Color, pressed: Color, focused: Color) {
        self.normal = normal
        self.disabled = disabled
        self.pressed = pressed
        self.focused = focused
    }

    public func resolve(enabled: Bool, pressed: Bool, focused: Bool) -> Color {
        if !enabled { return disabled }
        if pressed { return self.pressed }
        if focused { return self.focused }
        return normal
    }
}

public enum DesignColors {
    public static let action = DesignColorToken(
        normal: .accentColor, disabled: .secondary, pressed: .indigo, focused: .orange
    )
    public static let content = Color.primary
}

public enum DesignTypography {
    public static let body = Font.body
}

public enum DesignSpacing {
    public static let medium = CGFloat(12)
}

public enum DesignRadius {
    public static let medium = CGFloat(8)
}

/// This is an ordinary application-owned SwiftUI state mapping on iOS, not a discarded-state shim.
@inlinable
@inline(__always)
public func refractInteractionColor(_ token: DesignColorToken, enabled: Bool, pressed: Bool, focused: Bool) -> Color {
    token.resolve(enabled: enabled, pressed: pressed, focused: focused)
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
