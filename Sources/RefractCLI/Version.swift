// The packaging script stamps this exact source revision into its clean source archive.
// A public GitHub source archive expands the same commit through export-subst.
enum RefractVersion {
    static let current = "0.1.0"
    static let sourceRevision = "$Format:%H$"
}
