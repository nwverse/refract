import RefractIR

extension ViewNode {
    var hasLinkHandoff: Bool {
        if case let .native(component, _) = self,
           component.arguments.contains(where: { $0.type == .linkHandoff }) { return true }
        return children(for: .harmonyOS).contains { $0.hasLinkHandoff }
    }
}
