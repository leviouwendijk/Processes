import Foundation

public struct ProcessResult:
    Sendable
{
    public let processIdentifier: Int64
    public let exit: ProcessExit
    public let stdout: Data
    public let stderr: Data

    public init(
        processIdentifier: Int64,
        exit: ProcessExit,
        stdout: Data,
        stderr: Data
    ) {
        self.processIdentifier = processIdentifier
        self.exit = exit
        self.stdout = stdout
        self.stderr = stderr
    }

    public var isSuccess: Bool {
        exit.isSuccess
    }

    public var exitCode: Int32? {
        exit.exitCode
    }

    public var signal: Int32? {
        exit.signal
    }

    public var stdoutText: String {
        String(
            decoding: stdout,
            as: UTF8.self
        )
    }

    public var stderrText: String {
        String(
            decoding: stderr,
            as: UTF8.self
        )
    }
}
