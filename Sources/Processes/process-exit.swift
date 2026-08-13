public enum ProcessExit:
    Sendable,
    Equatable
{
    case exited(Int32)
    case signaled(Int32)

    public var exitCode: Int32? {
        switch self {
        case .exited(let code):
            return code

        case .signaled:
            return nil
        }
    }

    public var signal: Int32? {
        switch self {
        case .exited:
            return nil

        case .signaled(let signal):
            return signal
        }
    }

    public var isSuccess: Bool {
        switch self {
        case .exited(let code):
            return code == 0

        case .signaled:
            return false
        }
    }
}
