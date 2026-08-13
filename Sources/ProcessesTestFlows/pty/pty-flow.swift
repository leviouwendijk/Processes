import Darwin
import Foundation
import Processes
import TestFlows

extension ProcessesFlowSuite {
    static var ptyFlow: TestFlow {
        TestFlow(
            "pty",
            tags: [
                "process",
                "pty",
                "lifetime",
                "streaming",
            ]
        ) {
            Step("attach standard descriptors to pseudo terminal") {
                let result = try await ProcessRunner().run(
                    .init(
                        executable: .path(
                            "/bin/sh"
                        ),
                        arguments: [
                            "-c",
                            "test -t 0 && test -t 1 && test -t 2",
                        ],
                        io: .pseudoTerminal
                    )
                )

                try Expect.true(
                    result.isSuccess,
                    "stdin stdout and stderr are terminal-backed"
                )
            }

            Step("merge stdout and stderr into terminal transcript") {
                let stdoutRecorder = PTYOutputRecorder()
                let stderrRecorder = PTYOutputRecorder()

                let result = try await ProcessRunner().run(
                    .init(
                        executable: .path(
                            "/bin/sh"
                        ),
                        arguments: [
                            "-c",
                            "printf 'stdout-data'; printf 'stderr-data' >&2",
                        ],
                        io: .pseudoTerminal
                    ),
                    onStdout: { data in
                        await stdoutRecorder.append(
                            data
                        )
                    },
                    onStderr: { data in
                        await stderrRecorder.append(
                            data
                        )
                    }
                )

                try Expect.true(
                    result.stdoutText.contains(
                        "stdout-data"
                    ),
                    "PTY transcript contains stdout"
                )

                try Expect.true(
                    result.stdoutText.contains(
                        "stderr-data"
                    ),
                    "PTY transcript contains stderr"
                )

                try Expect.equal(
                    result.stderr,
                    Data(),
                    "PTY result keeps dedicated stderr empty"
                )

                try Expect.equal(
                    await stdoutRecorder.data(),
                    result.stdout,
                    "stdout observer receives merged PTY transcript"
                )

                try Expect.equal(
                    await stderrRecorder.data(),
                    Data(),
                    "stderr observer is unused for merged PTY output"
                )
            }

            Step("stream terminal output before completion") {
                let recorder = PTYOutputRecorder()

                let task = Task {
                    try await ProcessRunner().run(
                        .init(
                            executable: .path(
                                "/bin/sh"
                            ),
                            arguments: [
                                "-c",
                                "printf 'early'; /bin/sleep 1; printf 'late'",
                            ],
                            io: .pseudoTerminal
                        ),
                        onStdout: { data in
                            await recorder.append(
                                data
                            )
                        }
                    )
                }

                var observedEarly = false

                for _ in 0..<50 {
                    if
                        await recorder
                            .text()
                            .contains(
                                "early"
                            )
                    {
                        observedEarly = true
                        break
                    }

                    try await Task.sleep(
                        for: .milliseconds(
                            10
                        )
                    )
                }

                try Expect.true(
                    observedEarly,
                    "PTY output is observable before process completion"
                )

                let result = try await task.value

                try Expect.true(
                    result.stdoutText.contains(
                        "early"
                    ),
                    "captured transcript retains early output"
                )

                try Expect.true(
                    result.stdoutText.contains(
                        "late"
                    ),
                    "captured transcript retains later output"
                )
            }

            Step("apply PTY working directory") {
                let directory = FileManager
                    .default
                    .temporaryDirectory
                    .appendingPathComponent(
                        "processes-pty-\(UUID().uuidString)",
                        isDirectory: true
                    )

                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )

                defer {
                    try? FileManager.default.removeItem(
                        at: directory
                    )
                }

                let result = try await ProcessRunner().run(
                    .init(
                        executable: .path(
                            "/bin/pwd"
                        ),
                        workingDirectory: directory,
                        io: .pseudoTerminal
                    )
                )

                let reportedDirectory = URL(
                    fileURLWithPath: result
                        .stdoutText
                        .trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                )
                .resolvingSymlinksInPath()
                .standardizedFileURL

                let expectedDirectory = directory
                    .resolvingSymlinksInPath()
                    .standardizedFileURL

                try Expect.equal(
                    reportedDirectory.path,
                    expectedDirectory.path,
                    "PTY working directory is applied"
                )
            }

            Step("apply PTY environment") {
                let result = try await ProcessRunner().run(
                    .init(
                        executable: .path(
                            "/bin/sh"
                        ),
                        arguments: [
                            "-c",
                            "printf '%s' \"$PROCESSES_PTY_VALUE\"",
                        ],
                        environment: .inheritedUpdating(
                            [
                                "PROCESSES_PTY_VALUE": "works",
                            ]
                        ),
                        io: .pseudoTerminal
                    )
                )

                try Expect.equal(
                    result.stdoutText,
                    "works",
                    "PTY environment update reaches child"
                )
            }

            Step("preserve PTY ordinary exit status") {
                let result = try await ProcessRunner().run(
                    .init(
                        executable: .path(
                            "/bin/sh"
                        ),
                        arguments: [
                            "-c",
                            "exit 7",
                        ],
                        io: .pseudoTerminal
                    )
                )

                try Expect.equal(
                    result.exitCode ?? -1,
                    Int32(7),
                    "PTY ordinary exit status is preserved"
                )
            }

            Step("preserve PTY signal termination") {
                let result = try await ProcessRunner().run(
                    .init(
                        executable: .path(
                            "/bin/sh"
                        ),
                        arguments: [
                            "-c",
                            "kill -TERM $$",
                        ],
                        io: .pseudoTerminal
                    )
                )

                try Expect.equal(
                    result.signal ?? -1,
                    Int32(
                        SIGTERM
                    ),
                    "PTY signal termination remains typed as a signal"
                )

                try Expect.false(
                    result.isSuccess,
                    "PTY signal termination is not successful"
                )
            }

            Step("enforce PTY output limit") {
                var exceeded = false

                do {
                    _ = try await ProcessRunner().run(
                        .init(
                            executable: .path(
                                "/bin/sh"
                            ),
                            arguments: [
                                "-c",
                                "printf '123456789'",
                            ],
                            io: .pseudoTerminal,
                            outputLimit: 4
                        )
                    )
                } catch ProcessError.outputLimitExceeded(
                    let stream,
                    let limit
                ) {
                    exceeded =
                        stream == .stdout
                        && limit == 4
                }

                try Expect.true(
                    exceeded,
                    "PTY merged output obeys configured output limit"
                )
            }

            Step("timeout tears down PTY process") {
                var timedOut = false

                do {
                    _ = try await ProcessRunner().run(
                        .init(
                            executable: .path(
                                "/bin/sh"
                            ),
                            arguments: [
                                "-c",
                                "trap '' TERM; while :; do /bin/sleep 1; done",
                            ],
                            io: .pseudoTerminal,
                            timeout: .milliseconds(
                                100
                            ),
                            terminationPolicy: .init(
                                gracefulShutdownTimeout: .milliseconds(
                                    100
                                )
                            )
                        )
                    )
                } catch ProcessError.timedOut {
                    timedOut = true
                }

                try Expect.true(
                    timedOut,
                    "PTY timeout uses managed cancellation path"
                )
            }

            Step("cancellation tears down PTY descendant process group") {
                let directory = FileManager
                    .default
                    .temporaryDirectory
                    .appendingPathComponent(
                        "processes-pty-lifetime-\(UUID().uuidString)",
                        isDirectory: true
                    )

                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )

                defer {
                    try? FileManager.default.removeItem(
                        at: directory
                    )
                }

                let childPIDFile = directory
                    .appendingPathComponent(
                        "child.pid"
                    )

                let task = Task {
                    try await ProcessRunner().run(
                        .init(
                            executable: .path(
                                "/bin/sh"
                            ),
                            arguments: [
                                "-c",
                                """
                                trap '' TERM
                                /bin/sh -c 'trap "" TERM; while :; do /bin/sleep 1; done' &
                                echo $! > "$PROCESSES_PTY_CHILD_PID_FILE"
                                while :; do /bin/sleep 1; done
                                """,
                            ],
                            environment: .inheritedUpdating(
                                [
                                    "PROCESSES_PTY_CHILD_PID_FILE": childPIDFile.path,
                                ]
                            ),
                            io: .pseudoTerminal,
                            terminationPolicy: .init(
                                gracefulShutdownTimeout: .milliseconds(
                                    100
                                ),
                                isolateProcessGroup: true
                            )
                        )
                    )
                }

                let childPID = try await waitForPTYChildPID(
                    at: childPIDFile
                )

                try Expect.true(
                    ptyProcessExists(
                        childPID
                    ),
                    "PTY descendant exists before cancellation"
                )

                task.cancel()

                var cancelled = false

                do {
                    _ = try await task.value
                } catch is CancellationError {
                    cancelled = true
                }

                try Expect.true(
                    cancelled,
                    "PTY task cancellation propagates CancellationError"
                )

                try await Task.sleep(
                    for: .milliseconds(
                        100
                    )
                )

                try Expect.false(
                    ptyProcessExists(
                        childPID
                    ),
                    "PTY descendant is gone after managed cancellation"
                )
            }
        }
    }
}

private actor PTYOutputRecorder {
    private var recorded = Data()

    func append(
        _ data: Data
    ) {
        recorded.append(
            data
        )
    }

    func data() -> Data {
        recorded
    }

    func text() -> String {
        String(
            decoding: recorded,
            as: UTF8.self
        )
    }
}

private enum PTYFlowError:
    Error
{
    case childPIDWasNotWritten(
        URL
    )
}

private func waitForPTYChildPID(
    at url: URL
) async throws -> Int32 {
    for _ in 0..<100 {
        if
            let contents = try? String(
                contentsOf: url,
                encoding: .utf8
            ),
            let pid = Int32(
                contents.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            )
        {
            return pid
        }

        try await Task.sleep(
            for: .milliseconds(
                10
            )
        )
    }

    throw PTYFlowError.childPIDWasNotWritten(
        url
    )
}

private func ptyProcessExists(
    _ pid: Int32
) -> Bool {
    errno = 0

    let result = Darwin.kill(
        pid,
        0
    )

    return result == 0
        || errno == EPERM
}
