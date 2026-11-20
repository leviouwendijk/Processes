import Foundation
import Processes

struct ProcessFixtureCapture:
    Sendable
{
    private(set) var data = Data()
    private(set) var truncated = false

    let limit: Int

    init(
        limit: Int
    ) {
        self.limit = max(
            0,
            limit
        )
    }

    mutating func append(
        _ chunk: Data
    ) {
        guard !chunk.isEmpty else {
            return
        }

        guard limit > 0 else {
            truncated = true
            return
        }

        data.append(
            chunk
        )

        guard data.count > limit else {
            return
        }

        data.removeFirst(
            data.count - limit
        )
        truncated = true
    }
}

actor ProcessFixtureState<Ready: Sendable> {
    private let readiness: ProcessFixtureReadiness<Ready>

    private var stdoutCapture: ProcessFixtureCapture
    private var stderrCapture: ProcessFixtureCapture

    private var stdoutPending: [UInt8] = []
    private var stderrPending: [UInt8] = []

    private var readyResult:
        Result<Ready, any Error>?

    private var readyWaiters: [
        CheckedContinuation<Ready, any Error>
    ] = []

    private var exit: ProcessExit?
    private var eventError: String?

    init(
        readiness: ProcessFixtureReadiness<Ready>,
        captureLimit: Int
    ) {
        self.readiness = readiness
        self.stdoutCapture = ProcessFixtureCapture(
            limit: captureLimit
        )
        self.stderrCapture = ProcessFixtureCapture(
            limit: captureLimit
        )
    }

    func receive(
        _ event: ProcessSessionEvent
    ) {
        switch event {
        case .stdout(let data):
            stdoutCapture.append(
                data
            )
            receiveReadinessBytes(
                data,
                stream: .stdout
            )

        case .stderr(let data):
            stderrCapture.append(
                data
            )
            receiveReadinessBytes(
                data,
                stream: .stderr
            )

        case .exited(let exit):
            self.exit = exit

            guard readyResult == nil else {
                return
            }

            resolveReady(
                .failure(
                    ProcessFixtureError.processExitedBeforeReady(
                        exit
                    )
                )
            )
        }
    }

    func fail(
        _ error: any Error
    ) {
        if eventError == nil {
            eventError = String(
                describing: error
            )
        }

        guard readyResult == nil else {
            return
        }

        resolveReady(
            .failure(
                error
            )
        )
    }

    func finishEventStream() {
        guard readyResult == nil else {
            return
        }

        resolveReady(
            .failure(
                ProcessFixtureError.eventStreamEndedBeforeReady
            )
        )
    }

    func waitUntilReady() async throws -> Ready {
        if let readyResult {
            return try readyResult.get()
        }

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Ready, any Error>) in

            readyWaiters.append(
                continuation
            )
        }
    }

    func snapshot() -> ProcessFixtureSnapshot {
        ProcessFixtureSnapshot(
            stdout: stdoutCapture.data,
            stderr: stderrCapture.data,
            stdoutTruncated: stdoutCapture.truncated,
            stderrTruncated: stderrCapture.truncated,
            exit: exit,
            eventError: eventError
        )
    }

    func hasExited() -> Bool {
        exit != nil
    }
}

private extension ProcessFixtureState {
    func receiveReadinessBytes(
        _ data: Data,
        stream: ProcessOutputStream
    ) {
        guard readyResult == nil else {
            return
        }

        switch stream {
        case .stdout:
            var pending = stdoutPending
            pending.append(
                contentsOf: data
            )
            stdoutPending = consumeLines(
                pending,
                stream: stream
            )

        case .stderr:
            var pending = stderrPending
            pending.append(
                contentsOf: data
            )
            stderrPending = consumeLines(
                pending,
                stream: stream
            )
        }
    }

    func consumeLines(
        _ bytes: [UInt8],
        stream: ProcessOutputStream
    ) -> [UInt8] {
        var pending = bytes

        while
            readyResult == nil,
            let newline = pending.firstIndex(of: 0x0A)
        {
            var lineBytes = Array(
                pending[..<newline]
            )

            pending.removeFirst(
                newline + 1
            )

            if lineBytes.last == 0x0D {
                lineBytes.removeLast()
            }

            let line = ProcessFixtureLine(
                stream: stream,
                value: String(
                    decoding: lineBytes,
                    as: UTF8.self
                )
            )

            do {
                guard let value = try readiness.resolve(
                    line
                ) else {
                    continue
                }

                resolveReady(
                    .success(
                        value
                    )
                )
            } catch {
                resolveReady(
                    .failure(
                        error
                    )
                )
            }
        }

        if readyResult != nil {
            stdoutPending.removeAll(
                keepingCapacity: false
            )
            stderrPending.removeAll(
                keepingCapacity: false
            )

            return []
        }

        return pending
    }

    func resolveReady(
        _ result: Result<Ready, any Error>
    ) {
        guard readyResult == nil else {
            return
        }

        readyResult = result

        let waiters = readyWaiters
        readyWaiters.removeAll()

        for waiter in waiters {
            switch result {
            case .success(let value):
                waiter.resume(
                    returning: value
                )

            case .failure(let error):
                waiter.resume(
                    throwing: error
                )
            }
        }
    }
}
