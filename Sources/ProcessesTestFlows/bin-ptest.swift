import Foundation
import TestFlows

@main
enum ProcessesTestFlowsMain {
    static func main() async {
        if await ProcessFixtureChild.runIfRequested(
            arguments: CommandLine.arguments
        ) {
            return
        }

        await TestFlowCLI.run(
            suite: ProcessesFlowSuite.self
        )
    }
}
