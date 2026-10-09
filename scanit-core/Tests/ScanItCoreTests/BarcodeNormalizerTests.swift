import Testing
@testable import ScanItCore

struct BarcodeVector: Decodable, Sendable, CustomTestStringConvertible {
    struct Expected: Decodable, Sendable {
        let kind: String
        let value: String
        let inStore: Bool
    }

    let name: String
    let symbology: Symbology
    let payload: String
    let expected: Expected

    var testDescription: String { name }
}

private let barcodeVectors = (try? Fixtures.decode([BarcodeVector].self, from: "barcodes.json")) ?? []

@Suite("BarcodeNormalizer")
struct BarcodeNormalizerTests {
    @Test func fixturesLoad() {
        #expect(barcodeVectors.count >= 16)
    }

    @Test(arguments: barcodeVectors)
    func vector(_ vector: BarcodeVector) {
        let code = BarcodeNormalizer.normalize(payload: vector.payload, symbology: vector.symbology)
        #expect(code.kind.rawValue == vector.expected.kind)
        #expect(code.value == vector.expected.value)
        #expect(code.isInStore == vector.expected.inStore)
    }

    @Test func checkDigit() {
        #expect(GTIN.checkDigit(for: "400638133393") == 1)
        #expect(GTIN.isValid("4006381333931"))
        #expect(!GTIN.isValid("4006381333932"))
        #expect(!GTIN.isValid("40063813339a1"))
        #expect(!GTIN.isValid(""))
    }

    @Test func sameProductMatchesAcrossSymbologies() {
        let ean = BarcodeNormalizer.normalize(payload: "4006381333931", symbology: .ean13)
        let link = BarcodeNormalizer.normalize(payload: "https://id.gs1.org/01/04006381333931", symbology: .qr)
        #expect(ean == link)
    }
}
