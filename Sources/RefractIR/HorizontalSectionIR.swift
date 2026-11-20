/// Bounded identified sections with one horizontal lazy row per section.
/// The outer list remains the only vertical lazy owner; the model owns the data source.
public struct HorizontalSectionCollection: Codable, Equatable, Sendable {
    public let collection: Expression
    public let modelType: String
    public let sectionName: String
    public let sectionType: String
    public let sectionKey: String
    public let sectionKeyType: ValueType
    public let titleProperty: String
    public let rows: HorizontalItemCollection
    public let location: SourceLocation?

    public init(collection: Expression, modelType: String, sectionName: String, sectionType: String,
                sectionKey: String = "id", sectionKeyType: ValueType, titleProperty: String,
                rows: HorizontalItemCollection, location: SourceLocation? = nil) {
        self.collection = collection
        self.modelType = modelType
        self.sectionName = sectionName
        self.sectionType = sectionType
        self.sectionKey = sectionKey
        self.sectionKeyType = sectionKeyType
        self.titleProperty = titleProperty
        self.rows = rows
        self.location = location
    }
}

public struct HorizontalItemCollection: Codable, Equatable, Sendable {
    public let property: String
    public let itemName: String
    public let itemType: String
    public let key: String
    public let keyType: ValueType
    public let content: ViewNode
    public let location: SourceLocation?

    public init(property: String, itemName: String, itemType: String, key: String = "id",
                keyType: ValueType, content: ViewNode, location: SourceLocation? = nil) {
        self.property = property
        self.itemName = itemName
        self.itemType = itemType
        self.key = key
        self.keyType = keyType
        self.content = content
        self.location = location
    }
}
