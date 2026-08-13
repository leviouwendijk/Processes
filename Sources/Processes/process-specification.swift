import Foundation

public struct ProcessSpecification:
    Sendable,
    Equatable
{
    public let executable: ProcessExecutable
    public let arguments: [String]
    public let workingDirectory: URL?
    public let environment: ProcessEnvironment
    public let input: ProcessInput
    public let io: ProcessIO
    public let outputLimit: Int
    public let timeout: Duration?
    public let terminationPolicy: ProcessTerminationPolicy

    public init(
        executable: ProcessExecutable,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        environment: ProcessEnvironment = .inherited,
        input: ProcessInput = .none,
        io: ProcessIO = .pipes,
        outputLimit: Int = 16 * 1024 * 1024,
        timeout: Duration? = nil,
        terminationPolicy: ProcessTerminationPolicy = .managed
    ) {
        self.executable = executable
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.input = input
        self.io = io
        self.outputLimit = outputLimit
        self.timeout = timeout
        self.terminationPolicy = terminationPolicy
    }
}
