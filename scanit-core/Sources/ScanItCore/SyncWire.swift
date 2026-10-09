import Foundation

// Wire types for `/v1/sync/*`. `docs/api.md` is the human-readable contract; the server's
// `openapi.yaml` is the machine one. Fixture: `scanit-core/Fixtures/sync-push.json`.

public enum EntityKind: String, Codable, Sendable, CaseIterable {
    case store
    case session
    case cartItem = "cart_item"
    case priceObservation = "price_observation"
}

public enum SessionStatus: String, Codable, Sendable {
    case active, finished, abandoned
}

public enum PriceSource: String, Codable, Sendable {
    case ocr, manual, remembered, embedded
}

public struct StoreDTO: Hashable, Codable, Sendable {
    public var name: String
    public var chain: String?
    public var countryCode: String
    public var currency: String

    public init(name: String, chain: String? = nil, countryCode: String, currency: String) {
        self.name = name
        self.chain = chain
        self.countryCode = countryCode
        self.currency = currency
    }
}

public struct SessionDTO: Hashable, Codable, Sendable {
    public var storeId: UUID?
    public var limit: Money?
    public var currency: String
    public var startedAt: Date
    public var endedAt: Date?
    public var status: SessionStatus
    public var tillTotal: Money?

    public init(
        storeId: UUID?, limit: Money?, currency: String, startedAt: Date,
        endedAt: Date? = nil, status: SessionStatus, tillTotal: Money? = nil
    ) {
        self.storeId = storeId
        self.limit = limit
        self.currency = currency
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
        self.tillTotal = tillTotal
    }
}

public struct CartItemDTO: Hashable, Codable, Sendable {
    public var sessionId: UUID
    public var code: String
    public var codeKind: ScannedCode.Kind
    public var productName: String?
    public var quantity: Int
    public var weightGrams: Int?
    public var unitPrice: Money
    public var priceSource: PriceSource
    public var scannedAt: Date

    public init(
        sessionId: UUID, code: ScannedCode, productName: String? = nil, quantity: Int,
        weightGrams: Int? = nil, unitPrice: Money, priceSource: PriceSource, scannedAt: Date
    ) {
        self.sessionId = sessionId
        self.code = code.value
        self.codeKind = code.kind
        self.productName = productName
        self.quantity = quantity
        self.weightGrams = weightGrams
        self.unitPrice = unitPrice
        self.priceSource = priceSource
        self.scannedAt = scannedAt
    }
}

public struct PriceObservationDTO: Hashable, Codable, Sendable {
    public var storeId: UUID
    public var code: String
    public var price: Money
    public var observedAt: Date
    public var source: PriceSource

    public init(storeId: UUID, code: String, price: Money, observedAt: Date, source: PriceSource) {
        self.storeId = storeId
        self.code = code
        self.price = price
        self.observedAt = observedAt
        self.source = source
    }
}

public enum SyncPayload: Hashable, Sendable {
    case store(StoreDTO)
    case session(SessionDTO)
    case cartItem(CartItemDTO)
    case priceObservation(PriceObservationDTO)

    public var entity: EntityKind {
        switch self {
        case .store: .store
        case .session: .session
        case .cartItem: .cartItem
        case .priceObservation: .priceObservation
        }
    }
}

/// One row change: `{ entity, id, updatedAt, deletedAt, data }`.
public struct SyncChange: Hashable, Codable, Sendable {
    public var id: UUID
    public var updatedAt: Date
    public var deletedAt: Date?
    public var payload: SyncPayload

    public var entity: EntityKind { payload.entity }

    public init(id: UUID, updatedAt: Date, deletedAt: Date? = nil, payload: SyncPayload) {
        self.id = id
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.payload = payload
    }

    private enum CodingKeys: String, CodingKey {
        case entity, id, updatedAt, deletedAt, data
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        payload = switch try container.decode(EntityKind.self, forKey: .entity) {
        case .store: .store(try container.decode(StoreDTO.self, forKey: .data))
        case .session: .session(try container.decode(SessionDTO.self, forKey: .data))
        case .cartItem: .cartItem(try container.decode(CartItemDTO.self, forKey: .data))
        case .priceObservation: .priceObservation(try container.decode(PriceObservationDTO.self, forKey: .data))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entity, forKey: .entity)
        try container.encode(id, forKey: .id)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
        switch payload {
        case .store(let data): try container.encode(data, forKey: .data)
        case .session(let data): try container.encode(data, forKey: .data)
        case .cartItem(let data): try container.encode(data, forKey: .data)
        case .priceObservation(let data): try container.encode(data, forKey: .data)
        }
    }
}

public struct SyncPushRequest: Hashable, Codable, Sendable {
    public static let maxChanges = 500
    public var changes: [SyncChange]

    public init(changes: [SyncChange]) {
        self.changes = changes
    }
}

public struct SyncPushResponse: Hashable, Codable, Sendable {
    public struct Rejection: Hashable, Codable, Sendable {
        public var id: UUID
        public var code: String
    }

    public var accepted: [UUID]
    public var rejected: [Rejection]
    public var cursor: String
}

public struct SyncPullResponse: Hashable, Codable, Sendable {
    public var changes: [SyncChange]
    public var cursor: String
    public var hasMore: Bool
}

/// JSON coders for the `/v1` wire format: RFC 3339 UTC dates, with or without fractional seconds.
public enum WireCoding {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date))
        }
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            if let date = (try? fractional.parse(string)) ?? (try? Date.ISO8601FormatStyle().parse(string)) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an RFC 3339 date: \(string)")
        }
        return decoder
    }
}
