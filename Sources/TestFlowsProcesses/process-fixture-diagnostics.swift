import TestFlows

func processFixtureDiagnostics(
    processIdentifier: Int64,
    snapshot: ProcessFixtureSnapshot
) -> [TestFlowDiagnostic] {
    var diagnostics: [TestFlowDiagnostic] = [
        .field(
            "process_identifier",
            String(processIdentifier)
        )
    ]

    if let exit = snapshot.exit {
        switch exit {
        case .exited(let code):
            diagnostics.append(
                .field(
                    "process_exit_code",
                    String(code)
                )
            )

        case .signaled(let signal):
            diagnostics.append(
                .field(
                    "process_signal",
                    String(signal)
                )
            )
        }
    }

    if let eventError = snapshot.eventError {
        diagnostics.append(
            .field(
                "process_event_error",
                eventError
            )
        )
    }

    if snapshot.stdoutTruncated {
        diagnostics.append(
            .message(
                "process stdout capture contains only the retained tail"
            )
        )
    }

    if !snapshot.stdout.isEmpty {
        diagnostics.append(
            .section(
                "process stdout",
                snapshot.stdoutText
                    .split(
                        separator: "\n",
                        omittingEmptySubsequences: false
                    )
                    .map(String.init)
            )
        )
    }

    if snapshot.stderrTruncated {
        diagnostics.append(
            .message(
                "process stderr capture contains only the retained tail"
            )
        )
    }

    if !snapshot.stderr.isEmpty {
        diagnostics.append(
            .section(
                "process stderr",
                snapshot.stderrText
                    .split(
                        separator: "\n",
                        omittingEmptySubsequences: false
                    )
                    .map(String.init)
            )
        )
    }

    return diagnostics
}
