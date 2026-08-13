import Foundation

public enum ProcessInput:
    Sendable,
    Equatable
{
    case none
    case data(
        Data
    )

    public static func utf8(
        _ string: String
    ) -> Self {
        .data(
            Data(
                string.utf8
            )
        )
    }
}
