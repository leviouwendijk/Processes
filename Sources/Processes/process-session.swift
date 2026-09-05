import Foundation
import Subprocess

#if canImport(System)
import System
#else
import SystemPackage
#endif

/// A long-lived subprocess with explicit asynchronous stdin and streamed output.
///
/// `ProcessRunner` remains the run-to-completion API. `ProcessSession` is for
/// protocols and services whose process must remain alive across multiple
/// request/response exchanges.
///
/// The underlying Subprocess `Execution` and `StandardInputWriter` never escape
/// their owning run closure. Calls to `write(_:)` are forwarded through an
/// internal command stream and performed inside that closure.
public actor ProcessSession {
    public nonisolated let processIdentifier: Int64

    /// Incremental stdout, stderr, and terminal-exit events.
    ///
    /// The stream is intended to have one consuming owner. Bytes are not
    /// accumulated by Processes, which makes the surface suitable for
    /// long-lived framed protocols.
    public nonisolated let events:
        AsyncThrowingStream<ProcessSessionEvent, any Error>

    private let bridge: ProcessSessionBridge
    private let task: Task<Void, Never>

    private var inputFinished = false

    private init(
        processIdentifier: Int64,
        bridge: ProcessSessionBridge,
        task: Task<Void, Never>
    ) {
        self.processIdentifier = processIdentifier
        self.events = bridge.events
        self.bridge = bridge
        self.task = task
    }

    /// Start the process and return after the child has actually spawned.
    public static func start(
        _ specification: ProcessSessionSpecification
    ) async throws -> ProcessSession {
        let bridge = ProcessSessionBridge()

        let task = Task {
            await ProcessSessionRuntime.run(
                specification,
                bridge: bridge
            )
        }

        do {
            let processIdentifier = try await bridge.waitUntilStarted()

            return ProcessSession(
                processIdentifier: processIdentifier,
                bridge: bridge,
                task: task
            )
        } catch {
            task.cancel()
            throw error
        }
    }

    /// Write bytes to the still-open standard input stream.
    public func write(
        _ data: Data
    ) async throws {
        guard !inputFinished else {
            throw ProcessSessionError.inputFinished
        }

        try await bridge.send(
            .write(
                data
            )
        )
    }

    /// Close standard input after all previously submitted writes.
    ///
    /// This operation is idempotent.
    public func finishInput() async throws {
        guard !inputFinished else {
            return
        }

        try await bridge.send(
            .finish
        )

        inputFinished = true
    }

    /// Wait for the child process to terminate normally or by signal.
    public func wait() async throws -> ProcessExit {
        try await bridge.waitForExit()
    }

    /// Cancel the managed session.
    ///
    /// The existing `ProcessTerminationPolicy` is projected into
    /// swift-subprocess teardown behavior, so cancellation performs the same
    /// managed process-group teardown used elsewhere in Processes.
    public func terminate() async {
        await bridge.closeInput()
        task.cancel()
    }

    deinit {
        task.cancel()
    }
}

private enum ProcessSessionInputCommand:
    Sendable
{
    case write(Data)
    case finish
}

private enum ProcessSessionBodyCompletion:
    Sendable
{
    case inputFinished
    case outputFinished
}

