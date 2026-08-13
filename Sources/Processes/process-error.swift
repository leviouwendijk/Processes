import Foundation

public enum ProcessError:
    Error,
    Sendable,
    Equatable,
    LocalizedError
{
    case timedOut(
        Duration
    )

    case outputLimitExceeded(
        stream: ProcessOutputStream,
        limit: Int
    )

    case pseudoTerminalUnavailable

    case pseudoTerminalUnsupportedInput

    case pseudoTerminalOpenFailed(
        errno: Int32
    )

    case pseudoTerminalConfigurationFailed(
        code: Int32
    )

    case processSpawnFailed(
        errno: Int32
    )

    case pseudoTerminalPollFailed(
        errno: Int32
    )

    case pseudoTerminalReadFailed(
        errno: Int32
    )

    case processWaitFailed(
        errno: Int32
    )

    public var errorDescription: String? {
        switch self {
        case .timedOut(let timeout):
            return "Process exceeded its timeout of \(timeout)."

        case .outputLimitExceeded(let stream, let limit):
            return "Process \(stream) exceeded its output limit of \(limit) bytes."

        case .pseudoTerminalUnavailable:
            return "Pseudo-terminal execution is unavailable on this platform."

        case .pseudoTerminalUnsupportedInput:
            return "Supplying ProcessInput to pseudo-terminal execution is not supported yet."

        case .pseudoTerminalOpenFailed(let error):
            return "Failed to open pseudo-terminal with errno \(error)."

        case .pseudoTerminalConfigurationFailed(let code):
            return "Failed to configure pseudo-terminal process with code \(code)."

        case .processSpawnFailed(let error):
            return "Failed to spawn process with errno \(error)."

        case .pseudoTerminalPollFailed(let error):
            return "Failed while polling pseudo-terminal with errno \(error)."

        case .pseudoTerminalReadFailed(let error):
            return "Failed while reading pseudo-terminal with errno \(error)."

        case .processWaitFailed(let error):
            return "Failed while waiting for process with errno \(error)."
        }
    }
}
