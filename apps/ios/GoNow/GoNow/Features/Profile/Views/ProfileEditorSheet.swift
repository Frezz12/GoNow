import SwiftUI
import UIKit
import Foundation
import CoreLocation

struct ProfileEditorSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let user: CurrentUser
    @State private var displayName: String
    @State private var city: String
    @State private var occupation: String
    @State private var bio: String
    @State private var interests: String
    @State private var relationshipStatus: String
    @State private var locationLabel: String
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var showDistance: Bool
    @State private var hasBirthDate: Bool
    @State private var birthDate: Date
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isNameFocused: Bool
    @FocusState private var isCityFocused: Bool
    @FocusState private var isOccupationFocused: Bool
    @FocusState private var isInterestsFocused: Bool
    @FocusState private var isRelationshipFocused: Bool
    @FocusState private var isLocationFocused: Bool
    @StateObject private var locationPicker = ProfileLocationPicker()

    init(user: CurrentUser) {
        self.user = user
        _displayName = State(initialValue: user.displayName)
        _city = State(initialValue: user.city ?? "")
        _occupation = State(initialValue: user.occupation ?? "")
        _bio = State(initialValue: user.bio ?? "")
        _interests = State(initialValue: (user.interests ?? []).joined(separator: ", "))
        _relationshipStatus = State(initialValue: user.relationshipStatus ?? "")
        _locationLabel = State(initialValue: user.locationLabel ?? "")
        _latitude = State(initialValue: user.latitude)
        _longitude = State(initialValue: user.longitude)
        _showDistance = State(initialValue: user.showDistance ?? true)
        _hasBirthDate = State(initialValue: user.birthDate != nil)
        _birthDate = State(initialValue: user.birthDate.flatMap(ProfileDate.parse) ?? Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuthBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 16) {
                            AvatarPicker(initials: displayName.initials, size: 72)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("profile.avatar.title")
                                    .font(.headline)
                                Text("profile.avatar.helper")
                                    .font(.footnote)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }

                        ProfileInput(title: L10n.string("profile.field.name"), text: $displayName, isFocused: $isNameFocused, contentType: .name, capitalization: .words)
                        ProfileInput(title: L10n.string("profile.field.city"), text: $city, isFocused: $isCityFocused, contentType: .addressCity, capitalization: .words)
                        ProfileInput(title: L10n.string("profile.field.occupation"), text: $occupation, isFocused: $isOccupationFocused, capitalization: .sentences)
                        ProfileInput(title: L10n.string("profile.field.relationship"), text: $relationshipStatus, isFocused: $isRelationshipFocused, capitalization: .sentences)

                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("profile.location.title", systemImage: "location.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(GoNowTheme.primary)
                                TextField("profile.location.placeholder", text: $locationLabel)
                                    .textContentType(.fullStreetAddress)
                                    .textInputAutocapitalization(.words)
                                    .focused($isLocationFocused)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 50)
                                    .liquidGlassField(isInvalid: false, isFocused: isLocationFocused)
                                Button {
                                    locationPicker.requestCurrentLocation()
                                } label: {
                                    Label(
                                        locationPicker.isRequesting ? L10n.string("location.resolving") : L10n.string("location.use_current"),
                                        systemImage: "location.circle.fill"
                                    )
                                }
                                .buttonStyle(GlassInlineButtonStyle())
                                .disabled(locationPicker.isRequesting)

                                Toggle(isOn: $showDistance) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("profile.distance.toggle")
                                            .font(.subheadline.weight(.medium))
                                        Text("profile.distance.helper")
                                            .font(.footnote)
                                            .foregroundStyle(AppColors.textSecondary)
                                    }
                                }
                                .tint(GoNowTheme.primary)

                                if let locationError = locationPicker.errorMessage {
                                    ErrorMessage(text: locationError)
                                }
                            }
                        }

                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Image(systemName: "calendar.badge.exclamationmark")
                                        .foregroundStyle(AppColors.error)
                                    Text("profile.birth_date.required")
                                        .font(.subheadline.weight(.semibold))
                                }
                                if hasBirthDate {
                                    DatePicker("profile.birth_date.title", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                                        .datePickerStyle(.compact)
                                } else {
                                    Button("profile.birth_date.add") { hasBirthDate = true }
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(GoNowTheme.primary)
                                        .frame(minHeight: 44)
                                }
                                Text("profile.birth_date.helper")
                                    .font(.footnote)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }

                        ProfileInput(title: L10n.string("profile.interests.title"), text: $interests, isFocused: $isInterestsFocused, capitalization: .sentences)
                        Text("profile.interests.helper")
                            .font(.footnote)
                            .foregroundStyle(AppColors.textSecondary)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("profile.bio.title")
                                .font(.subheadline.weight(.medium))
                            TextEditor(text: $bio)
                                .font(.body)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 118)
                                .padding(10)
                                .liquidGlassField(isInvalid: false, isFocused: false)
                            Text("profile.bio.limit")
                                .font(.footnote)
                                .foregroundStyle(AppColors.textSecondary)
                        }

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(AppColors.error)
                        }

                        Button(isSaving ? L10n.string("common.saving") : L10n.string("profile.save")) { save() }
                            .buttonStyle(GradientPrimaryButtonStyle())
                            .disabled(isSaving)
                    }
                    .padding(24)
                }
            }
            .navigationTitle("profile.my_profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? L10n.string("common.saving") : L10n.string("common.save")) { save() }
                        .foregroundStyle(GoNowTheme.primary)
                        .disabled(isSaving)
                }
            }
        }
        .presentationDetents([.large])
        .onChange(of: locationPicker.coordinate?.latitude) { _, _ in
            latitude = locationPicker.coordinate?.latitude
            longitude = locationPicker.coordinate?.longitude
            if let label = locationPicker.label, !label.isEmpty {
                locationLabel = label
            }
        }
    }

    private func save() {
        let items = interests
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard displayName.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else {
            errorMessage = L10n.string("validation.name.too_short")
            return
        }
        guard hasBirthDate else {
            errorMessage = L10n.string("validation.birth_date.required")
            return
        }
        isSaving = true
        errorMessage = nil
        let payload = UpdateProfilePayload(
            displayName: displayName,
            birthDate: ProfileDate.format(birthDate),
            city: city.nilIfEmpty,
            occupation: occupation.nilIfEmpty,
            bio: bio.nilIfEmpty,
            interests: items,
            relationshipStatus: relationshipStatus.nilIfEmpty,
            locationLabel: locationLabel.nilIfEmpty,
            latitude: latitude,
            longitude: longitude,
            showDistance: showDistance
        )
        Task {
            defer { isSaving = false }
            do {
                try await appState.updateProfile(payload)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct ProfileInput: View {
    let title: String
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    var contentType: UITextContentType? = nil
    var capitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
            TextField(title, text: $text)
                .textContentType(contentType)
                .textInputAutocapitalization(capitalization)
                .focused($isFocused)
                .padding(.horizontal, 16)
                .frame(minHeight: 54)
                .liquidGlassField(isInvalid: false, isFocused: isFocused)
        }
    }
}
