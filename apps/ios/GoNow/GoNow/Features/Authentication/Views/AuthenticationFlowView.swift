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
    @State private var isPasswordRecoveryPresented = false
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
                Button("Забыли пароль?") { isPasswordRecoveryPresented = true }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(GoNowTheme.primary)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .trailing)
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
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 28)
            .frame(maxWidth: 520, alignment: .leading)
            }
        }
        .sheet(isPresented: $isPasswordRecoveryPresented) {
            PasswordRecoverySheet(initialEmail: email)
        }
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
    @State private var verificationEmail: String?
    let onShowLogin: () -> Void

    var body: some View {
        ZStack {
            AuthBackdrop()
            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 28)
            .frame(maxWidth: 520, alignment: .leading)
            }
        }
        .sheet(isPresented: Binding(get: { verificationEmail != nil }, set: { if !$0 { verificationEmail = nil } })) {
            if let verificationEmail { EmailVerificationSheet(email: verificationEmail) }
        }
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
            do { verificationEmail = try await appState.register(name: name.trimmingCharacters(in: .whitespacesAndNewlines), email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password).email }
            catch let error as APIError { fieldErrors = error.fieldErrors; errorMessage = error.localizedDescription }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct EmailVerificationSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let email: String
    @State private var code = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                AuthBackdrop()
                VStack(alignment: .leading, spacing: 20) {
                    MapPointMarker(size: 62).frame(maxWidth: .infinity)
                    Text("Подтвердите email").font(.title.bold())
                    Text("Мы отправили шестизначный код на \(email).")
                        .foregroundStyle(.secondary)
                    TextField("000000", text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($isFocused)
                        .multilineTextAlignment(.center)
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 16).frame(minHeight: 58)
                        .liquidGlassField(isInvalid: errorMessage != nil, isFocused: isFocused)
                        .accessibilityLabel("Шестизначный код подтверждения")
                    if let errorMessage { ErrorMessage(text: errorMessage) }
                    Button(isLoading ? "Проверяем…" : "Подтвердить") { verify() }
                        .buttonStyle(GradientPrimaryButtonStyle())
                        .disabled(isLoading || code.count != 6)
                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("Подтверждение")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }

    private func verify() {
        isLoading = true; errorMessage = nil
        Task { defer { isLoading = false }; do { try await appState.verifyEmail(email: email, code: code); dismiss() } catch { errorMessage = error.localizedDescription } }
    }
}

private struct PasswordRecoverySheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var email: String
    @State private var code = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var isPasswordVisible = false
    @State private var isCodeRequested = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var isEmailFocused: Bool
    @FocusState private var isCodeFocused: Bool
    @FocusState private var isPasswordFocused: Bool
    @FocusState private var isConfirmationFocused: Bool

    init(initialEmail: String) {
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuthBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        MapPointMarker(size: 58)
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                        Text(isCodeRequested ? "Установите новый пароль" : "Восстановление пароля")
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(isCodeRequested
                             ? "Введите код из письма и придумайте новый пароль."
                             : "Введите email. Если аккаунт существует, мы отправим код для восстановления.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if isCodeRequested {
                            VStack(spacing: 16) {
                                TextField("Код из письма", text: $code)
                                    .keyboardType(.numberPad)
                                    .textContentType(.oneTimeCode)
                                    .focused($isCodeFocused)
                                    .multilineTextAlignment(.center)
                                    .font(.title3.monospacedDigit().weight(.semibold))
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 54)
                                    .liquidGlassField(isInvalid: false, isFocused: isCodeFocused)
                                    .accessibilityLabel("Шестизначный код восстановления")
                                PasswordField(title: "Новый пароль", text: $password, isVisible: $isPasswordVisible, error: nil, isFocused: $isPasswordFocused, contentType: .newPassword)
                                PasswordField(title: "Повторите пароль", text: $confirmation, isVisible: $isPasswordVisible, error: nil, isFocused: $isConfirmationFocused, contentType: .newPassword)
                            }
                        } else {
                            AuthTextField(title: "Email", text: $email, error: nil, isFocused: $isEmailFocused, contentType: .emailAddress, keyboard: .emailAddress, capitalization: .never)
                        }

                        if let errorMessage { ErrorMessage(text: errorMessage) }

                        Button(isLoading ? "Подождите…" : (isCodeRequested ? "Изменить пароль" : "Получить код")) {
                            isCodeRequested ? resetPassword() : requestCode()
                        }
                        .buttonStyle(GradientPrimaryButtonStyle())
                        .disabled(isLoading)

                        if isCodeRequested {
                            Button("Отправить код ещё раз") { requestCode() }
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(GoNowTheme.primary)
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity)
                                .disabled(isLoading)
                        }
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Восстановление")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Отмена") { dismiss() }
                        .foregroundStyle(GoNowTheme.primary)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func requestCode() {
        guard let validationError = AuthValidation.email(email) else {
            isLoading = true
            errorMessage = nil
            Task {
                defer { isLoading = false }
                do {
                    try await appState.requestPasswordReset(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
                    isCodeRequested = true
                    isCodeFocused = true
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            return
        }
        errorMessage = validationError
    }

    private func resetPassword() {
        guard code.count == 6 else {
            errorMessage = "Введите шестизначный код из письма"
            return
        }
        if let validationError = AuthValidation.password(password) {
            errorMessage = validationError
            return
        }
        if let validationError = AuthValidation.matchingPasswords(password, confirmation) {
            errorMessage = validationError
            return
        }
        isLoading = true
        errorMessage = nil
        Task {
            defer { isLoading = false }
            do {
                try await appState.resetPassword(email: email.trimmingCharacters(in: .whitespacesAndNewlines), code: code, password: password)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
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
                Button { isVisible.toggle() } label: {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .foregroundStyle(GoNowTheme.primary)
                .background(.thinMaterial, in: Circle())
                .glassEffect(.regular, in: Circle())
                .overlay { Circle().strokeBorder(.white.opacity(0.72), lineWidth: 1) }
                    .accessibilityLabel(isVisible ? "Скрыть пароль" : "Показать пароль")
            }
            .padding(.horizontal, 16).frame(minHeight: 54)
            .liquidGlassField(isInvalid: error != nil, isFocused: isFocused)
            if let error { ErrorMessage(text: error) }
        }
    }
}
