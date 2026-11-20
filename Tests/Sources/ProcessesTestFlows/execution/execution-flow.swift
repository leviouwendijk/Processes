import Foundation
import Processes
import TestFlows

extension ProcessesFlowSuite {
    static var executionFlow: TestFlow {
        TestFlow(
            "execution",
            tags: [
                "process",
                "execution",
            ]
        ) {
            Step("report process identifier at start") {
                let recorder = ProcessStartRecorder()

                let result = try await ProcessRunner().run(
                    .init(
                        executable: .path(
                            "/bin/sh"
                        ),
                        arguments: [
                            "-c",
                            "exit 0",
                        ]
                    ),
                    onStart: { pid in
                        await recorder.record(
                            pid
                        )
                    }
                )

                let startedPID = await recorder.value()

                try Expect.equal(
                    startedPID ?? -1,
                    result.processIdentifier,
                    "start callback reports actual process identifier"
                )
            }

            Step("execute process and collect stdout") {
                let result = try await ProcessRunner().run(
                    .init(
                        executable: .path(
                            "/bin/echo"
                        ),
                        arguments: [
                            "hello",
                        ]
                    )
                )

                try Expect.true(
                    result.isSuccess,
                    "process succeeds"
                )

                try Expect.equal(
                    result.exitCode ?? -1,
                    Int32(0),
                    "process exits zero"
                )

                try Expect.equal(
                    result.stdoutText.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                    "hello",
                    "stdout is collected"
                )
            }

            Step("preserve nonzero exit status") {
                let result = try await ProcessRunner().run(
                    .init(
                        executable: .path(
                            "/bin/sh"
                        ),
                        arguments: [
                            "-c",
                            "exit 7",
                        ]
                    )
                )

                try Expect.false(
                    result.isSuccess,
                    "nonzero exit is not successful"
                )

                try Expect.equal(
                    result.exitCode ?? -1,
                    Int32(7),
                    "nonzero exit code is preserved"
                )
            }

            Step("collect stderr independently") {
                let result = try await ProcessRunner().run(
                    .init(
                        executable: .path(
                            "/bin/sh"
                        ),
                        arguments: [
                            "-c",
                            "printf 'problem' >&2",
                        ]
                    )
                )

                try Expect.equal(
                    result.stderrText,
                    "problem",
                    "stderr is collected"
                )

                try Expect.equal(
                    result.stdoutText,
                    "",
                    "stderr does not leak into stdout"
                )
            }

            Step("apply working directory") {
                let directory = FileManager
                    .default
                    .temporaryDirectory
                    .appendingPathComponent(
                        "processes-\(UUID().uuidString)",
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
                        workingDirectory: directory
                    )
                )

                let reportedDirectory = URL(
                    fileURLWithPath: result.stdoutText
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
                    "working directory is applied"
                )
            }

            Step("apply inherited environment updates") {
                let result = try await ProcessRunner().run(
                    .init(
                        executable: .path(
                            "/usr/bin/env"
                        ),
                        environment: .inheritedUpdating(
                            [
                                "PROCESSES_TEST_VALUE": "works",
                            ]
                        )
                    )
                )

                try Expect.true(
                    result.stdoutText.contains(
                        "PROCESSES_TEST_VALUE=works"
                    ),
                    "environment update reaches child"
                )
            }

            Step("apply custom environment") {
                let result = try await ProcessRunner().run(
                    .init(
                        executable: .path(
                            "/usr/bin/env"
                        ),
                        environment: .custom(
                            [
                                "PROCESSES_ONLY_VALUE": "isolated",
                            ]
                        )
                    )
                )

                try Expect.true(
                    result.stdoutText.contains(
                        "PROCESSES_ONLY_VALUE=isolated"
                    ),
                    "custom environment reaches child"
                )

                try Expect.false(
                    result.stdoutText.contains(
                        "PROCESSES_TEST_VALUE=works"
                    ),
                    "custom environment does not inherit prior updates"
                )
            }
        }
    }
}


private actor ProcessStartRecorder {
    private var processIdentifier: Int64?

    func record(
        _ processIdentifier: Int64
    ) {
        self.processIdentifier =
            processIdentifier
    }

    func value() -> Int64? {
        processIdentifier
    }
}
