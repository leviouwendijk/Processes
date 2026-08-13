#if canImport(Darwin)

import Darwin
import Foundation

struct PseudoTerminalProcessRunner:
    Sendable
{
    func run(
        _ specification: ProcessSpecification,
        onOutput: ProcessOutputHandler?
    ) async throws -> ProcessResult {
        guard specification.input == .none else {
            throw ProcessError.pseudoTerminalUnsupportedInput
        }

        try Task.checkCancellation()

        let state = PseudoTerminalProcessState(
            policy: specification.terminationPolicy
        )

        return try await withTaskCancellationHandler(
            operation: {
                let worker = Task.detached {
                    try await runDetached(
                        specification,
                        state: state,
                        onOutput: onOutput
                    )
                }

                let result = try await worker.value

                try Task.checkCancellation()

                return result
            },
            onCancel: {
                state.requestTermination()
            }
        )
    }
}

private extension PseudoTerminalProcessRunner {
    func runDetached(
        _ specification: ProcessSpecification,
        state: PseudoTerminalProcessState,
        onOutput: ProcessOutputHandler?
    ) async throws -> ProcessResult {
        var master: Int32 = -1
        var slave: Int32 = -1

        guard
            openpty(
                &master,
                &slave,
                nil,
                nil,
                nil
            ) == 0
        else {
            throw ProcessError.pseudoTerminalOpenFailed(
                errno: errno
            )
        }

        defer {
            if master >= 0 {
                close(
                    master
                )
            }

            if slave >= 0 {
                close(
                    slave
                )
            }
        }

        let executable = executableString(
            specification.executable
        )

        var arguments: [UnsafeMutablePointer<CChar>?] =
            ([executable] + specification.arguments)
            .map {
                strdup(
                    $0
                )
            }

        arguments.append(
            nil
        )

        defer {
            arguments.forEach {
                if let pointer = $0 {
                    free(
                        pointer
                    )
                }
            }
        }

        let environment = processEnvironment(
            specification.environment
        )

        var environmentPointers: [UnsafeMutablePointer<CChar>?] =
            environment
            .sorted {
                $0.key < $1.key
            }
            .map {
                strdup(
                    "\($0.key)=\($0.value)"
                )
            }

        environmentPointers.append(
            nil
        )

        defer {
            environmentPointers.forEach {
                if let pointer = $0 {
                    free(
                        pointer
                    )
                }
            }
        }

        var fileActions: posix_spawn_file_actions_t? = nil

        try requireConfigurationSuccess(
            posix_spawn_file_actions_init(
                &fileActions
            )
        )

        defer {
            posix_spawn_file_actions_destroy(
                &fileActions
            )
        }

        try requireConfigurationSuccess(
            posix_spawn_file_actions_adddup2(
                &fileActions,
                slave,
                STDIN_FILENO
            )
        )

        try requireConfigurationSuccess(
            posix_spawn_file_actions_adddup2(
                &fileActions,
                slave,
                STDOUT_FILENO
            )
        )

        try requireConfigurationSuccess(
            posix_spawn_file_actions_adddup2(
                &fileActions,
                slave,
                STDERR_FILENO
            )
        )

        try requireConfigurationSuccess(
            posix_spawn_file_actions_addclose(
                &fileActions,
                master
            )
        )

        try requireConfigurationSuccess(
            posix_spawn_file_actions_addclose(
                &fileActions,
                slave
            )
        )

        if let directory = specification.workingDirectory {
            let result = directory.path.withCString {
                posix_spawn_file_actions_addchdir_np(
                    &fileActions,
                    $0
                )
            }

            try requireConfigurationSuccess(
                result
            )
        }

        var attributes: posix_spawnattr_t? = nil

        try requireConfigurationSuccess(
            posix_spawnattr_init(
                &attributes
            )
        )

        defer {
            posix_spawnattr_destroy(
                &attributes
            )
        }

        var attributeFlags: Int16 = 0

        if specification.terminationPolicy.isolateProcessGroup {
            try requireConfigurationSuccess(
                posix_spawnattr_setpgroup(
                    &attributes,
                    0
                )
            )

            attributeFlags |= Int16(
                POSIX_SPAWN_SETPGROUP
            )
        }

        var defaultSignals = sigset_t()

        sigemptyset(
            &defaultSignals
        )

        [
            SIGHUP,
            SIGINT,
            SIGQUIT,
            SIGPIPE,
            SIGTERM,
            SIGCHLD,
            SIGTSTP,
            SIGTTIN,
            SIGTTOU,
        ].forEach {
            sigaddset(
                &defaultSignals,
                $0
            )
        }

        try requireConfigurationSuccess(
            posix_spawnattr_setsigdefault(
                &attributes,
                &defaultSignals
            )
        )

        attributeFlags |= Int16(
            POSIX_SPAWN_SETSIGDEF
        )

        var emptySignalMask = sigset_t()

        sigemptyset(
            &emptySignalMask
        )

        try requireConfigurationSuccess(
            posix_spawnattr_setsigmask(
                &attributes,
                &emptySignalMask
            )
        )

        attributeFlags |= Int16(
            POSIX_SPAWN_SETSIGMASK
        )

        try requireConfigurationSuccess(
            posix_spawnattr_setflags(
                &attributes,
                attributeFlags
            )
        )

        var pid: pid_t = 0

        let spawnError = arguments.withUnsafeMutableBufferPointer {
            argumentBuffer in

            environmentPointers.withUnsafeMutableBufferPointer {
                environmentBuffer in

                switch specification.executable {
                case .path:
                    return posix_spawn(
                        &pid,
                        executable,
                        &fileActions,
                        &attributes,
                        argumentBuffer.baseAddress,
                        environmentBuffer.baseAddress
                    )

                case .name:
                    return posix_spawnp(
                        &pid,
                        executable,
                        &fileActions,
                        &attributes,
                        argumentBuffer.baseAddress,
                        environmentBuffer.baseAddress
                    )
                }
            }
        }

        close(
            slave
        )

        slave = -1

        guard spawnError == 0 else {
            throw ProcessError.processSpawnFailed(
                errno: spawnError
            )
        }

        state.register(
            pid: pid
        )

        let currentFlags = fcntl(
            master,
            F_GETFL,
            0
        )

        guard currentFlags != -1 else {
            let failure = errno

            state.forceTermination()

            _ = try? await waitForProcess(
                pid,
                state: state
            )

            throw ProcessError.pseudoTerminalConfigurationFailed(
                code: failure
            )
        }

        guard
            fcntl(
                master,
                F_SETFL,
                currentFlags | O_NONBLOCK
            ) != -1
        else {
            let failure = errno

            state.forceTermination()

            _ = try? await waitForProcess(
                pid,
                state: state
            )

            throw ProcessError.pseudoTerminalConfigurationFailed(
                code: failure
            )
        }

        var collected = Data()
        var readBuffer = [UInt8](
            repeating: 0,
            count: 8192
        )

        var descriptor = pollfd(
            fd: master,
            events: Int16(
                POLLIN
            ),
            revents: 0
        )

        var finishedReading = false
        var pendingError: ProcessError?

        while !finishedReading {
            state.advanceTermination()

            descriptor.revents = 0

            let pollResult = poll(
                &descriptor,
                1,
                50
            )

            if pollResult < 0 {
                if errno == EINTR {
                    continue
                }

                pendingError = .pseudoTerminalPollFailed(
                    errno: errno
                )

                state.forceTermination()
                break
            }

            if pollResult == 0 {
                continue
            }

            if
                (
                    descriptor.revents
                        & Int16(
                            POLLNVAL
                        )
                ) != 0
            {
                pendingError = .pseudoTerminalPollFailed(
                    errno: EBADF
                )

                state.forceTermination()
                break
            }

            let hasReadableEvent =
                (
                    descriptor.revents
                        & Int16(
                            POLLIN
                        )
                ) != 0

            let hasTerminalEvent =
                (
                    descriptor.revents
                        & Int16(
                            POLLHUP | POLLERR
                        )
                ) != 0

            if hasReadableEvent || hasTerminalEvent {
                while true {
                    let bytesRead = readBuffer.withUnsafeMutableBytes {
                        buffer in

                        Darwin.read(
                            master,
                            buffer.baseAddress,
                            buffer.count
                        )
                    }

                    if bytesRead > 0 {
                        let chunk = Data(
                            readBuffer.prefix(
                                bytesRead
                            )
                        )

                        guard
                            collected.count + chunk.count
                                <= specification.outputLimit
                        else {
                            pendingError = .outputLimitExceeded(
                                stream: .stdout,
                                limit: specification.outputLimit
                            )

                            state.forceTermination()
                            finishedReading = true
                            break
                        }

                        collected.append(
                            chunk
                        )

                        if let onOutput {
                            await onOutput(
                                chunk
                            )
                        }

                        continue
                    }

                    if bytesRead == 0 {
                        finishedReading = true
                        break
                    }

                    if
                        errno == EAGAIN
                        || errno == EWOULDBLOCK
                    {
                        if hasTerminalEvent {
                            finishedReading = true
                        }

                        break
                    }

                    if errno == EIO {
                        finishedReading = true
                        break
                    }

                    pendingError = .pseudoTerminalReadFailed(
                        errno: errno
                    )

                    state.forceTermination()
                    finishedReading = true
                    break
                }
            }
        }

        let status = try await waitForProcess(
            pid,
            state: state
        )

        if let pendingError {
            throw pendingError
        }

        return ProcessResult(
            processIdentifier: Int64(
                pid
            ),
            exit: processExit(
                status
            ),
            stdout: collected,
            stderr: Data()
        )
    }

