import Foundation

/// Incremental output and lifetime events from a persistent process session.
public enum ProcessSessionEvent:
    Sendable
{
    case stdout(Data)
    case stderr(Data)
    case exited(ProcessExit)
}