private actor ProcessSessionBridge {
    nonisolated let inputStream:
        AsyncStream<ProcessSessionInputCommand>

    nonisolated let events:
        AsyncThrowingStream<ProcessSessionEvent, any Error>

    private let inputContinuation:
        AsyncStream<ProcessSessionInputCommand>.Continuation

    private let eventContinuation:
        AsyncThrowingStream<ProcessSessionEvent, any Error>.Continuation

    private var startResult:
        Result<Int64, any Error>?

    private var exitResult:
        Result<ProcessExit, any Error>?

    private var startWaiters: [
        CheckedContinuation<Int64, any Error>
    ] = []

    private var exitWaiters: [
        CheckedContinuation<ProcessExit, any Error>
    ] = []

    init() {
        let input = AsyncStream<ProcessSessionInputCommand>
            .makeStream()
        let events = AsyncThrowingStream<
            ProcessSessionEvent,
            any Error
        >
        .makeStream()

        self.inputStream = input.stream
        self.inputContinuation = input.continuation
        self.events = events.stream
        self.eventContinuation = events.continuation
    }

    func markStarted(
        processIdentifier: Int64
    ) {
        guard startResult == nil else {
            return
        }

        startResult = .success(
            processIdentifier
        )

        let waiters = startWaiters
        startWaiters.removeAll()

        for waiter in waiters {
            waiter.resume(
                returning: processIdentifier
            )
        }
    }

    func waitUntilStarted() async throws -> Int64 {
        if let startResult {
            return try startResult.get()
        }

        return try await withCheckedThrowingContinuation {
            continuation in

            startWaiters.append(
                continuation
            )
        }
    }

    func send(
        _ command: ProcessSessionInputCommand
    ) throws {
        guard exitResult == nil else {
            throw ProcessSessionError.sessionFinished
        }

        inputContinuation.yield(
            command
        )
    }

    func closeInput() {
        inputContinuation.finish()
    }

    func emit(
        _ event: ProcessSessionEvent
    ) {
        guard exitResult == nil else {
            return
        }

        eventContinuation.yield(
            event
        )
    }

    func complete(
        exit: ProcessExit
    ) {
        guard exitResult == nil else {
            return
        }

        inputContinuation.finish()

        eventContinuation.yield(
            .exited(
                exit
            )
        )
        eventContinuation.finish()

        exitResult = .success(
            exit
        )

        if startResult == nil {
            startResult = .failure(
                ProcessSessionError.sessionFinished
            )

            let waiters = startWaiters
            startWaiters.removeAll()

            for waiter in waiters {
                waiter.resume(
                    throwing: ProcessSessionError.sessionFinished
                )
            }
        }

        let waiters = exitWaiters
        exitWaiters.removeAll()

        for waiter in waiters {
            waiter.resume(
                returning: exit
            )
        }
    }

    func fail(
        _ error: any Error
    ) {
        guard exitResult == nil else {
            return
        }

        inputContinuation.finish()
        eventContinuation.finish(
            throwing: error
        )

        exitResult = .failure(
            error
        )

        if startResult == nil {
            startResult = .failure(
                error
            )

            let waiters = startWaiters
            startWaiters.removeAll()

            for waiter in waiters {
                waiter.resume(
                    throwing: error
                )
            }
        }

        let waiters = exitWaiters
        exitWaiters.removeAll()

        for waiter in waiters {
            waiter.resume(
                throwing: error
            )
        }
    }

    func waitForExit() async throws -> ProcessExit {
        if let exitResult {
            return try exitResult.get()
        }

        return try await withCheckedThrowingContinuation {
            continuation in

            exitWaiters.append(
                continuation
            )
        }
    }
}

