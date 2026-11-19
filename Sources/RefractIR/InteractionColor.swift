/// Explicit, app-owned interaction inputs for a mapped color. Refract never invents these values or
/// attaches them to an unrelated native control's interaction source.
public struct InteractionColorValue: Codable, Equatable, Sendable {
    public let token: String
    public let enabled: Expression
    public let pressed: Expression
    public let focused: Expression

    public init(token: String, enabled: Expression, pressed: Expression, focused: Expression) {
        self.token = token
        self.enabled = enabled
        self.pressed = pressed
        self.focused = focused
    }
}
