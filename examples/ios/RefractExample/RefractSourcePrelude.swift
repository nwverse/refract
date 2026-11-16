import SwiftUI

public protocol RefractModel {}
public protocol RefractNativeView: View {}

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
