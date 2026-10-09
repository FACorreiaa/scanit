import Foundation

/// What Open Food Facts knows about a product (`ARCHITECTURE.md` → Open Food Facts).
nonisolated struct ProductInfo: Equatable, Sendable {
    var name: String?
    var brand: String?
    var imageURL: URL?
    var categories: [String]
}

nonisolated enum ProductLookupResult: Equatable, Sendable {
    case found(ProductInfo)
    /// OFF answered and does not know the code. Cached as a miss with a TTL.
    case notFound
}

/// Looks up a product by the code printed on the pack. Throws on network trouble, which leaves
/// the lookup queued for when the phone is back online.
nonisolated protocol ProductLookup: Sendable {
    func lookup(code: String) async throws -> ProductLookupResult
}

/// Free, keyless Open Food Facts API v2. OFF asks for a descriptive User-Agent.
nonisolated struct OpenFoodFactsClient: ProductLookup {
    var session: URLSession = .shared
    var baseURL = URL(string: "https://world.openfoodfacts.org/api/v2/product/")!
    var userAgent: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return "ScanIt/\(version) (iOS)"
    }()

    func lookup(code: String) async throws -> ProductLookupResult {
        var components = URLComponents(url: baseURL.appending(path: code), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "fields", value: "product_name,brands,image_front_small_url,categories_tags")]
        var request = URLRequest(url: components.url!, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // Unknown products come back as 404 with a JSON body; anything else non-2xx is trouble.
        guard (200..<300).contains(status) || status == 404 else { throw URLError(.badServerResponse) }
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> ProductLookupResult {
        struct Envelope: Decodable {
            struct Product: Decodable {
                let product_name: String?
                let brands: String?
                let image_front_small_url: String?
                let categories_tags: [String]?
            }
            let status: Int
            let product: Product?
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.status == 1, let product = envelope.product else { return .notFound }
        func clean(_ text: String?) -> String? {
            let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
        return .found(ProductInfo(
            name: clean(product.product_name),
            // OFF lists brands comma-separated; the first is the one on the front of the pack.
            brand: clean(product.brands?.split(separator: ",").first.map(String.init)),
            imageURL: product.image_front_small_url.flatMap(URL.init(string:)),
            categories: product.categories_tags ?? []
        ))
    }
}

/// UI tests (`-ui-testing`): fixed answers, no network.
nonisolated struct FixedProductLookup: ProductLookup {
    let names: [String: String]

    func lookup(code: String) async throws -> ProductLookupResult {
        names[code].map { .found(ProductInfo(name: $0, brand: nil, imageURL: nil, categories: [])) } ?? .notFound
    }
}
