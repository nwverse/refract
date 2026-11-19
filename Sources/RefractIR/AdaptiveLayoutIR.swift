public extension EnumDeclaration {
    /// WidthSizeClass is the only environment-derived enum in this bounded layout slice.
    /// Its cases are source alternatives, not device names or a new design system.
    var isWidthSizeClass: Bool { name == "WidthSizeClass" }
}
