import Processes

public struct ProcessFixtureLine:
    Sendable,
    Equatable
{
    public let stream: ProcessOutputStream
    public let value: String

    public init(
        stream: ProcessOutputStream,
        value: String
    ) {
        self.stream = stream
        self.value = value
    }
}
