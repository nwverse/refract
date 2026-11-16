import RefractIR

func emitArkModels(_ models: [ModelProtocol], into writer: inout ArkWriter) throws {
    for model in models {
        guard ArkText.isIdentifier(model.name) else {
            throw Diagnostic(code: "arkui.invalid_model_name",
                             message: "Model `\(model.name)` is not a valid ArkTS interface identifier.",
                             suggestion: "Use a Swift protocol name made of letters, digits and underscores.",
                             location: model.location)
        }
        writer.line()
        writer.open("export interface \(model.name)")
        for property in model.properties {
            writer.line("\(property.name): \(try arkModelType(property.type));")
        }
        for action in model.actions {
            let parameters = try action.parameters.map {
                "\($0.localName): \(try arkModelType($0.type))"
            }.joined(separator: ", ")
            writer.line("\(action.name)(\(parameters)): void;")
        }
        writer.close()
    }
}

func arkModelType(_ type: ValueType) throws -> String {
    switch type {
    case .string: "string"
    case .bool: "boolean"
    case .int, .double: "number"
    }
}