private enum ProcessSessionRuntime {
    static func run(
        _ specification: ProcessSessionSpecification,
        bridge: ProcessSessionBridge
    ) async {
        do {
            let result = try await Subprocess.run(
                subprocessExecutable(
                    specification.executable
                ),
                arguments: Subprocess.Arguments(
                    specification.arguments
                ),
                environment: subprocessEnvironment(
                    specification.environment
                ),
                workingDirectory: specification
                    .workingDirectory
                    .map {
                        FilePath(
                            $0.path
                        )
                    },
                platformOptions: subprocessPlatformOptions(
                    specification.terminationPolicy
                ),
                input: .inputWriter,
                output: Subprocess.SequenceOutput.sequence,
                error: Subprocess.SequenceOutput.sequence
            ) { execution in
                await bridge.markStarted(
                    processIdentifier: Int64(
                        execution
                            .processIdentifier
                            .value
                    )
                )

                try await withThrowingTaskGroup(
                    of: ProcessSessionBodyCompletion.self
                ) { group in
                    group.addTask {
                        var didFinishInput = false

                        inputLoop:
                        for await command in bridge.inputStream {
                            try Task.checkCancellation()

                            switch command {
                            case .write(let data):
                                _ = try await execution
                                    .standardInputWriter
                                    .write(
                                        Array(
                                            data
                                        )
                                    )

                            case .finish:
                                try await execution
                                    .standardInputWriter
                                    .finish()

                                didFinishInput = true
                                break inputLoop
                            }
                        }

                        if
                            !didFinishInput,
                            !Task.isCancelled
                        {
                            try await execution
                                .standardInputWriter
                                .finish()
                        }

                        return .inputFinished
                    }

                    group.addTask {
                        async let stdout: Void = {
                            for try await buffer in execution.standardOutput {
                                let chunk = buffer.withUnsafeBytes {
                                    Data(
                                        $0
                                    )
                                }

                                await bridge.emit(
                                    .stdout(
                                        chunk
                                    )
                                )
                            }
                        }()

                        async let stderr: Void = {
                            for try await buffer in execution.standardError {
                                let chunk = buffer.withUnsafeBytes {
                                    Data(
                                        $0
                                    )
                                }

                                await bridge.emit(
                                    .stderr(
                                        chunk
                                    )
                                )
                            }
                        }()

                        try await stdout
                        try await stderr

                        return .outputFinished
                    }

                    guard let first = try await group.next() else {
                        return
                    }

                    switch first {
                    case .outputFinished:
                        group.cancelAll()

                    case .inputFinished:
                        while let completion = try await group.next() {
                            if case .outputFinished = completion {
                                break
                            }
                        }

                        group.cancelAll()
                    }
                }
            }

            await bridge.complete(
                exit: processExit(
                    result.terminationStatus
                )
            )
        } catch {
            await bridge.fail(
                error
            )
        }
    }
}

private extension ProcessSessionRuntime {
    static func subprocessExecutable(
        _ executable: ProcessExecutable
    ) -> Subprocess.Executable {
        switch executable {
        case .name(let name):
            return .name(
                name
            )

        case .path(let path):
            return .path(
                FilePath(
                    path
                )
            )
        }
    }

    static func subprocessEnvironment(
        _ environment: ProcessEnvironment
    ) -> Subprocess.Environment {
        switch environment {
        case .inherited:
            return .inherit

        case .inheritedUpdating(let values):
            return .inherit.updating(
                subprocessEnvironmentUpdates(
                    values
                )
            )

        case .custom(let values):
            return .custom(
                subprocessEnvironmentValues(
                    values
                )
            )
        }
    }

    static func subprocessEnvironmentUpdates(
        _ values: [String: String?]
    ) -> [Subprocess.Environment.Key: String?] {
        Dictionary(
            uniqueKeysWithValues: values.map { key, value in
                (
                    subprocessEnvironmentKey(
                        key
                    ),
                    value
                )
            }
        )
    }

    static func subprocessEnvironmentValues(
        _ values: [String: String]
    ) -> [Subprocess.Environment.Key: String] {
        Dictionary(
            uniqueKeysWithValues: values.map { key, value in
                (
                    subprocessEnvironmentKey(
                        key
                    ),
                    value
                )
            }
        )
    }

    static func subprocessEnvironmentKey(
        _ value: String
    ) -> Subprocess.Environment.Key {
        Subprocess.Environment.Key(
            rawValue: value
        )!
    }

    static func subprocessPlatformOptions(
        _ policy: ProcessTerminationPolicy
    ) -> Subprocess.PlatformOptions {
        var options = Subprocess.PlatformOptions()

        #if !os(Windows)
        if policy.isolateProcessGroup {
            options.createSession = true
        }
        #endif

        options.teardownSequence = [
            .gracefulShutDown(
                toProcessGroup: policy.isolateProcessGroup,
                allowedDurationToNextStep: policy.gracefulShutdownTimeout
            ),
        ]

        return options
    }

    static func processExit(
        _ status: Subprocess.TerminationStatus
    ) -> ProcessExit {
        switch status {
        case .exited(let code):
            return .exited(
                Int32(
                    code
                )
            )

        #if !os(Windows)
        case .signaled(let signal):
            return .signaled(
                Int32(
                    signal
                )
            )
        #endif
        }
    }
}
