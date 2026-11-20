import Foundation
import Processes

public enum ProcessFixtureError:
    Error,
    Sendable,
    LocalizedError
{
    case startupTimedOut(Duration)
    case processExitedBeforeReady(ProcessExit)
    case eventStreamEndedBeforeReady

    public var errorDescription: String? {
        switch self {
        case .startupTimedOut(let timeout):
            return "Process fixture did not become ready within \(timeout)."

        case .processExitedBeforeReady(let exit):
            return "Process fixture exited before becoming ready: \(processFixtureExitDescription(exit))."

        case .eventStreamEndedBeforeReady:
            return "Process fixture event stream ended before readiness was established."
        }
    }
}

func processFixtureExitDescription(
    _ exit: ProcessExit
) -> String {
    switch exit {
    case .exited(let code):
        return "exited(\(code))"

    case .signaled(let signal):
        return "signaled(\(signal))"
    }
}
