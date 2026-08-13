public enum ProcessEnvironment:
    Sendable,
    Equatable
{
    case inherited
    case inheritedUpdating(
        [String: String?]
    )
    case custom(
        [String: String]
    )
}
