import Foundation

enum SaveNaming {
    /// File name for a drawing saved at `date`, e.g. "QOIX Draw 2026-10-10 09.30.12.png".
    static func fileName(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "QOIX Draw \(formatter.string(from: date)).png"
    }
}
