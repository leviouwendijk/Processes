import Foundation
import Processes
import TestFlows

extension ProcessesFlowSuite {
    static var ioFlow: TestFlow {
        TestFlow(
            "io",
            tags: [
                "process",
                "io",
                "streaming",
            ]
        ) {
            Step("send stdin and collect stdout") {
                let result = try await ProcessRunner().run(
                    .init(
                        executable: .path(
                            "/bin/cat"
                        ),
                        input: .utf8(
                            "hello from stdin"
                        )
                    )
                )

                try Expect.true(
                    result.isSuccess,
                    "stdin process succeeds"
                )

                try Expect.equal(
                    result.stdoutText,
                    "hello from stdin",
                    "stdin reaches subprocess"
                )
            }

            Step("observe stdout and stderr while preserving collected output") {
                let recorder = ProcessOutputRecorder()

                let result = try await ProcessRunner().run(
                    .init(
                        executable: .path(
                            "/bin/sh"
                        ),
                        arguments: [
                            "-c",
                            "printf 'stdout-data'; printf 'stderr-data' >&2",
                        ]
                    ),
                    onStdout: { data in
                        await recorder.appendStdout(
                            data
                        )
                    },
                    onStderr: { data in
                        await recorder.appendStderr(
                            data
                        )
                    }
                )

                let observedStdout = await recorder.stdout()
                let observedStderr = await recorder.stderr()

                try Expect.equal(
                    observedStdout,
                    result.stdout,
                    "observed stdout matches collected stdout"
                )

                try Expect.equal(
                    observedStderr,
                    result.stderr,
                    "observed stderr matches collected stderr"
                )

                try Expect.equal(
                    result.stdoutText,
                    "stdout-data",
                    "stdout remains collected"
                )

                try Expect.equal(
                    result.stderrText,
                    "stderr-data",
                    "stderr remains collected"
                )
            }

            Step("stdout is observable before process completion") {
                let recorder = ProcessOutputRecorder()

                let task = Task {
                    try await ProcessRunner().run(
                        .init(
                            executable: .path(
                                "/bin/sh"
                            ),
                            arguments: [
                                "-c",
                                "printf 'early'; /bin/sleep 1; printf 'late'",
                            ]
                        ),
                        onStdout: { data in
                            await recorder.appendStdout(
                                data
                            )
                        }
                    )
                }

                var sawEarlyOutput = false

                for _ in 0..<30 {
                    let output = await recorder.stdoutText()

                    if output.contains(
                        "early"
                    ) {
                        sawEarlyOutput = true
                        break
                    }

                    try await Task.sleep(
                        for: .milliseconds(
                            10
                        )
                    )
                }

                try Expect.true(
                    sawEarlyOutput,
                    "stdout arrives before process exits"
                )

                let result = try await task.value

                try Expect.equal(
                    result.stdoutText,
                    "earlylate",
                    "all streamed stdout remains collected"
                )
            }

            Step("output limit is enforced while streaming") {
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
                            outputLimit: 4
                        ),
                        onStdout: { _ in
                        }
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
                    "streaming output obeys configured output limit"
                )
            }
        }
    }
}

private actor ProcessOutputRecorder {
    private var stdoutData = Data()
    private var stderrData = Data()

    func appendStdout(
        _ data: Data
    ) {
        stdoutData.append(
            data
        )
    }

    func appendStderr(
        _ data: Data
    ) {
        stderrData.append(
            data
        )
    }

    func stdout() -> Data {
        stdoutData
    }

    func stderr() -> Data {
        stderrData
    }

    func stdoutText() -> String {
        String(
            decoding: stdoutData,
            as: UTF8.self
        )
    }
}