    func executableString(
        _ executable: ProcessExecutable
    ) -> String {
        switch executable {
        case .name(let value):
            return value

        case .path(let value):
            return value
        }
    }

    func processEnvironment(
        _ environment: ProcessEnvironment
    ) -> [String: String] {
        switch environment {
        case .inherited:
            return ProcessInfo
                .processInfo
                .environment

        case .inheritedUpdating(let updates):
            var result = ProcessInfo
                .processInfo
                .environment

            for (key, value) in updates {
                if let value {
                    result[key] = value
                } else {
                    result.removeValue(
                        forKey: key
                    )
                }
            }

            return result

        case .custom(let values):
            return values
        }
    }

    func requireConfigurationSuccess(
        _ result: Int32
    ) throws {
        guard result == 0 else {
            throw ProcessError.pseudoTerminalConfigurationFailed(
                code: result
            )
        }
    }

    func waitForProcess(
        _ pid: pid_t,
        state: PseudoTerminalProcessState
    ) async throws -> Int32 {
        var status: Int32 = 0

        while true {
            let result = waitpid(
                pid,
                &status,
                WNOHANG
            )

            if result == pid {
                return status
            }

            if result == -1 {
                if errno == EINTR {
                    continue
                }

                throw ProcessError.processWaitFailed(
                    errno: errno
                )
            }

            state.advanceTermination()

            try? await Task.sleep(
                for: .milliseconds(
                    10
                )
            )
        }
    }

