import Foundation
import Processes
import TestFlows

extension ProcessesFlowSuite {
    static var sessionFlow: TestFlow {
        TestFlow(
            "session",
            tags: [
                "process",
                "session",
                "streaming",
                "stdin",
                "lifetime",
            ]
        ) {
            Step(
                "keep one process alive across repeated bidirectional exchanges"
            ) {
                let session = try await ProcessSession.start(
                    .init(
                        executable: .path(
                            "/bin/sh"
                        ),
                        arguments: [
                            "-c",
                            """
                            printf 'env:%s\\n' "$SESSION_VALUE" >&2
                            while IFS= read -r line; do
                                printf 'out:%s\\n' "$line"
                                printf 'err:%s\\n' "$line" >&2
                            done
                            """,
                        ],
                        environment: .inheritedUpdating(
                            [
                                "SESSION_VALUE": "ready",
                            ]
                        )
                    )
                )

                let capture = Task {
                    var stdout = Data()
                    var stderr = Data()
                    var exit: ProcessExit?

                    for try await event in session.events {
                        switch event {
                        case .stdout(let chunk):
                            stdout.append(
                                chunk
                            )

                        case .stderr(let chunk):
                            stderr.append(
                                chunk
                            )

                        case .exited(let value):
                            exit = value
                        }
                    }

                    return ProcessSessionCapture(
                        stdout: stdout,
                        stderr: stderr,
                        exit: exit
                    )
                }

                try await session.write(
                    Data(
                        "one\n".utf8
                    )
                )

                try await session.write(
                    Data(
                        "two\n".utf8
                    )
                )

                try await session.finishInput()

                let exit = try await session.wait()
                let captured = try await capture.value

                try Expect.equal(
                    exit,
                    .exited(
                        0
                    ),
                    "persistent session exit"
                )

                try Expect.equal(
                    captured.exit,
                    Optional(
                        .exited(
                            0
                        )
                    ),
                    "persistent session exit event"
                )

                try Expect.equal(
                    captured.stdoutText,
                    """
                    out:one
                    out:two

                    """,
                    "repeated writes share one stdout stream"
                )

                try Expect.equal(
                    captured.stderrText,
                    """
                    env:ready
                    err:one
                    err:two

                    """,
                    "environment and stderr remain available throughout session"
                )
            }
        }
    }
}

private struct ProcessSessionCapture:
    Sendable
{
    let stdout: Data
    let stderr: Data
    let exit: ProcessExit?

    var stdoutText: String {
        String(
            decoding: stdout,
            as: UTF8.self
        )
    }

    var stderrText: String {
        String(
            decoding: stderr,
            as: UTF8.self
        )
    }
}
