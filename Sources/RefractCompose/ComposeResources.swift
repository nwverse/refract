import RefractIR
import RefractMapping

extension ComposeBackend {
    /// Emits the app's fully qualified resource class; the Kotlin output package is not its resource namespace.
    func composeResource(_ name: String, kind: AssetKind, mapping: Mapping,
                         location: SourceLocation?) throws -> String {
        _ = try AssetCatalog.resolveBoth(name, kind: kind, mapping: mapping, location: location)
        guard let resourceClass = mapping.android.resources.className else {
            throw Diagnostic(code: "R.asset.namespace", message: "Android \(kind.rawValue) assets require the app R class.",
                             suggestion: "Set `android.resources.className` to the consuming app's fully qualified R class", location: location)
        }
        let type = switch kind { case .image: "drawable"; case .font, .raw: kind.rawValue }
        return "\(resourceClass).\(type).\(name)"
    }

    func composeFontFamily(_ name: String, mapping: Mapping, location: SourceLocation?,
                           context: inout Context) throws -> String {
        let resource = try composeResource(name, kind: .font, mapping: mapping, location: location)
        context.imports.insert("androidx.compose.ui.text.font.Font")
        context.imports.insert("androidx.compose.ui.text.font.FontFamily")
        return "FontFamily(Font(\(resource)))"
    }
}
