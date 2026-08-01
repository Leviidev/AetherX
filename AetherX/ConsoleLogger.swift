import Foundation

class ConsoleLogger {
    static let shared = ConsoleLogger()
    
    let logFileURL: URL
    
    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        logFileURL = docs.appendingPathComponent("console.log")
    }
    
    func startRedirecting() {
        // Clear previous logs
        try? FileManager.default.removeItem(at: logFileURL)
        
        // Redirect C-level stdout and stderr to the file
        freopen(logFileURL.path.cString(using: .utf8), "a+", stdout)
        freopen(logFileURL.path.cString(using: .utf8), "a+", stderr)
        
        writeLog("--- AetherX Session Started ---")
    }
    
    func writeLog(_ message: String) {
        // Also print to console for Xcode debugging
        print(message)
        
        let timestamp = Date().description
        let logMessage = "[\(timestamp)] \(message)\n"
        
        if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
            fileHandle.seekToEndOfFile()
            if let data = logMessage.data(using: .utf8) {
                fileHandle.write(data)
            }
            fileHandle.closeFile()
        } else {
            try? logMessage.write(to: logFileURL, atomically: true, encoding: .utf8)
        }
    }
    
    func readLogs() -> String {
        do {
            return try String(contentsOf: logFileURL, encoding: .utf8)
        } catch {
            return "No logs found or error reading logs: \(error.localizedDescription)"
        }
    }
}
