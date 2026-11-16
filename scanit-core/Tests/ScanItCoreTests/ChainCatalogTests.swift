import Testing
@testable import ScanItCore

@Suite("Chain catalogue (CMP-001)")
struct ChainCatalogTests {
    @Test func portugalListsTheEightChains() {
        let ids = ChainCatalog.chains(country: "PT").map(\.id)
        #expect(ids == ["continente", "pingo-doce", "lidl", "aldi", "auchan", "intermarche", "mercadona", "minipreco"])
        #expect(ChainCatalog.chains(country: "pt").map(\.id) == ids, "country codes ignore case")
    }

    @Test func everyCountryHasAList() {
        for country in ["PT", "ES", "FR", "US"] {
            #expect(ChainCatalog.chains(country: country).count >= 8, "\(country)")
        }
        #expect(ChainCatalog.chains(country: "JP").isEmpty, "unknown country: no chips, typing still works")
    }

    @Test func idsAreUniquePerCountryAndStableAcrossCountries() {
        for country in ChainCatalog.countries {
            let ids = ChainCatalog.chains(country: country).map(\.id)
            #expect(Set(ids).count == ids.count, "\(country) repeats an id")
        }
        // One id is one chain everywhere: CMP-002 compares by id within a country.
        #expect(ChainCatalog.chain(id: "lidl", country: "PT")?.name == "Lidl")
        #expect(ChainCatalog.chain(id: "auchan", country: "ES")?.name == "Alcampo", "local brand name, same chain")
        #expect(ChainCatalog.chain(id: "lidl", country: "JP") == nil)
    }

    @Test(arguments: [
        ("Pingo Doce Benfica", "PT", "pingo-doce"),
        ("pingo doce", "PT", "pingo-doce"),
        ("Continente Modelo Sintra", "PT", "continente"),
        ("Intermarche Cascais", "PT", "intermarche"),
        ("MINIPREÇO", "PT", "minipreco"),
        ("Lidl", "PT", "lidl"),
        ("E.Leclerc Rennes", "FR", "leclerc"),
        ("Super U Nantes", "FR", "super-u"),
        ("Trader Joe's Brooklyn", "US", "trader-joes"),
        ("Alcampo", "ES", "auchan"),
    ])
    func matchesTypedStoreNames(name: String, country: String, id: String) {
        #expect(ChainCatalog.match(storeName: name, country: country)?.id == id)
    }

    @Test(arguments: [
        ("Mercearia do Bairro", "PT"),
        ("Lidlx", "PT"), // whole words only
        ("Super Mercado", "FR"), // "super" alone is not Super U
        ("Lidl", "JP"),
        ("", "PT"),
    ])
    func leavesOtherNamesAlone(name: String, country: String) {
        #expect(ChainCatalog.match(storeName: name, country: country) == nil)
    }

    @Test func foldIgnoresCaseAccentsAndPunctuation() {
        #expect(ChainCatalog.fold("  Intermarché  ") == "intermarche")
        #expect(ChainCatalog.fold("E.Leclerc") == "e leclerc")
        #expect(ChainCatalog.fold("Trader Joe's") == "trader joe s")
    }
}
