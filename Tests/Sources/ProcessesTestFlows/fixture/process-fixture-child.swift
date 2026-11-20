import Foundation

enum ProcessFixtureChild {
    static func runIfRequested(
        arguments: [String]
    ) async -> Bool {
        guard
            arguments.count >= 3,
            arguments[1] == "--process-fixture-child"
        else {
            return false
        }

        switch arguments[2] {
        case "echo":
            await runEcho()

        case "burst":
            await runBurst()

        case "hold":
            await runHold()

        case "silent":
            await runSilent()

        default:
            write(
                "unknown process fixture child mode\n",
                to: .standardError
            )
        }

        return true
    }
}

private extension ProcessFixtureChild {
    static func runEcho() async {
        write(
            "fixture-child:boot\n",
            to: .standardError
        )

        write(
            "READY:",
            to: .standardOutput
        )

        try? await Task.sleep(
            for: .milliseconds(25)
        )

        write(
            "echo\n",
            to: .standardOutput
        )

        let input = FileHandle.standardInput.readDataToEndOfFile()

        write(
            "received:",
            to: .standardOutput
        )
        FileHandle.standardOutput.write(
            input
        )

        write(
            "fixture-child:done\n",
            to: .standardError
        )
    }

    static func runBurst() async {
        write(
            "READY:burst\n",
            to: .standardOutput
        )

        write(
            String(
                repeating: "x",
                count: 64
            ) + "\n",
            to: .standardOutput
        )

        _ = FileHandle.standardInput.readDataToEndOfFile()
    }

    static func runHold() async {
        write(
            "READY:hold\n",
            to: .standardOutput
        )

        while true {
            try? await Task.sleep(
                for: .seconds(60)
            )
        }
    }

    static func runSilent() async {
        while true {
            try? await Task.sleep(
                for: .seconds(60)
            )
        }
    }

    static func write(
        _ value: String,
        to handle: FileHandle
    ) {
        handle.write(
            Data(
                value.utf8
            )
        )
    }
}
