import Foundation
import Processes

public struct ProcessFixtureSnapshot:
    Sendable,
    Equatable
{
    public let stdout: Data
    public let stderr: Data
    public let stdoutTruncated: Bool
    public let stderrTruncated: Bool
    public let exit: ProcessExit?
    public let eventError: String?

    public init(
        stdout: Data,
        stderr: Data,
        stdoutTruncated: Bool,
        stderrTruncated: Bool,
        exit: ProcessExit?,
        eventError: String?
    ) {
        self.stdout = stdout
        self.stderr = stderr
        self.stdoutTruncated = stdoutTruncated
        self.stderrTruncated = stderrTruncated
        self.exit = exit
        self.eventError = eventError
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
