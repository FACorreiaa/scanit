import CoreTransferable
import Foundation
import ScanItCore
import SwiftData
import UniformTypeIdentifiers

/// Every finished trip as one CSV file, a row per cart line (BACKLOG ADD-006). The data never
/// leaves the phone unless the owner shares the file.
nonisolated enum TripExport {
    struct Row: Equatable, Sendable {
        let date: Date
        let store: String
        let product: String
        let code: String
        let quantity: Int
        let unitPriceMinor: Int
        let currency: String
        let priceSource: String
    }

    static let header = ["date", "store", "product", "code", "quantity", "unit_price", "line_total", "currency", "price_source"]

    /// Finished trips, oldest first, lines in the order they were scanned.
    static func rows(context: ModelContext) -> [Row] {
        let finished = SessionStatus.finished.rawValue
        let trips = (try? context.fetch(FetchDescriptor<ShoppingSession>(
            predicate: #Predicate { $0.statusRaw == finished && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startedAt)]
        ))) ?? []
        return trips.flatMap { trip in
            trip.liveItems.sorted { $0.scannedAt < $1.scannedAt }.map { item in
                Row(
                    date: trip.startedAt, store: trip.store?.name ?? "", product: item.productName ?? "",
                    code: item.code, quantity: item.quantity, unitPriceMinor: item.unitPriceMinor,
                    currency: trip.currency, priceSource: item.priceSourceRaw
                )
            }
        }
    }

    /// RFC 4180, UTF-8. Amounts use a decimal point whatever the phone's region, so the file
    /// reads the same everywhere.
    static func csv(_ rows: [Row], timeZone: TimeZone = .current) -> String {
        var dates = Date.ISO8601FormatStyle(timeZone: timeZone)
        dates = dates.year().month().day().dateSeparator(.dash).dateTimeSeparator(.space).time(includingFractionalSeconds: false).timeSeparator(.colon)
        let lines = rows.map { row in
            [
                dates.format(row.date), row.store, row.product, row.code, String(row.quantity),
                amount(row.unitPriceMinor, currency: row.currency),
                amount(row.unitPriceMinor * row.quantity, currency: row.currency),
                row.currency, row.priceSource,
            ]
        }
        return ([header] + lines).map { $0.map(field).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    private static func amount(_ minor: Int, currency: String) -> String {
        let digits = Money.minorUnitDigits(for: currency)
        guard digits > 0 else { return String(minor) }
        let scale = (0..<digits).reduce(1) { value, _ in value * 10 }
        let fraction = String(abs(minor) % scale)
        let padded = String(repeating: "0", count: digits - fraction.count) + fraction
        return "\(minor < 0 ? "-" : "")\(abs(minor) / scale).\(padded)"
    }

    /// Quotes what needs quoting. A product name from Open Food Facts that starts like a formula
    /// is made plain text, so a spreadsheet never runs it.
    private static func field(_ value: String) -> String {
        var text = value
        if let first = text.first, "=+-@\t\r".contains(first), Double(text) == nil { text = "'" + text }
        guard text.contains(where: { ",\"\r\n".contains($0) }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// Handed to `ShareLink`.
nonisolated struct TripExportFile: Transferable, Sendable {
    let csv: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { file in
            // The byte-order mark makes Excel read the accents in store and product names.
            Data([0xEF, 0xBB, 0xBF]) + Data(file.csv.utf8)
        }
        .suggestedFileName("ScanItNow trips.csv")
    }
}
