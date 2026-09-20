import TestFlows

enum ProcessesFlowSuite: TestFlowRegistry {
    static let title = "Processes flow tests"

    static let flows: [TestFlow] = [
        executionFlow,
        ioFlow,
        lifetimeFlow,
        ptyFlow,
        sessionFlow,
        processFixtureFlow,
    ]
}
