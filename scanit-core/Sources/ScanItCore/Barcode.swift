import Foundation

/// Symbologies the scanner is configured for (`ARCHITECTURE.md` → Scanner).
public enum Symbology: String, Codable, Sendable, CaseIterable {
    case ean13, ean8, upca, upce, code128, qr
}

/// A scanned product code, normalised so the same product matches whichever symbology was read.
public struct ScannedCode: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// `value` is a 14-digit GTIN with a valid check digit.
        case gtin
        /// `value` is the raw payload; it can still be remembered, but never looked up.
        case opaque
    }

    public let kind: Kind
    public let value: String

    public init(kind: Kind, value: String) {
        self.kind = kind
        self.value = value
    }

    /// GS1 restricted-circulation numbers: GTIN-13 prefixes 020–029 and 200–299 (which covers
    /// UPC-A number system 2), and EAN-8 prefixes 0 and 2. These are weighed produce, deli and
    /// store-own labels: the same code can mean a different product in another shop, and the
    /// price may be embedded in it (parsed per country in BACKLOG INS-105).
    public var isInStore: Bool {
        guard kind == .gtin else { return false }
        if value.hasPrefix("000000") {
            let first = value.dropFirst(6).first // EAN-8
            return first == "0" || first == "2"
        }
        let gtin13 = value.dropFirst()
        return gtin13.hasPrefix("2") || gtin13.hasPrefix("02")
    }
}

public enum GTIN {
    /// Mod-10 check digit for the digits *before* the check digit, or `nil` if not all digits.
    public static func checkDigit(for body: some StringProtocol) -> Int? {
        var sum = 0
        for (offset, character) in body.reversed().enumerated() {
            guard let digit = character.wholeNumberValue, character.isASCII else { return nil }
            sum += digit * (offset.isMultiple(of: 2) ? 3 : 1)
        }
        return (10 - sum % 10) % 10
    }

    /// True for an 8, 12, 13 or 14 digit string whose last digit is the right check digit.
    public static func isValid(_ code: some StringProtocol) -> Bool {
        guard [8, 12, 13, 14].contains(code.count), let last = code.last?.wholeNumberValue else {
            return false
        }
        return checkDigit(for: code.dropLast()) == last
    }

    /// Left-pads a valid GTIN-8/12/13/14 to 14 digits.
    public static func gtin14(_ code: some StringProtocol) -> String? {
        guard isValid(code) else { return nil }
        return String(repeating: "0", count: 14 - code.count) + code
    }
}

public enum BarcodeNormalizer {
    public static func normalize(payload: String, symbology: Symbology) -> ScannedCode {
        let raw = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        let gtin: String? = switch symbology {
        case .ean13, .ean8, .upca:
            GTIN.gtin14(raw)
        case .upce:
            expandUPCE(raw).flatMap(GTIN.gtin14)
        case .code128:
            GTIN.gtin14(raw) ?? gs1ApplicationIdentifier01(in: raw)
        case .qr:
            digitalLinkGTIN(in: raw)
        }
        if let gtin {
            return ScannedCode(kind: .gtin, value: gtin)
        }
        return ScannedCode(kind: .opaque, value: raw)
    }

    /// UPC-E (8 digits: number system, 6 data digits, check) to UPC-A (12 digits).
    static func expandUPCE(_ code: String) -> String? {
        guard code.count == 8, code.allSatisfy(\.isASCII), code.allSatisfy(\.isNumber) else { return nil }
        let digits = Array(code)
        let numberSystem = digits[0]
        guard numberSystem == "0" || numberSystem == "1" else { return nil }
        let d = Array(digits[1...6])
        let check = digits[7]
        let body: String = switch d[5] {
        case "0", "1", "2":
            String([d[0], d[1], d[5], "0", "0", "0", "0", d[2], d[3], d[4]])
        case "3":
            String([d[0], d[1], d[2], "0", "0", "0", "0", "0", d[3], d[4]])
        case "4":
            String([d[0], d[1], d[2], d[3], "0", "0", "0", "0", "0", d[4]])
        default:
            String([d[0], d[1], d[2], d[3], d[4], "0", "0", "0", "0", d[5]])
        }
        return String(numberSystem) + body + String(check)
    }

    /// GS1 Digital Link: `https://<any host>/01/<gtin>[/…][?…]`.
    static func digitalLinkGTIN(in payload: String) -> String? {
        guard let url = URL(string: payload), url.scheme?.hasPrefix("http") == true else { return nil }
        let parts = url.path.split(separator: "/")
        guard let index = parts.firstIndex(of: "01"), parts.indices.contains(index + 1) else { return nil }
        return GTIN.gtin14(parts[index + 1])
    }

    /// GS1-128 in human-readable form: `(01)<14 digits>…`.
    static func gs1ApplicationIdentifier01(in payload: String) -> String? {
        guard let range = payload.range(of: "(01)") else { return nil }
        let digits = payload[range.upperBound...].prefix(14)
        guard digits.count == 14 else { return nil }
        return GTIN.gtin14(digits)
    }
}
