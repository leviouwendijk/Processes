import Foundation
import Subprocess

#if canImport(System)
import System
#else
import SystemPackage
#endif

public struct ProcessRunner:
    Sendable
{
    public init() {}

    public func run(
        _ specification: ProcessSpecification,
        onStart: ProcessStartHandler? = nil,
        onStdout: ProcessOutputHandler? = nil,
        onStderr: ProcessOutputHandler? = nil
    ) async throws -> ProcessResult {
        guard let timeout = specification.timeout else {
            return try await runManaged(
                specification,
                onStart: onStart,
                onStdout: onStdout,
                onStderr: onStderr
            )
        }

        return try await runManaged(
            specification,
            timeout: timeout,
            onStart: onStart,
            onStdout: onStdout,
            onStderr: onStderr
        )
    }
}

private extension ProcessRunner {
    struct CapturedOutput:
        Sendable
    {
        let stdout: Data
        let stderr: Data
    }

    struct SubprocessInputAdapter:
        Subprocess.InputProtocol,
        Sendable
    {
        let bytes: [UInt8]?

        func write(
            with writer: Subprocess.StandardInputWriter
        ) async throws {
            guard let bytes else {
                return
            }

            _ = try await writer.write(
                bytes
            )
        }
    }

    enum RaceResult:
        Sendable
    {
        case completed(
            ProcessResult
        )
        case timedOut
    }

    func runManaged(
        _ specification: ProcessSpecification,
        timeout: Duration,
        onStart: ProcessStartHandler?,
        onStdout: ProcessOutputHandler?,
        onStderr: ProcessOutputHandler?
    ) async throws -> ProcessResult {
        try await withThrowingTaskGroup(
            of: RaceResult.self,
            returning: ProcessResult.self
        ) { group in
            group.addTask {
                .completed(
                    try await runManaged(
                        specification,
                        onStart: onStart,
                        onStdout: onStdout,
                        onStderr: onStderr
                    )
                )
            }

            group.addTask {
                try await Task.sleep(
                    for: timeout
                )

                return .timedOut
            }

            guard let first = try await group.next() else {
                throw CancellationError()
            }

            group.cancelAll()

            switch first {
            case .completed(let result):
                return result

            case .timedOut:
                throw ProcessError.timedOut(
                    timeout
                )
            }
        }
    }

    func runManaged(
        _ specification: ProcessSpecification,
        onStart: ProcessStartHandler?,
        onStdout: ProcessOutputHandler?,
        onStderr: ProcessOutputHandler?
    ) async throws -> ProcessResult {
        switch specification.io {
        case .pipes:
            return try await runPiped(
                specification,
                onStart: onStart,
                onStdout: onStdout,
                onStderr: onStderr
            )

        case .pseudoTerminal:
            return try await PseudoTerminalProcessRunner().run(
                specification,
                onStart: onStart,
                onOutput: onStdout
            )
        }
    }

    func runPiped(
        _ specification: ProcessSpecification,
        onStart: ProcessStartHandler?,
        onStdout: ProcessOutputHandler?,
        onStderr: ProcessOutputHandler?
    ) async throws -> ProcessResult {
        try Task.checkCancellation()

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
                input: subprocessInput(
                    specification.input
                ),
                output: Subprocess.SequenceOutput.sequence,
                error: Subprocess.SequenceOutput.sequence
            ) { execution in
                if let onStart {
                    await onStart(
                        Int64(
                            execution
                                .processIdentifier
                                .value
                        )
                    )
                }

                async let stdout = collectOutput(
                    execution.standardOutput,
                    stream: .stdout,
                    limit: specification.outputLimit,
                    handler: onStdout
                )

                async let stderr = collectOutput(
                    execution.standardError,
                    stream: .stderr,
                    limit: specification.outputLimit,
                    handler: onStderr
                )

                let captured = try await (
                    stdout,
                    stderr
                )

                return CapturedOutput(
                    stdout: captured.0,
                    stderr: captured.1
                )
            }

            try Task.checkCancellation()

            return ProcessResult(
                processIdentifier: Int64(
                    result.processIdentifier.value
                ),
                exit: processExit(
                    result.terminationStatus
                ),
                stdout: result.closureResult.stdout,
                stderr: result.closureResult.stderr
            )
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }

            throw error
        }
    }

    func collectOutput(
        _ sequence: Subprocess.SubprocessOutputSequence,
        stream: ProcessOutputStream,
        limit: Int,
        handler: ProcessOutputHandler?
    ) async throws -> Data {
        var collected = Data()

        for try await buffer in sequence {
            let chunk = buffer.withUnsafeBytes {
                Data(
                    $0
                )
            }

            guard
                collected.count + chunk.count
                    <= limit
            else {
                throw ProcessError.outputLimitExceeded(
                    stream: stream,
                    limit: limit
                )
            }

            collected.append(
                chunk
            )

            if let handler {
                await handler(
                    chunk
                )
            }
        }

        return collected
    }

    func subprocessInput(
        _ input: ProcessInput
    ) -> SubprocessInputAdapter {
        switch input {
        case .none:
            return SubprocessInputAdapter(
                bytes: nil
            )

        case .data(let data):
            return SubprocessInputAdapter(
                bytes: Array(
                    data
                )
            )
        }
    }

    func subprocessExecutable(
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

    func subprocessEnvironment(
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

    func subprocessEnvironmentUpdates(
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

    func subprocessEnvironmentValues(
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

    func subprocessEnvironmentKey(
        _ value: String
    ) -> Subprocess.Environment.Key {
        Subprocess.Environment.Key(
            rawValue: value
        )!
    }

    func subprocessPlatformOptions(
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

    func processExit(
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
