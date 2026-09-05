import Foundation

public enum ProcessSessionError:
    Error,
    Sendable,
    LocalizedError
{
    case inputFinished
    case sessionFinished

    public var errorDescription: String? {
        switch self {
        case .inputFinished:
            return "Process session standard input has already been finished."

        case .sessionFinished:
            return "Process session has already finished."
        }
    }
}
