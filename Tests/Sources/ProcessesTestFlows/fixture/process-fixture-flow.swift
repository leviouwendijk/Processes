import Foundation
import Processes
import TestFlows
import TestFlowsProcesses

extension ProcessesFlowSuite {
    static var processFixtureFlow: TestFlow {
        TestFlow(
            "process-fixture",
            tags: [
                "process",
                "fixture",
                "integration",
            ]
        ) {
            Step("resolve typed readiness and preserve process exchange") {
                try await usingFixture(
                    processFixture(
                        mode: "echo"
                    )
                ) { handle in
                    try Expect.equal(
                        handle.ready,
                        "echo",
                        "readiness resolves typed value"
                    )

                    try Expect.greaterThan(
                        handle.processIdentifier,
                        Int64(0),
                        "fixture exposes child process identifier"
                    )

                    try await handle.write(
                        Data(
                            "ping\n".utf8
                        )
                    )
                    try await handle.finishInput()

                    let exit = try await handle.wait()

                    try Expect.equal(
                        exit,
                        .exited(0),
                        "echo fixture exits successfully"
                    )

                    let snapshot = await handle.snapshot()

                    try Expect.contains(
                        snapshot.stdoutText,
                        "READY:echo\n",
                        "stdout retains readiness line"
                    )

                    try Expect.contains(
                        snapshot.stdoutText,
                        "received:ping\n",
                        "stdin round trip reaches captured stdout"
                    )

                    try Expect.contains(
                        snapshot.stderrText,
                        "fixture-child:boot\n",
                        "stderr captures startup diagnostics"
                    )

                    try Expect.contains(
                        snapshot.stderrText,
                        "fixture-child:done\n",
                        "stderr captures completion diagnostics"
                    )
                }
            }

            Step("retain bounded output tail") {
                try await usingFixture(
                    processFixture(
                        mode: "burst",
                        captureLimit: 16
                    )
                ) { handle in
                    try Expect.equal(
                        handle.ready,
                        "burst",
                        "burst fixture becomes ready"
                    )

                    try await handle.finishInput()
                    _ = try await handle.wait()

                    let snapshot = await handle.snapshot()

                    try Expect.true(
                        snapshot.stdoutTruncated,
                        "stdout reports truncation"
                    )

                    try Expect.equal(
                        snapshot.stdout.count,
                        16,
                        "stdout retains configured bounded tail"
                    )

                    try Expect.true(
                        snapshot.stdoutText.hasSuffix("\n"),
                        "bounded stdout retains newest bytes"
                    )
                }
            }

            Step("tear down long-running child at fixture scope end") {
                let handle = try await usingFixture(
                    processFixture(
                        mode: "hold"
                    )
                ) { handle in
                    try Expect.equal(
                        handle.ready,
                        "hold",
                        "long-running fixture becomes ready"
                    )

                    return handle
                }

                let snapshot = await handle.snapshot()

                _ = try Expect.notNil(
                    snapshot.exit,
                    "scoped teardown records terminal process exit"
                )

                try await handle.teardown()
            }

            Step("clean up process when readiness times out") {
                let fixture = processFixture(
                    mode: "silent",
                    startupTimeout: .milliseconds(150)
                )

                do {
                    let handle = try await fixture.start()
                    try await handle.teardown()

                    throw TestFlowAssertionFailure(
                        label: "fixture startup timeout",
                        message: "fixture unexpectedly became ready",
                        actual: "ready",
                        expected: "startup failure"
                    )
                } catch let failure as TestFixtureFailure {
                    switch failure.phase {
                    case .start:
                        break

                    case .operation, .teardown:
                        throw TestFlowAssertionFailure(
                            label: "fixture startup timeout phase",
                            message: "fixture failed in the wrong lifecycle phase",
                            actual: failure.phase.rawValue,
                            expected: TestFixturePhase.start.rawValue
                        )
                    }
                }
            }
        }
    }
}

private func processFixture(
    mode: String,
    startupTimeout: Duration = .seconds(5),
    captureLimit: Int = 1024 * 1024
) -> ProcessFixture<String> {
    ProcessFixture(
        process: .init(
            executable: .path(
                processFixtureExecutablePath()
            ),
            arguments: [
                "--process-fixture-child",
                mode,
            ]
        ),
        readiness: .init { line in
            guard line.stream == .stdout else {
                return nil
            }

            let prefix = "READY:"

            guard line.value.hasPrefix(prefix) else {
                return nil
            }

            return String(
                line.value.dropFirst(
                    prefix.count
                )
            )
        },
        startupTimeout: startupTimeout,
        captureLimit: captureLimit
    )
}

private func processFixtureExecutablePath() -> String {
    let argument = CommandLine.arguments[0]

    guard !argument.hasPrefix("/") else {
        return argument
    }

    return URL(
        fileURLWithPath: FileManager.default.currentDirectoryPath,
        isDirectory: true
    )
    .appendingPathComponent(
        argument
    )
    .standardizedFileURL
    .path
}
