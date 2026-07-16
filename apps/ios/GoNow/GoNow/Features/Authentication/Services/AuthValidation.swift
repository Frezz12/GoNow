import Foundation

enum AuthValidation {
    static func email(_ value: String) -> String? {
        let pattern = "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$"
        return value.range(of: pattern, options: .regularExpression) == nil ? "Введите корректный email" : nil
    }

    static func password(_ value: String) -> String? {
        if value.count < 8 { return "Пароль должен содержать минимум 8 символов" }
        if value.count > 128 { return "Пароль не должен быть длиннее 128 символов" }
        return nil
    }

    static func matchingPasswords(_ password: String, _ confirmation: String) -> String? {
        password == confirmation ? nil : "Пароли не совпадают"
    }
}
