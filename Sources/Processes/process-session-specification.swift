import Foundation

/// Launch configuration for a long-lived bidirectional subprocess session.
///
/// Unlike `ProcessSpecification`, this type intentionally has no initial input,
/// output capture limit, timeout, or terminal mode. A session keeps stdin open
/// for explicit writes and projects stdout/stderr incrementally as events.
public struct ProcessSessionSpecification:
    Sendable,
    Equatable
{
    public let executable: ProcessExecutable
    public let arguments: [String]
    public let workingDirectory: URL?
    public let environment: ProcessEnvironment
    public let terminationPolicy: ProcessTerminationPolicy

    public init(
        executable: ProcessExecutable,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        environment: ProcessEnvironment = .inherited,
        terminationPolicy: ProcessTerminationPolicy = .managed
    ) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.terminationPolicy = terminationPolicy
    }
}
