import Foundation

public typealias ProcessOutputHandler =
    @Sendable (Data) async -> Void
