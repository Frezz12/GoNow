import Foundation
import CoreLocation
import SwiftUI
import UIKit

struct ProfileSetupPrompt: View {
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppColors.textOnAccent)
                .frame(width: 42, height: 42)
                .background(GoNowTheme.buttonGradient, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text("Расскажите о себе")
                    .font(.subheadline.weight(.semibold))
                Text("Это займёт около минуты.")
                    .font(.footnote)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer(minLength: 8)

            Button("Заполнить") { action() }
                .buttonStyle(GlassInlineButtonStyle())
                .accessibilityLabel("Заполнить профиль")
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.76), lineWidth: 1)
        }
        .shadow(color: GoNowTheme.primary.opacity(0.14), radius: 12, y: 5)
    }
}

struct ProfileSetupFlow: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let user: CurrentUser

    @State private var step = 0
    @State private var birthDate: Date
    @State private var city: String
    @State private var occupation: String
    @State private var relationshipStatus: String
    @State private var interests: String
    @State private var bio: String
    @State private var locationLabel: String
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var showDistance: Bool
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: SetupField?
    @StateObject private var locationPicker = ProfileLocationPicker()

    private enum SetupField: Hashable {
        case city, occupation, relationshipStatus, interests, location
    }

    init(user: CurrentUser) {
        self.user = user
        _birthDate = State(initialValue: Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now)
        _city = State(initialValue: user.city ?? "")
        _occupation = State(initialValue: user.occupation ?? "")
        _relationshipStatus = State(initialValue: user.relationshipStatus ?? "")
        _interests = State(initialValue: (user.interests ?? []).joined(separator: ", "))
        _bio = State(initialValue: user.bio ?? "")
        _locationLabel = State(initialValue: user.locationLabel ?? "")
        _latitude = State(initialValue: user.latitude)
        _longitude = State(initialValue: user.longitude)
        _showDistance = State(initialValue: user.showDistance ?? true)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuthBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        progress
                        stepContent
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(AppColors.error)
                        }
                        controls
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Заполнение профиля")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") { dismiss() }
                        .foregroundStyle(GoNowTheme.primary)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .onChange(of: locationPicker.coordinate?.latitude) { _, _ in
            latitude = locationPicker.coordinate?.latitude
            longitude = locationPicker.coordinate?.longitude
            if let label = locationPicker.label, !label.isEmpty {
                locationLabel = label
            }
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Шаг \(step + 1) из 4")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(GoNowTheme.primary)
            GeometryReader { proxy in
                Capsule()
                    .fill(.white.opacity(0.45))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(GoNowTheme.buttonGradient)
                            .frame(width: proxy.size.width * CGFloat(step + 1) / 4)
                    }
            }
            .frame(height: 6)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0:
            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "calendar.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(GoNowTheme.primary)
                    Text("Когда у вас день рождения?")
                        .font(.title2.bold())
                    Text("Дата нужна, чтобы безопасно подбирать активности по возрасту. Её не увидят другие пользователи.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                    DatePicker("Дата рождения", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                }
            }
        case 1:
            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Чем вы занимаетесь?")
                        .font(.title2.bold())
                    Text("Эти поля необязательны — их можно пропустить и изменить позже.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                    setupField("Город", text: $city, field: .city, contentType: .addressCity)
                    setupField("Чем занимаетесь", text: $occupation, field: .occupation)
                    setupField("Семейный статус", text: $relationshipStatus, field: .relationshipStatus)
                }
            }
        case 2:
            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(GoNowTheme.primary)
                    Text("Где вы сейчас?")
                        .font(.title2.bold())
                    Text("Укажите район, город или место вручную — либо используйте геолокацию. Точный адрес никто не увидит.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                    setupField("Район, город или место", text: $locationLabel, field: .location)
                    Button {
                        locationPicker.requestCurrentLocation()
                    } label: {
                        Label(
                            locationPicker.isRequesting ? "Определяем место…" : "Использовать мою геолокацию",
                            systemImage: "location.fill"
                        )
                    }
                    .buttonStyle(GlassInlineButtonStyle())
                    .disabled(locationPicker.isRequesting)

                    Toggle(isOn: $showDistance) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Показывать расстояние до меня")
                                .font(.subheadline.weight(.medium))
                            Text("Люди увидят только примерное расстояние, без адреса.")
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
        default:
            GlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Пара штрихов о вас")
                        .font(.title2.bold())
                    Text("Добавьте интересы, чтобы людям было проще начать разговор.")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textSecondary)
                    setupField("Интересы", text: $interests, field: .interests)
                    Text("Через запятую: прогулки, кино, йога")
                        .font(.footnote)
                        .foregroundStyle(AppColors.textSecondary)
                    TextEditor(text: $bio)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 112)
                        .padding(10)
                        .liquidGlassField(isInvalid: false, isFocused: false)
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button("Назад") { step -= 1 }
                    .buttonStyle(GlassSecondaryButtonStyle())
            }
            Button(step == 3 ? (isSaving ? "Сохраняем…" : "Готово") : "Далее") {
                advance()
            }
            .buttonStyle(GradientPrimaryButtonStyle())
            .disabled(isSaving)
        }
    }

    private func setupField(
        _ title: String,
        text: Binding<String>,
        field: SetupField,
        contentType: UITextContentType? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
            TextField(title, text: text)
                .textContentType(contentType)
                .textInputAutocapitalization(.sentences)
                .focused($focusedField, equals: field)
                .padding(.horizontal, 16)
                .frame(minHeight: 54)
                .liquidGlassField(isInvalid: false, isFocused: focusedField == field)
        }
    }

    private func advance() {
        errorMessage = nil
        if step < 3 {
            withAnimation(.easeOut(duration: 0.22)) { step += 1 }
            return
        }

        let parsedInterests = interests
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        isSaving = true
        let payload = UpdateProfilePayload(
            displayName: user.displayName,
            birthDate: ProfileDate.format(birthDate),
            city: city.nilIfEmpty,
            occupation: occupation.nilIfEmpty,
            bio: bio.nilIfEmpty,
            interests: parsedInterests,
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
