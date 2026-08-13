public struct ProcessTerminationPolicy:
    Sendable,
    Equatable
{
    public let gracefulShutdownTimeout: Duration
    public let isolateProcessGroup: Bool

    public init(
        gracefulShutdownTimeout: Duration = .seconds(2),
        isolateProcessGroup: Bool = true
    ) {
        self.gracefulShutdownTimeout = gracefulShutdownTimeout
        self.isolateProcessGroup = isolateProcessGroup
    }

    public static let managed = Self()
}
