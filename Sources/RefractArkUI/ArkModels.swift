import RefractIR

func emitArkItemTypes(_ items: [ItemType], into writer: inout ArkWriter) throws {
    for item in items {
        writer.line()
        writer.line("@ObservedV2")
        writer.open("export class \(item.name)")
        for property in item.properties {
            writer.line("@Trace \(property.name): \(try property.enumName ?? arkModelType(property.type));")
        }
        writer.line()
        writer.open("constructor(\(try item.properties.map { "\($0.name): \(try $0.enumName ?? arkModelType($0.type))" }.joined(separator: ", ")))")
        for property in item.properties { writer.line("this.\(property.name) = \(property.name);") }
        writer.close()
        writer.close()
    }
}

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
            let type = if property.effect == .text {
                "string | null | undefined"
            } else {
                try property.collection.map { "BasicDataSource<\($0.itemType)>" } ?? arkModelType(property.type)
            }
            writer.line("\(property.name): \(type);")
        }
        for property in model.projectedCollections {
            guard let item = model.properties.compactMap(\.collection).first?.itemType else { continue }
            writer.line("\(property): BasicDataSource<\(item)>;")
        }
        for action in model.actions {
            let parameters = try action.parameters.map {
                "\($0.localName): \(try arkModelType($0.type))"
            }.joined(separator: ", ")
            writer.line("\(action.name)(\(parameters)): \(action.effect == .asyncAttempt ? "boolean" : "void");")
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
