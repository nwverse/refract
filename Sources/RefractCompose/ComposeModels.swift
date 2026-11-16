import RefractIR

func emitComposeModels(_ models: [ModelProtocol], into out: inout KotlinWriter) throws {
    for model in models {
        out.line()
        out.open("public interface \(model.name)")
        for property in model.properties {
            out.line("public val \(property.name): State<\(try composeModelType(property.type))>")
        }
        for action in model.actions {
            let parameters = try action.parameters.map {
                "\($0.localName): \(try composeModelType($0.type))"
            }.joined(separator: ", ")
            out.line("public fun \(action.name)(\(parameters))")
        }
        out.close()
    }
}

func composeModelType(_ type: ValueType) throws -> String {
    switch type {
    case .string: "String"
    case .bool: "Boolean"
    case .int: "Int"
    case .double: "Double"
    }
}
