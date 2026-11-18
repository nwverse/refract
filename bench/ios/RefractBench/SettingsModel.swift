import SwiftUI

public protocol RefractModel: AnyObject {}

/// Typed design values used by the shared source. Generated platforms map these
/// names to their own native typography; this app maps them directly to SwiftUI.
public enum DesignTypography {
    public static let screenTitle = Font.title3
    public static let rowTitle = Font.body
    public static let rowSubtitle = Font.caption
}

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
@ViewBuilder
public func refractView<IOS: View, Android: View, HarmonyOS: View>(
    @ViewBuilder ios: () -> IOS,
    @ViewBuilder android: () -> Android,
    @ViewBuilder harmonyOS: () -> HarmonyOS
) -> IOS {
    ios()
}

/// Both screens use the same observation and immutable row replacement policy.
/// A change to one row publishes only the model's array change, not a timer or
/// polling mechanism owned by either implementation.
@MainActor
final class BenchmarkSettingsModel: ObservableObject, @preconcurrency SettingsModel {
    static let rowCount = 200

    let title = "Native settings"
    @Published private(set) var rows: [SettingRow]

    init() {
        rows = (0..<Self.rowCount).map { id in
            SettingRow(
                id: id,
                title: "Setting \(id)",
                subtitle: "Native setting row \(id)",
                enabled: id.isMultiple(of: 2)
            )
        }
    }

    func setEnabled(_ id: Int, value: Bool) {
        guard let index = rows.firstIndex(where: { $0.id == id }), rows[index].enabled != value else {
            return
        }
        var updated = rows
        updated[index] = SettingRow(
            id: id,
            title: rows[index].title,
            subtitle: rows[index].subtitle,
            enabled: value
        )
        rows = updated
    }
}
