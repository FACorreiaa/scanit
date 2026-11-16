import Foundation

/// A supermarket chain in one country (BACKLOG CMP-001). `id` is what `Store.chain` keeps; the same
/// chain has the same id in every country, though its local `name` may differ (Auchan is
/// "Alcampo" in Spain). Comparisons are by chain within a country, never across currencies.
public struct Chain: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// Other names a store is typed as. Matched as whole words after `ChainCatalog.fold`.
    public let aliases: [String]
}

/// The per-country chain list in `Resources/chains.json`, shared with Android.
public enum ChainCatalog {
    private struct File: Decodable {
        let version: Int
        let countries: [String: [Chain]]
    }

    private static let byCountry: [String: [Chain]] = {
        guard let url = Bundle.module.url(forResource: "chains", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else {
            assertionFailure("chains.json is missing or malformed")
            return [:]
        }
        return file.countries
    }()

    /// ISO 3166-1 codes that have a list, sorted.
    public static var countries: [String] { byCountry.keys.sorted() }

    /// The chains for a country, in the order to offer them. Empty for a country without a list.
    public static func chains(country: String) -> [Chain] {
        byCountry[country.uppercased()] ?? []
    }

    public static func chain(id: String, country: String) -> Chain? {
        chains(country: country).first { $0.id == id }
    }

    /// The chain a typed store name belongs to, if its name or an alias appears in it as whole
    /// words ("Pingo Doce Benfica" → Pingo Doce). The longest match wins.
    public static func match(storeName: String, country: String) -> Chain? {
        let name = " \(fold(storeName)) "
        guard name.count > 2 else { return nil }
        var best: (chain: Chain, length: Int)?
        for chain in chains(country: country) {
            for phrase in [chain.name] + chain.aliases {
                let folded = fold(phrase)
                guard !folded.isEmpty, name.contains(" \(folded) ") else { continue }
                if folded.count > best?.length ?? 0 { best = (chain, folded.count) }
            }
        }
        return best?.chain
    }

    /// Lower case, no accents, and every run of punctuation or spaces as one space.
    static func fold(_ text: String) -> String {
        let plain = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        let spaced = String(plain.map { $0.isLetter || $0.isNumber ? $0 : " " })
        return spaced.split(separator: " ").joined(separator: " ")
    }
}
