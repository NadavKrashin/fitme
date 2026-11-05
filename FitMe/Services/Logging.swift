import Foundation
import os

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "FitMe"

    static let settings = Logger(subsystem: subsystem, category: "settings")
    static let demoData = Logger(subsystem: subsystem, category: "demo-data")
}
