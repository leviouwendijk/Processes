import Foundation
import Processes
import TestFlows

public actor ProcessFixtureHandle<Ready: Sendable>:
    TestFixtureHandle
{
    public nonisolated let processIdentifier: Int64
    public nonisolated let ready: Ready

    private let session: ProcessSession
    private let state: ProcessFixtureState<Ready>
    private let eventTask: Task<Void, Never>

    private var didTeardown = false

    init(
        session: ProcessSession,
        state: ProcessFixtureState<Ready>,
        eventTask: Task<Void, Never>,
        ready: Ready
    ) {
        self.processIdentifier = session.processIdentifier
        self.ready = ready
        self.session = session
        self.state = state
        self.eventTask = eventTask
    }

    public func write(
        _ data: Data
    ) async throws {
        try await session.write(
            data
        )
    }

    public func finishInput() async throws {
        try await session.finishInput()
    }

    public func wait() async throws -> ProcessExit {
        do {
            let exit = try await session.wait()
            await eventTask.value
            return exit
        } catch {
            await eventTask.value
            throw error
        }
    }

    public func snapshot() async -> ProcessFixtureSnapshot {
        await state.snapshot()
    }

    public func diagnostics() async -> [TestFlowDiagnostic] {
        let snapshot = await state.snapshot()

        return processFixtureDiagnostics(
            processIdentifier: processIdentifier,
            snapshot: snapshot
        )
    }

    public func teardown() async throws {
        guard !didTeardown else {
            return
        }

        didTeardown = true

        if await !state.hasExited() {
            await session.terminate()
        }

        do {
            _ = try await session.wait()
            await eventTask.value
        } catch {
            await eventTask.value
            throw error
        }
    }
}
