import Foundation
import os

enum AppLog {
    static let general = Logger(subsystem: "com.smarty.app", category: "general")
    static let capture = Logger(subsystem: "com.smarty.app", category: "capture")
    static let speech = Logger(subsystem: "com.smarty.app", category: "speech")
    static let ocr = Logger(subsystem: "com.smarty.app", category: "ocr")
    static let openai = Logger(subsystem: "com.smarty.app", category: "openai")
    static let overlay = Logger(subsystem: "com.smarty.app", category: "overlay")
}
