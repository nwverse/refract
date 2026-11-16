/// Ownership is explicit so backends never infer state by identifier spelling.
public enum ValueProperty: Codable, Equatable, Sendable {
    case state(String)
    case binding(String)
}

public enum WritableProperty: Codable, Equatable, Sendable {
    case state(String)
    case binding(String)
}

public enum StateAction: Codable, Equatable, Sendable {
    case assign(WritableProperty, Expression)
    case increment(WritableProperty, Expression)
}

public enum StringInterpolationSegment: Codable, Equatable, Sendable {
    case literal(String)
    case expression(Expression)
}
