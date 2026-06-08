import XCTest
import SwiftData
@testable import Vita

@MainActor
final class SettingsActionsTests: XCTestCase {

    private var container: ModelContainer!   // retained — a dropped in-memory container traps on use
    private func ctx() -> ModelContext {
        container = VitaContainer.make(inMemory: true)
        return container.mainContext
    }

    @discardableResult
    private func compound(_ c: ModelContext, slug: String, rx: RxStatus = .nonRx) -> CatalogCompound {
        let comp = CatalogCompound(slug: slug); comp.name = slug; comp.rxStatusRaw = rx.rawValue
        c.insert(comp); return comp
    }

    func testSetRxOverrideSetsAndReplaces() {
        let c = ctx(); let comp = compound(c, slug: "bpc-157", rx: .nonRx)
        let a = SettingsActions(context: c)

        a.setRxOverride(slug: "bpc-157", isRx: true)
        XCTAssertEqual(comp.rxStatus, .rx)
        let s = CatalogStore.fetchOrCreateSettings(c)
        XCTAssertEqual(s.customRxOverrides, ["bpc-157=rx"])

        a.setRxOverride(slug: "bpc-157", isRx: false)          // replace, not duplicate
        XCTAssertEqual(comp.rxStatus, .nonRx)
        XCTAssertEqual(s.customRxOverrides, ["bpc-157=nonRx"])
    }

    func testRxOverrideReappliesAcrossReseed() {
        let c = ctx(); let comp = compound(c, slug: "tb-500", rx: .nonRx)
        SettingsActions(context: c).setRxOverride(slug: "tb-500", isRx: true)
        comp.rxStatusRaw = RxStatus.nonRx.rawValue              // simulate a reseed clobbering it
        CatalogStore.applyRxOverrides(c, settings: CatalogStore.fetchOrCreateSettings(c))
        XCTAssertEqual(comp.rxStatus, .rx)                      // override re-applied
    }

    func testClearChatAndLogs() throws {
        let c = ctx()
        c.insert(ChatMessage()); c.insert(DoseLog()); try c.save()
        SettingsActions(context: c).clearChat()
        XCTAssertEqual(try c.fetch(FetchDescriptor<ChatMessage>()).count, 0)
        SettingsActions(context: c).clearDoseLogs()
        XCTAssertEqual(try c.fetch(FetchDescriptor<DoseLog>()).count, 0)
    }

    func testResetOnboarding() {
        let c = ctx()
        let s = CatalogStore.fetchOrCreateSettings(c)
        CatalogStore.fetchOrCreateProfile(c, settings: s).onboardedAt = Date()
        try? c.save()
        SettingsActions(context: c).resetOnboarding()
        XCTAssertNil(CatalogStore.fetchOrCreateProfile(c, settings: s).onboardedAt)
    }

    func testFullResetWipesAndReseeds() throws {
        let c = ctx()
        let s = CatalogStore.fetchOrCreateSettings(c)
        CatalogStore.fetchOrCreateProfile(c, settings: s).onboardedAt = Date()
        c.insert(ProtocolItem()); c.insert(DoseLog()); compound(c, slug: "x")
        try c.save()

        SettingsActions(context: c).fullReset()

        XCTAssertEqual(try c.fetch(FetchDescriptor<ProtocolItem>()).count, 0)
        XCTAssertEqual(try c.fetch(FetchDescriptor<DoseLog>()).count, 0)
        XCTAssertGreaterThan(try c.fetch(FetchDescriptor<CatalogCompound>()).count, 0)   // catalog reseeded
        let s2 = CatalogStore.fetchOrCreateSettings(c)
        XCTAssertNil(CatalogStore.fetchOrCreateProfile(c, settings: s2).onboardedAt)      // wizard runs again
    }

    func testPingBodyShape() {
        let body = AnthropicClient.makeBody(
            maxTokens: 1,
            system: [AnthropicClient.SystemBlock(text: "t", cache: false)],
            messages: [["role": "user", "content": "hi"]])
        XCTAssertEqual(body["max_tokens"] as? Int, 1)
        XCTAssertNil(body["tools"])         // ping carries no tools
        XCTAssertNil(body["temperature"])   // Opus-4.8-legal
        XCTAssertNil(body["thinking"])
    }
}
