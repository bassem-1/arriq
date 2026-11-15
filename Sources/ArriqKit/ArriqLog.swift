import os

/// os.Logger categories. never log tokens, topics or addresses.
enum ArriqLog {
    static let engine = Logger(subsystem: "io.github.arriq", category: "engine")
    static let drivers = Logger(subsystem: "io.github.arriq", category: "drivers")
}
