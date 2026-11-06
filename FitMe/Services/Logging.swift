import Foundation
import os

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "FitMe"

    static let settings = Logger(subsystem: subsystem, category: "settings")
    static let demoData = Logger(subsystem: subsystem, category: "demo-data")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let imagePipeline = Logger(subsystem: subsystem, category: "image-pipeline")
}
