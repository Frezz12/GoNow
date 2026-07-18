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
                .animation(AppAnimation.standard, value: isRegistering)
        }
        .tint(AppColors.accentPrimary)
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
        AuthenticationScreen {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                brandHeader(title: L10n.string("auth.login.hero.title"), subtitle: L10n.string("auth.login.hero.subtitle"))
                VStack(spacing: AppSpacing.md) {
                    AuthTextField(title: L10n.string("auth.field.email"), text: $email, error: fieldErrors["email"], isFocused: $isEmailFocused, contentType: .emailAddress, keyboard: .emailAddress, capitalization: .never)
                    PasswordField(title: L10n.string("auth.field.password"), text: $password, isVisible: $isPasswordVisible, error: fieldErrors["password"], isFocused: $isPasswordFocused, contentType: .password)
                }
                Button("auth.forgot_password") { isPasswordRecoveryPresented = true }
                    .font(AppTypography.captionStrong)
                    .foregroundStyle(AppColors.accentPrimary)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                if let errorMessage { ErrorMessage(text: errorMessage) }
                Button(action: submit) {
                    if isLoading { ProgressView().tint(AppColors.textOnAccent).frame(maxWidth: .infinity) }
                    else { Text("auth.sign_in").frame(maxWidth: .infinity) }
                }
                .buttonStyle(GradientPrimaryButtonStyle())
                .disabled(isLoading)
                .accessibilityHint("auth.sign_in.hint")
                HStack(spacing: 4) {
                    Text("auth.first_time").foregroundStyle(AppColors.textSecondary)
                    Button("auth.create_account", action: onShowRegister)
                        .font(AppTypography.captionStrong)
                        .foregroundStyle(AppColors.accentPrimary)
                        .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
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
        AuthenticationScreen {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                brandHeader(title: L10n.string("auth.register.hero.title"), subtitle: L10n.string("auth.register.hero.subtitle"))
                VStack(spacing: AppSpacing.md) {
                    AuthTextField(title: L10n.string("auth.field.name"), text: $name, error: fieldErrors["displayName"], isFocused: $isNameFocused, contentType: .name, capitalization: .words)
                    AuthTextField(title: L10n.string("auth.field.email"), text: $email, error: fieldErrors["email"], isFocused: $isEmailFocused, contentType: .emailAddress, keyboard: .emailAddress, capitalization: .never)
                    PasswordField(title: L10n.string("auth.field.password"), text: $password, isVisible: $isPasswordVisible, error: fieldErrors["password"], isFocused: $isPasswordFocused, contentType: .newPassword)
                    PasswordField(title: L10n.string("auth.field.password_confirm"), text: $confirmation, isVisible: $isPasswordVisible, error: fieldErrors["confirmation"], isFocused: $isConfirmationFocused, contentType: .newPassword)
                }
                Text("auth.password.helper")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                if let errorMessage { ErrorMessage(text: errorMessage) }
                Button(action: submit) {
                    if isLoading { ProgressView().tint(AppColors.textOnAccent).frame(maxWidth: .infinity) }
                    else { Text("auth.create_account").frame(maxWidth: .infinity) }
                }
                .buttonStyle(GradientPrimaryButtonStyle())
                .disabled(isLoading)
                HStack(spacing: 4) {
                    Text("auth.already_have_account").foregroundStyle(AppColors.textSecondary)
                    Button("auth.sign_in", action: onShowLogin)
                        .font(AppTypography.captionStrong)
                        .foregroundStyle(AppColors.accentPrimary)
                        .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: Binding(get: { verificationEmail != nil }, set: { if !$0 { verificationEmail = nil } })) {
            if let verificationEmail { EmailVerificationSheet(email: verificationEmail) }
        }
    }

    private func submit() {
        var errors: [String: String] = [:]
        if name.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 { errors["displayName"] = L10n.string("validation.name.too_short") }
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

/// A single, centered authentication canvas. Forms use the backdrop directly instead of a detached card.
private struct AuthenticationScreen<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            AuthBackdrop()

            GeometryReader { proxy in
                ScrollView {
                    VStack {
                        Spacer(minLength: AppSpacing.lg)
                        content
                            .frame(maxWidth: AppLayout.maxContentWidth, alignment: .leading)
                        Spacer(minLength: AppSpacing.lg)
                    }
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                    .padding(.horizontal, AppLayout.horizontalInset)
                    .padding(.vertical, AppSpacing.lg)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
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
                    Text("auth.verify.title").font(.title.bold())
                    Text("auth.verify.sent \(email)")
                    .foregroundStyle(AppColors.textSecondary)
                    TextField(text: $code, prompt: Text(verbatim: "000000")) {
                        Text(verbatim: "000000")
                    }
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($isFocused)
                        .multilineTextAlignment(.center)
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, AppSpacing.md).frame(minHeight: 58)
                        .liquidGlassField(isInvalid: errorMessage != nil, isFocused: isFocused)
                        .accessibilityLabel("auth.verify.code.accessibility")
                    if let errorMessage { ErrorMessage(text: errorMessage) }
                    Button(isLoading ? L10n.string("auth.verifying") : L10n.string("auth.verify.action")) { verify() }
                        .buttonStyle(GradientPrimaryButtonStyle())
                        .disabled(isLoading || code.count != 6)
                    Spacer()
                }
                .padding(AppSpacing.xl)
            }
            .navigationTitle("auth.verify.navigation_title")
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
                        Text(isCodeRequested ? L10n.string("auth.reset.new_password.title") : L10n.string("auth.reset.title"))
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(isCodeRequested
                             ? L10n.string("auth.reset.code.description")
                             : L10n.string("auth.reset.email.description"))
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textSecondary)

                        if isCodeRequested {
                            VStack(spacing: 16) {
                                TextField("auth.reset.code.placeholder", text: $code)
                                    .keyboardType(.numberPad)
                                    .textContentType(.oneTimeCode)
                                    .focused($isCodeFocused)
                                    .multilineTextAlignment(.center)
                                    .font(.title3.monospacedDigit().weight(.semibold))
                                    .padding(.horizontal, AppSpacing.md)
                                    .frame(minHeight: 54)
                                    .liquidGlassField(isInvalid: false, isFocused: isCodeFocused)
                                    .accessibilityLabel("auth.reset.code.accessibility")
                                PasswordField(title: L10n.string("auth.field.new_password"), text: $password, isVisible: $isPasswordVisible, error: nil, isFocused: $isPasswordFocused, contentType: .newPassword)
                                PasswordField(title: L10n.string("auth.field.password_confirm"), text: $confirmation, isVisible: $isPasswordVisible, error: nil, isFocused: $isConfirmationFocused, contentType: .newPassword)
                            }
                        } else {
                            AuthTextField(title: L10n.string("auth.field.email"), text: $email, error: nil, isFocused: $isEmailFocused, contentType: .emailAddress, keyboard: .emailAddress, capitalization: .never)
                        }

                        if let errorMessage { ErrorMessage(text: errorMessage) }

                        Button(isLoading ? L10n.string("common.please_wait") : (isCodeRequested ? L10n.string("auth.reset.action") : L10n.string("auth.reset.request_code"))) {
                            isCodeRequested ? resetPassword() : requestCode()
                        }
                        .buttonStyle(GradientPrimaryButtonStyle())
                        .disabled(isLoading)

                        if isCodeRequested {
                            Button("auth.reset.resend_code") { requestCode() }
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppColors.accentPrimary)
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity)
                                .disabled(isLoading)
                        }
                    }
                    .padding(AppSpacing.xl)
                }
            }
            .navigationTitle("auth.reset.navigation_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.cancel") { dismiss() }
                        .foregroundStyle(AppColors.accentPrimary)
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
            errorMessage = L10n.string("validation.code.six_digits")
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
    VStack(alignment: .center, spacing: AppSpacing.sm) {
        MapPointMarker(size: 84)
            .frame(width: 84, height: 84)
            .accessibilityHidden(true)
        Text(title)
            .font(AppTypography.largeTitle)
            .foregroundStyle(AppColors.textPrimary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        Text(subtitle)
            .font(AppTypography.body)
            .foregroundStyle(AppColors.textSecondary)
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
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title).font(AppTypography.captionStrong)
            TextField(title, text: $text)
                .textContentType(contentType)
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled(keyboard == .emailAddress)
                .focused($isFocused)
                .padding(.horizontal, AppSpacing.md).frame(minHeight: 54)
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
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title).font(AppTypography.captionStrong)
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
                .foregroundStyle(AppColors.accentPrimary)
                .background(.thinMaterial, in: Circle())
                .glassEffect(.regular, in: Circle())
                .overlay { Circle().strokeBorder(AppColors.glassBorder.opacity(0.72), lineWidth: 1) }
                    .accessibilityLabel(isVisible ? L10n.string("auth.password.hide") : L10n.string("auth.password.show"))
            }
            .padding(.horizontal, AppSpacing.md).frame(minHeight: 54)
            .liquidGlassField(isInvalid: error != nil, isFocused: isFocused)
            if let error { ErrorMessage(text: error) }
        }
    }
}
