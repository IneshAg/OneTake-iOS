import SwiftUI

struct PackageFormatSheet: View {
    let auditionID: Audition.ID
    let required: PackageDeliverable?
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            OTSheetHeader(title: "Delivery format", leading: nil, trailing: "Done", onTrailing: { dismiss() })
                .padding(.top, OTSpace.m)

            Text(required.map { "Casting requests \($0.rawValue)." } ?? "No file format was specified. Choose what you want to send.")
                .font(.otFootnote)
                .foregroundStyle(OT.labelSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, OTSpace.gutter)
                .padding(.top, OTSpace.s)
                .padding(.bottom, OTSpace.xs)

            if let binding = store.binding(for: auditionID) {
                List {
                    ForEach(PackageDeliverable.allCases) { option in
                        let selected = binding.wrappedValue.packageDeliverable == option
                        Button {
                            if binding.wrappedValue.packageDeliverable != option {
                                store.clearShareLink(for: auditionID)
                            }
                            binding.wrappedValue.packageDeliverable = option
                            Haptics.tick()
                            dismiss()
                        } label: {
                            HStack(spacing: OTSpace.m) {
                                Image(systemName: option.icon)
                                    .foregroundStyle(OT.accent)
                                    .frame(width: 24) // ot-lint:allow
                                VStack(alignment: .leading, spacing: OTSpace.xxs) {
                                    HStack {
                                        Text(option.rawValue)
                                            .font(.otBody.weight(.semibold))
                                        if required == option {
                                            Text("Required")
                                                .font(.otCaption.weight(.bold))
                                                .foregroundStyle(OT.accent)
                                                .padding(.horizontal, 7) // ot-lint:allow
                                                .padding(.vertical, 3) // ot-lint:allow
                                                .background(OT.accentSoft, in: Capsule())
                                        }
                                    }
                                    Text(option.subtitle)
                                        .font(.otFootnote)
                                        .foregroundStyle(OT.labelSecondary)
                                }
                                Spacer()
                                if selected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(OT.accent)
                                }
                            }
                            .foregroundStyle(OT.labelPrimary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .otCanvas()
    }
}
