import SwiftUI

struct EditSlateView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var draft = SlateInfo()
    @State private var heightUnit = HeightUnit.feetInches
    @State private var feet = ""
    @State private var inches = ""
    @State private var centimetres = ""

    private enum Field { case name, height, basedIn, representation }
    private enum HeightUnit: String, Hashable { case feetInches = "ft / in", centimetres = "cm" }

    var body: some View {
        OTScreen(
            title: "Edit slate",
            onBack: { store.pop() },
            scrolls: false,
            trailing: {
                Button("Save") {
                    focusedField = nil
                    store.slate = draft
                    store.pop()
                }
                .font(.otHeadline)
                .foregroundStyle(OT.accent)
            }
        ) {
            Form {
                Section("Your slate") {
                    slateField("Name", placeholder: "e.g. Maya Sharma", text: $draft.name, field: .name,
                               contentType: .name, capitalization: .words, next: .height)
                    VStack(alignment: .leading, spacing: OTSpace.s) {
                        Text("Height").font(.otFootnote.weight(.medium)).foregroundStyle(OT.labelSecondary)

                        if heightUnit == .feetInches {
                            HStack(spacing: OTSpace.s) {
                                TextField("Feet", text: $feet)
                                    .keyboardType(.numberPad)
                                    .focused($focusedField, equals: .height)
                                    .onChange(of: feet) { oldValue, newValue in
                                        let digits = String(newValue.filter(\.isNumber).prefix(1))
                                        if let number = Int(digits), number > 8 { feet = oldValue; return }
                                        if digits != newValue { feet = digits; updateHeight(); return }
                                        updateHeight()
                                    }
                                Text("ft").foregroundStyle(OT.labelTertiary)
                                TextField("Inches", text: $inches)
                                    .keyboardType(.numberPad)
                                    .focused($focusedField, equals: .height)
                                    .onChange(of: inches) { oldValue, newValue in
                                        let digits = String(newValue.filter(\.isNumber).prefix(2))
                                        if let number = Int(digits), number > 11 { inches = oldValue; return }
                                        if digits != newValue { inches = digits; updateHeight(); return }
                                        updateHeight()
                                    }
                                Text("in").foregroundStyle(OT.labelTertiary)
                            }
                        } else {
                            HStack(spacing: OTSpace.s) {
                                TextField("Centimetres", text: $centimetres)
                                    .keyboardType(.numberPad)
                                    .focused($focusedField, equals: .height)
                                    .onChange(of: centimetres) { oldValue, newValue in
                                        let digits = String(newValue.filter(\.isNumber).prefix(3))
                                        if let number = Int(digits), number > 250 { centimetres = oldValue; return }
                                        if digits != newValue { centimetres = digits; updateHeight(); return }
                                        updateHeight()
                                    }
                                Text("cm").foregroundStyle(OT.labelTertiary)
                            }
                        }

                        Picker("Height unit", selection: Binding(get: { heightUnit }, set: changeHeightUnit)) {
                            Text("ft / in").tag(HeightUnit.feetInches)
                            Text("cm").tag(HeightUnit.centimetres)
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, OTSpace.xxs)

                    slateField("Based in", placeholder: "e.g. London", text: $draft.basedIn, field: .basedIn,
                               capitalization: .words, next: .representation)
                    slateField("Representation", placeholder: "Agency or self-represented", text: $draft.representation,
                               field: .representation, capitalization: .words, next: nil)
                }
                Section("Preview") {
                    Text(draft.spoken.isEmpty ? "Your slate preview will appear here." : draft.spoken)
                        .font(.otHeadline)
                        .foregroundStyle(draft.spoken.isEmpty ? OT.labelTertiary : OT.labelPrimary)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
        .onAppear(perform: loadDraft)
    }

    private func slateField(
        _ label: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        contentType: UITextContentType? = nil,
        capitalization: TextInputAutocapitalization,
        next: Field?
    ) -> some View {
        VStack(alignment: .leading, spacing: OTSpace.xxs) {
            Text(label).font(.otFootnote.weight(.medium)).foregroundStyle(OT.labelSecondary)
            TextField(placeholder, text: text)
                .textContentType(contentType)
                .textInputAutocapitalization(capitalization)
                .focused($focusedField, equals: field)
                .submitLabel(next == nil ? .done : .next)
                .onSubmit { focusedField = next }
        }
        .padding(.vertical, OTSpace.xxs)
    }

    private func loadDraft() {
        draft = store.slate
        let digits = String(draft.height.filter(\.isNumber))
        let hasImperialUnit = draft.height.contains("′") || draft.height.contains("″")
            || draft.height.localizedCaseInsensitiveContains("ft")
            || draft.height.localizedCaseInsensitiveContains("in")
        let isUnlabeledMetric = !hasImperialUnit && digits.count == 3 && (Int(digits) ?? 0) <= 250
        if draft.height.localizedCaseInsensitiveContains("cm") || isUnlabeledMetric {
            heightUnit = .centimetres
            centimetres = String(digits.prefix(3))
        } else {
            heightUnit = .feetInches
            feet = String(digits.prefix(1))
            inches = String(digits.dropFirst().prefix(2))
        }
    }

    private func changeHeightUnit(to newUnit: HeightUnit) {
        guard heightUnit != newUnit else { return }
        if newUnit == .centimetres {
            let totalInches = (Int(feet) ?? 0) * 12 + (Int(inches) ?? 0)
            centimetres = totalInches == 0 ? "" : String(Int((Double(totalInches) * 2.54).rounded()))
        } else {
            let totalInches = Int((Double(Int(centimetres) ?? 0) / 2.54).rounded())
            feet = totalInches == 0 ? "" : String(totalInches / 12)
            inches = totalInches == 0 ? "" : String(totalInches % 12)
        }
        heightUnit = newUnit
        updateHeight()
    }

    private func updateHeight() {
        switch heightUnit {
        case .feetInches:
            let parts = [feet.isEmpty ? nil : "\(feet)′", inches.isEmpty ? nil : "\(inches)″"].compactMap { $0 }
            draft.height = parts.joined(separator: " ")
        case .centimetres:
            draft.height = centimetres.isEmpty ? "" : "\(centimetres) cm"
        }
    }
}
