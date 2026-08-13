import TestFlows

@main
enum ProcessesTestFlowsMain {
    static func main() async {
        await TestFlowCLI.run(
            suite: ProcessesFlowSuite.self
        )
    }
}
