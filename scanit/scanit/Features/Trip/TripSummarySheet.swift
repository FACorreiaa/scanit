import ScanItCore
import SwiftData
import SwiftUI

/// Shown after Finish (`DESIGN.md` §6, BACKLOG IOS-010): total, limit result, items, change vs
/// the last trip at this store, the biggest lines, and an optional actual till total.
struct TripSummarySheet: View {
    @Environment(SessionStore.self) private var sessions
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let session: ShoppingSession

    @State private var tillText = ""
    @State private var undone = false

    var body: some View {
        let summary = TripSummary(session: session, context: context)
        let saving = InsightsSource.tripSavings([session], context: context)[session.id]
        NavigationStack {
            List {
                Section {
                    TripTotalHeader(total: summary.total, limit: summary.limit, status: summary.status)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .listRowBackground(Color.clear)
                }

                Section {
                    LabeledContent("Items", value: summary.itemCount, format: .number)
                    if let delta = summary.deltaVsPrevious, let store = session.store {
                        LabeledContent("Vs last time at \(store.name)", value: deltaText(delta))
                            .monospacedDigit()
                    }
                }

                if let saving {
                    Section {
                        TripSavingRows(saving: saving)
                    } footer: {
                        if let coverage = saving.coverageText {
                            Text("\(coverage). Against your latest prices at your other stores.")
                        } else {
                            Text("Against your latest prices at your other stores.")
                        }
                    }
                }

                if !summary.biggestLines.isEmpty {
                    Section("Biggest") {
                        ForEach(summary.biggestLines, id: \.id) { item in
                            CartItemRow(item: item, currency: session.currency)
                        }
                    }
                }

                Section {
                    TripShareLink(session: session, saving: saving)
                } footer: {
                    Text(TripShareContent.footer(includesSaving: saving?.isSaving == true))
                }

                Section {
                    HStack {
                        Text(Money.symbol(for: session.currency)).foregroundStyle(.secondary)
                        TextField("Optional", text: $tillText)
                            .keyboardType(.decimalPad)
                            .monospacedDigit()
                            .accessibilityIdentifier("tillTotal")
                    }
                } header: {
                    Text("Actual till total")
                } footer: {
                    Text("What the till charged. The difference shows missed items or wrong prices.")
                }
            }
            .navigationTitle("Trip finished")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Undo finish") {
                        undone = true
                        sessions.undoFinish(session)
                        dismiss()
                    }
                    .accessibilityIdentifier("undoFinish")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("doneSummary")
                }
            }
        }
        .onAppear {
            if let till = session.tillTotalMinor {
                tillText = MoneyInput.editingText(Money(amountMinor: till, currency: session.currency))
            }
        }
        // Done, swipe-down and backgrounding all keep the till total.
        .onDisappear {
            guard !undone else { return }
            let till = MoneyInput.parse(tillText, currency: session.currency)?.amountMinor
            if till != session.tillTotalMinor { sessions.setTillTotal(session, minor: till) }
        }
    }

    private func deltaText(_ delta: Money) -> String {
        let amount = Money(amountMinor: abs(delta.amountMinor), currency: delta.currency).formatted()
        switch delta.amountMinor {
        case 0: return "Same"
        case ..<0: return "−\(amount)"
        default: return "+\(amount)"
        }
    }
}
