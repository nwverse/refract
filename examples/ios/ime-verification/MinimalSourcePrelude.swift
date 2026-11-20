import SwiftUI

/// The existing source-level iOS marker contracts required by the canonical
/// input host. This small test target does not import unrelated theme helpers.
public protocol RefractModel {}
public protocol RefractNativeView: View {}
public protocol RefractTextInputHost: View {}
