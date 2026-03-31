import Foundation

enum TimeFormatting {
    /// Converts Jellyfin ticks (100-nanosecond intervals) to seconds
    static func ticksToSeconds(_ ticks: Int?) -> Double {
        guard let ticks else { return 0 }
        return Double(ticks) / 10_000_000
    }

    /// Formats seconds into "Xh Xm" or "Xm" for display
    static func shortDuration(seconds: Double) -> String {
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// Formats seconds into "X:XX:XX" for player display
    static func playerTime(seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// Formats ticks into "Xh Xm" for display
    static func shortDuration(ticks: Int?) -> String {
        shortDuration(seconds: ticksToSeconds(ticks))
    }

    /// Formats remaining time: "Xh Xm left"
    static func remaining(totalTicks: Int?, positionTicks: Int?) -> String {
        let total = ticksToSeconds(totalTicks)
        let position = ticksToSeconds(positionTicks)
        let remaining = max(0, total - position)
        return "\(shortDuration(seconds: remaining)) left"
    }
}
