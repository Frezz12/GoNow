import SwiftUI

struct MapFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MapFilterState
    let onApply: (MapFilterState) -> Void

    init(filters: MapFilterState, onApply: @escaping (MapFilterState) -> Void) {
        _draft = State(initialValue: filters)
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("map.filters.categories") {
                    ForEach(ActivityCategory.allCases) { category in
                        Button {
                            if draft.categories.contains(category) {
                                draft.categories.remove(category)
                            } else {
                                draft.categories.insert(category)
                            }
                        } label: {
                            HStack {
                                Label(LocalizedStringKey(category.titleKey), systemImage: category.symbol)
                                Spacer()
                                if draft.categories.contains(category) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(AppColors.accentPrimary)
                                }
                            }
                        }
                        .foregroundStyle(AppColors.textPrimary)
                    }
                }

                Section("map.filters.time") {
                    Picker("map.filters.starts", selection: $draft.startsWithinHours) {
                        Text("map.filters.any_time").tag(Int?.none)
                        Text("map.filters.next_hour").tag(Int?.some(1))
                        Text("map.filters.today").tag(Int?.some(12))
                        Text("map.filters.next_day").tag(Int?.some(24))
                    }
                }

                Section {
                    Toggle("map.filters.only_available", isOn: $draft.onlyAvailable)
                }

                Section {
                    Button("map.filters.reset") { draft = MapFilterState() }
                        .foregroundStyle(AppColors.error)
                }
            }
            .navigationTitle("map.filters.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("map.filters.apply") { onApply(draft) }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
