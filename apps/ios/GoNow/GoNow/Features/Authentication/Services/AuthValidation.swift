import Foundation

enum AuthValidation {
    static func email(_ value: String) -> String? {
        let pattern = "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$"
        return value.range(of: pattern, options: .regularExpression) == nil ? L10n.string("validation.email.invalid") : nil
    }

    static func password(_ value: String) -> String? {
        if value.count < 8 { return L10n.string("validation.password.too_short") }
        if value.count > 128 { return L10n.string("validation.password.too_long") }
        return nil
    }

    static func matchingPasswords(_ password: String, _ confirmation: String) -> String? {
        password == confirmation ? nil : L10n.string("validation.password.mismatch")
    }
}
