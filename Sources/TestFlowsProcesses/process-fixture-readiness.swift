public struct ProcessFixtureReadiness<Value: Sendable>:
    Sendable
{
    let resolve:
        @Sendable (ProcessFixtureLine) throws -> Value?

    public init(
        _ resolve:
            @escaping @Sendable (ProcessFixtureLine) throws -> Value?
    ) {
        self.resolve = resolve
    }
}