    func processExit(
        _ status: Int32
    ) -> ProcessExit {
        let signal = status & 0x7F

        if signal == 0 {
            return .exited(
                (status >> 8) & 0xFF
            )
        }

        return .signaled(
            signal
        )
    }
}

private final class PseudoTerminalProcessState:
    @unchecked Sendable
{
    private let lock = NSLock()
    private let clock = ContinuousClock()
    private let policy: ProcessTerminationPolicy

    private var pid: pid_t?
    private var terminationRequested = false
    private var gracefulSignalSentAt: ContinuousClock.Instant?
    private var forceSignalSent = false

    init(
        policy: ProcessTerminationPolicy
    ) {
        self.policy = policy
    }

    func register(
        pid: pid_t
    ) {
        var signal: Int32?

        lock.lock()

        self.pid = pid

        if forceSignalSent {
            signal = SIGKILL
        } else if
            terminationRequested
            && gracefulSignalSentAt == nil
        {
            gracefulSignalSentAt = clock.now
            signal = SIGTERM
        }

        lock.unlock()

        if let signal {
            send(
                signal,
                to: pid
            )
        }
    }

    func requestTermination() {
        var targetPID: pid_t?

        lock.lock()

        terminationRequested = true

        if
            !forceSignalSent,
            gracefulSignalSentAt == nil,
            let pid
        {
            gracefulSignalSentAt = clock.now
            targetPID = pid
        }

        lock.unlock()

        if let targetPID {
            send(
                SIGTERM,
                to: targetPID
            )
        }
    }

    func advanceTermination() {
        var targetPID: pid_t?

        lock.lock()

        if
            terminationRequested,
            !forceSignalSent,
            let sentAt = gracefulSignalSentAt,
            sentAt.duration(
                to: clock.now
            ) >= policy.gracefulShutdownTimeout,
            let pid
        {
            forceSignalSent = true
            targetPID = pid
        }

        lock.unlock()

        if let targetPID {
            send(
                SIGKILL,
                to: targetPID
            )
        }
    }

    func forceTermination() {
        var targetPID: pid_t?

        lock.lock()

        terminationRequested = true

        if !forceSignalSent {
            forceSignalSent = true
            targetPID = pid
        }

        lock.unlock()

        if let targetPID {
            send(
                SIGKILL,
                to: targetPID
            )
        }
    }

    private func send(
        _ signal: Int32,
        to pid: pid_t
    ) {
        let target =
            policy.isolateProcessGroup
            ? -pid
            : pid

        _ = Darwin.kill(
            target,
            signal
        )
    }
}

#else

import Foundation

struct PseudoTerminalProcessRunner:
    Sendable
{
    func run(
        _ specification: ProcessSpecification,
        onOutput: ProcessOutputHandler?
    ) async throws -> ProcessResult {
        throw ProcessError.pseudoTerminalUnavailable
    }
}

#endif
