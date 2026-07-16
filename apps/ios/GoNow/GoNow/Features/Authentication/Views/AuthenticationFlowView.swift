import SwiftUI
import UIKit

struct AuthenticationFlowView: View {
    @State private var isRegistering = false

    var body: some View {
        NavigationStack {
            Group {
                if isRegistering { RegisterView(onShowLogin: { isRegistering = false }) }
                else { LoginView(onShowRegister: { isRegistering = true }) }
            }
                .animation(.easeInOut(duration: 0.2), value: isRegistering)
        }
        .tint(GoNowTheme.primary)
    }
}

private struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @State private var email = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var fieldErrors: [String: String] = [:]
    @FocusState private var isEmailFocused: Bool
    @FocusState private var isPasswordFocused: Bool
    let onShowRegister: () -> Void

    var body: some View {
        ZStack {
            AuthBackdrop()
            ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                brandHeader(title: "Рядом — интереснее", subtitle: "Войдите, чтобы находить людей для активностей рядом.")
                VStack(spacing: 16) {
                    AuthTextField(title: "Email", text: $email, error: fieldErrors["email"], isFocused: $isEmailFocused, contentType: .emailAddress, keyboard: .emailAddress, capitalization: .never)
                    PasswordField(title: "Пароль", text: $password, isVisible: $isPasswordVisible, error: fieldErrors["password"], isFocused: $isPasswordFocused, contentType: .password)
                }
                if let errorMessage { ErrorMessage(text: errorMessage) }
                Button(action: submit) {
                    if isLoading { ProgressView().tint(.white).frame(maxWidth: .infinity) }
                    else { Text("Войти").frame(maxWidth: .infinity) }
                }
                .buttonStyle(GradientPrimaryButtonStyle())
                .disabled(isLoading)
                .accessibilityHint("Выполнить вход с указанным email и паролем")
                HStack(spacing: 4) {
                    Text("Впервые в GoNow?").foregroundStyle(.secondary)
                    Button("Создать аккаунт", action: onShowRegister)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(GoNowTheme.primary)
                        .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(24)
            .frame(maxWidth: 520, alignment: .leading)
            }
        }
        .navigationTitle("Вход")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() {
        fieldErrors = ["email": AuthValidation.email(email), "password": AuthValidation.password(password)].compactMapValues { $0 }
        guard fieldErrors.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        Task {
            defer { isLoading = false }
            do { try await appState.login(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password) }
            catch let error as APIError { fieldErrors = error.fieldErrors; errorMessage = error.localizedDescription }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct RegisterView: View {
    @EnvironmentObject private var appState: AppState
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var isPasswordVisible = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var fieldErrors: [String: String] = [:]
    @FocusState private var isNameFocused: Bool
    @FocusState private var isEmailFocused: Bool
    @FocusState private var isPasswordFocused: Bool
    @FocusState private var isConfirmationFocused: Bool
    let onShowLogin: () -> Void

    var body: some View {
        ZStack {
            AuthBackdrop()
            ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                brandHeader(title: "Ваши планы начинаются здесь", subtitle: "Создайте аккаунт — это займёт меньше минуты.")
                VStack(spacing: 16) {
                    AuthTextField(title: "Ваше имя", text: $name, error: fieldErrors["displayName"], isFocused: $isNameFocused, contentType: .name, capitalization: .words)
                    AuthTextField(title: "Email", text: $email, error: fieldErrors["email"], isFocused: $isEmailFocused, contentType: .emailAddress, keyboard: .emailAddress, capitalization: .never)
                    PasswordField(title: "Пароль", text: $password, isVisible: $isPasswordVisible, error: fieldErrors["password"], isFocused: $isPasswordFocused, contentType: .newPassword)
                    PasswordField(title: "Повторите пароль", text: $confirmation, isVisible: $isPasswordVisible, error: fieldErrors["confirmation"], isFocused: $isConfirmationFocused, contentType: .newPassword)
                }
                Text("Минимум 8 символов. Не используйте очевидный пароль.").font(.footnote).foregroundStyle(.secondary)
                if let errorMessage { ErrorMessage(text: errorMessage) }
                Button(action: submit) {
                    if isLoading { ProgressView().tint(.white).frame(maxWidth: .infinity) }
                    else { Text("Создать аккаунт").frame(maxWidth: .infinity) }
                }
                .buttonStyle(GradientPrimaryButtonStyle())
                .disabled(isLoading)
                HStack(spacing: 4) {
                    Text("Уже есть аккаунт?").foregroundStyle(.secondary)
                    Button("Войти", action: onShowLogin)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(GoNowTheme.primary)
                        .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(24)
            .frame(maxWidth: 520, alignment: .leading)
            }
        }
        .navigationTitle("Регистрация")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submit() {
        var errors: [String: String] = [:]
        if name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 { errors["displayName"] = "Введите имя не короче 2 символов" }
        if let error = AuthValidation.email(email) { errors["email"] = error }
        if let error = AuthValidation.password(password) { errors["password"] = error }
        if let error = AuthValidation.matchingPasswords(password, confirmation) { errors["confirmation"] = error }
        fieldErrors = errors
        guard errors.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        Task {
            defer { isLoading = false }
            do { try await appState.register(name: name.trimmingCharacters(in: .whitespacesAndNewlines), email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password) }
            catch let error as APIError { fieldErrors = error.fieldErrors; errorMessage = error.localizedDescription }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

private func brandHeader(title: String, subtitle: String) -> some View {
    VStack(alignment: .center, spacing: 12) {
        MapPointMarker(size: 84)
            .frame(width: 84, height: 84)
            .accessibilityHidden(true)
        Text(title)
            .font(.largeTitle.bold())
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        Text(subtitle)
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity)
}

private struct AuthTextField: View {
    let title: String
    @Binding var text: String
    let error: String?
    @FocusState.Binding var isFocused: Bool
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium))
            TextField(title, text: $text)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled(keyboard == .emailAddress)
                .focused($isFocused)
                .padding(.horizontal, 16).frame(minHeight: 54)
                .liquidGlassField(isInvalid: error != nil, isFocused: isFocused)
            if let error { ErrorMessage(text: error) }
        }
    }
}

private struct PasswordField: View {
    let title: String
    @Binding var text: String
    @Binding var isVisible: Bool
    let error: String?
    @FocusState.Binding var isFocused: Bool
    var contentType: UITextContentType

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium))
            HStack {
                Group { if isVisible { TextField(title, text: $text) } else { SecureField(title, text: $text) } }
                    .textContentType(contentType)
                    .focused($isFocused)
                Button(isVisible ? "Скрыть" : "Показать") { isVisible.toggle() }
                    .buttonStyle(GlassInlineButtonStyle())
                    .accessibilityLabel(isVisible ? "Скрыть пароль" : "Показать пароль")
            }
            .padding(.horizontal, 16).frame(minHeight: 54)
            .liquidGlassField(isInvalid: error != nil, isFocused: isFocused)
            if let error { ErrorMessage(text: error) }
        }
    }
}
