import Processes
import TestFlows

public struct ProcessFixture<Ready: Sendable>:
    TestFixture,
    Sendable
{
    public let process: ProcessSessionSpecification
    public let readiness: ProcessFixtureReadiness<Ready>
    public let startupTimeout: Duration
    public let captureLimit: Int

    public init(
        process: ProcessSessionSpecification,
        readiness: ProcessFixtureReadiness<Ready>,
        startupTimeout: Duration = .seconds(5),
        captureLimit: Int = 1024 * 1024
    ) {
        self.process = process
        self.readiness = readiness
        self.startupTimeout = startupTimeout
        self.captureLimit = max(
            0,
            captureLimit
        )
    }

    public func start() async throws -> ProcessFixtureHandle<Ready> {
        let session = try await ProcessSession.start(
            process
        )

        let state = ProcessFixtureState(
            readiness: readiness,
            captureLimit: captureLimit
        )

        let eventTask = Task {
            do {
                for try await event in session.events {
                    await state.receive(
                        event
                    )
                }

                await state.finishEventStream()
            } catch {
                await state.fail(
                    error
                )
            }
        }

        let startupTimeout = startupTimeout
        let timeoutTask = Task {
            do {
                try await Task.sleep(
                    for: startupTimeout
                )
            } catch {
                return
            }

            await state.fail(
                ProcessFixtureError.startupTimedOut(
                    startupTimeout
                )
            )
        }

        do {
            let ready = try await state.waitUntilReady()
            timeoutTask.cancel()

            return ProcessFixtureHandle(
                session: session,
                state: state,
                eventTask: eventTask,
                ready: ready
            )
        } catch {
            timeoutTask.cancel()

            await session.terminate()
            _ = try? await session.wait()
            await eventTask.value

            let snapshot = await state.snapshot()

            throw TestFixtureFailure(
                phase: .start,
                primaryDiagnostics: TestFlowErrorDiagnostics.diagnostics(
                    for: error
                ),
                fixtureDiagnostics: processFixtureDiagnostics(
                    processIdentifier: session.processIdentifier,
                    snapshot: snapshot
                )
            )
        }
    }
}
