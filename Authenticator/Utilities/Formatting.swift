import Foundation

enum Formatting {
    /// Splits a code into readable groups: "123456" -> "123 456", "12345678" -> "1234 5678".
    static func groupedCode(_ code: String) -> String {
        let groupSize = code.count % 2 == 0 && code.count >= 8 ? 4 : 3
        guard code.count > groupSize else { return code }

        var output = ""
        for (index, character) in code.enumerated() {
            if index > 0, index % groupSize == 0 { output.append(" ") }
            output.append(character)
        }
        return output
    }

    static func idleTimeoutDescription(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "Never" }
        let minutes = Int(seconds) / 60
        if minutes < 1 { return "\(Int(seconds)) seconds" }
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}
