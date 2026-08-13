import Darwin
import Foundation
import Processes
import TestFlows

extension ProcessesFlowSuite {
    static var lifetimeFlow: TestFlow {
        TestFlow(
            "lifetime",
            tags: [
                "process",
                "lifetime",
                "cancellation",
            ]
        ) {
            Step("normal completion remains unaffected by timeout") {
                let result = try await ProcessRunner().run(
                    .init(
                        executable: .path(
                            "/bin/echo"
                        ),
                        arguments: [
                            "completed",
                        ],
                        timeout: .seconds(2)
                    )
                )

                try Expect.true(
                    result.isSuccess,
                    "process completes normally before timeout"
                )

                try Expect.equal(
                    result.stdoutText.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                    "completed",
                    "normal output is preserved"
                )
            }

            Step("timeout cancels managed execution") {
                var timedOut = false

                do {
                    _ = try await ProcessRunner().run(
                        .init(
                            executable: .path(
                                "/bin/sleep"
                            ),
                            arguments: [
                                "30",
                            ],
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
                    "timeout is surfaced as ProcessError.timedOut"
                )
            }

            Step("explicit task cancellation propagates cancellation") {
                let task = Task {
                    try await ProcessRunner().run(
                        .init(
                            executable: .path(
                                "/bin/sleep"
                            ),
                            arguments: [
                                "30",
                            ],
                            terminationPolicy: .init(
                                gracefulShutdownTimeout: .milliseconds(
                                    100
                                )
                            )
                        )
                    )
                }

                try await Task.sleep(
                    for: .milliseconds(
                        100
                    )
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
                    "task cancellation remains cancellation at Processes boundary"
                )
            }

            Step("signal termination is preserved") {
                let result = try await ProcessRunner().run(
                    .init(
                        executable: .path(
                            "/bin/sh"
                        ),
                        arguments: [
                            "-c",
                            "kill -TERM $$",
                        ]
                    )
                )

                try Expect.equal(
                    result.signal ?? -1,
                    Int32(
                        SIGTERM
                    ),
                    "signal termination is preserved"
                )

                try Expect.false(
                    result.isSuccess,
                    "signal termination is not successful"
                )
            }

            Step("cancellation tears down descendant process group") {
                let directory = FileManager
                    .default
                    .temporaryDirectory
                    .appendingPathComponent(
                        "processes-lifetime-\(UUID().uuidString)",
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
                                echo $! > "$PROCESSES_CHILD_PID_FILE"
                                while :; do /bin/sleep 1; done
                                """,
                            ],
                            environment: .inheritedUpdating(
                                [
                                    "PROCESSES_CHILD_PID_FILE": childPIDFile.path,
                                ]
                            ),
                            terminationPolicy: .init(
                                gracefulShutdownTimeout: .milliseconds(
                                    100
                                ),
                                isolateProcessGroup: true
                            )
                        )
                    )
                }

                let childPID = try await waitForPID(
                    at: childPIDFile
                )

                try Expect.true(
                    processExists(
                        childPID
                    ),
                    "descendant process exists before cancellation"
                )

                task.cancel()

                do {
                    _ = try await task.value
                } catch is CancellationError {
                }

                try await Task.sleep(
                    for: .milliseconds(
                        100
                    )
                )

                try Expect.false(
                    processExists(
                        childPID
                    ),
                    "descendant process is gone after managed cancellation"
                )
            }
        }
    }
}

private enum LifetimeFlowError:
    Error
{
    case pidWasNotWritten(
        URL
    )
}

private func waitForPID(
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

    throw LifetimeFlowError.pidWasNotWritten(
        url
    )
}

private func processExists(
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
