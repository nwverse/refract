import RefractIR

extension Generation {
    /// The benchmark slice deliberately supports only a direct, unambiguous HStack child weight.
    func stackChildren(_ children: [ViewNode], parentAxis: ViewNode.StackAxis) throws -> [ViewNode] {
        try children.map { child in
            let modifiers: [Modifier]
            switch child {
            case let .stack(_, _, values, _), let .layout(_, _, values, _), let .text(_, values, _),
                 let .image(_, values, _), let .scroll(_, _, values, _), let .list(_, values, _):
                modifiers = values
            default:
                modifiers = []
            }
            let priorities = modifiers.filter { $0.name == "layoutPriority" }
            guard !priorities.isEmpty else { return child }
            guard parentAxis == .horizontal, priorities.count == 1, priorities[0].arguments.count == 1,
                  case let .numberLiteral(priority) = priorities[0].arguments[0].value, priority == "1" else {
                throw Diagnostic(code: "RFVIEW003",
                    message: "The supported stack-child layoutPriority is exactly 1 on a direct HStack child.",
                    suggestion: "Apply `.layoutPriority(1)` directly to a supported HStack child; other layout weights are outside this slice.",
                    location: priorities[0].location)
            }
            return child
        }
    }
}
