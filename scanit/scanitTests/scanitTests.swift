import Foundation
import ScanItCore
import Testing
@testable import scanit

@MainActor
struct MoneyDisplayTests {
    @Test func formatsInTheMoneysOwnCurrency() {
        let price = Money(amountMinor: 199, currency: "EUR")
        #expect(price.formatted(locale: Locale(identifier: "pt_PT")).contains("1,99"))
        #expect(price.formatted(locale: Locale(identifier: "en_US")).contains("1.99"))
    }

    @Test func zeroDecimalCurrencies() {
        let yen = Money(amountMinor: 198, currency: "JPY")
        let text = yen.formatted(locale: Locale(identifier: "en_US"))
        #expect(text.contains("198"))
        #expect(!text.contains("."))
    }
}

@MainActor
struct AnalyticsEventTests {
    @Test func eventNamesMatchTheTrackingPlan() {
        #expect(AnalyticsEvent.appOpened.name == "app_opened")
        #expect(AnalyticsEvent.appOpened.properties.isEmpty)
        #expect(AnalyticsEvent.discordLinkClicked(surface: .settings).name == "discord_link_clicked")
        #expect(AnalyticsEvent.discordLinkClicked(surface: .settings).properties == ["surface": "settings"])
    }
}
