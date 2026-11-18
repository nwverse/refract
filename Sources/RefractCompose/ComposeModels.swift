import RefractIR

func emitComposeModels(_ models: [ModelProtocol], into out: inout KotlinWriter) throws {
    for model in models {
        out.line()
        out.open("public interface \(model.name)")
        for property in model.properties {
            let type = if let collection = property.collection {
                "State<List<\(collection.itemType)>>"
            } else if property.effect == .text {
                "State<String?>"
            } else {
                "State<\(try composeModelType(property.type))>"
            }
            out.line("public val \(property.name): \(type)")
        }
        for action in model.actions {
            let parameters = try action.parameters.map {
                "\($0.localName): \(try composeModelType($0.type))"
            }.joined(separator: ", ")
            let result = action.effect == .asyncAttempt ? ": Boolean" : ""
            out.line("public fun \(action.name)(\(parameters))\(result)")
        }
        out.close()
    }
}

func emitComposeItemTypes(_ items: [ItemType], into out: inout KotlinWriter,
                          context: inout ComposeBackend.Context) throws {
    for item in items where !item.properties.isEmpty {
        context.imports.insert("androidx.compose.runtime.Immutable")
        out.line()
        out.line("@Immutable")
        out.open("public data class \(item.name)(")
        for property in item.properties {
            if let collection = property.collection {
                out.line("public val \(property.name): List<\(collection.itemType)>,")
            } else {
                out.line("public val \(property.name): \(try composeModelType(property.type)),")
            }
        }
        out.depth -= 1
        out.line(")")
    }
}

func composeModelType(_ type: ValueType) throws -> String {
    switch type {
    case .string: "String"
    case .bool: "Boolean"
    case .int: "Int"
    case .revision: "Long"
    case .double: "Double"
    }
}
