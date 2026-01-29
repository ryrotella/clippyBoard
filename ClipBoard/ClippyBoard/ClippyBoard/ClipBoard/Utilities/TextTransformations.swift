import Foundation

enum TextTransformation: String, CaseIterable {
    // Case transformations
    case uppercase = "UPPERCASE"
    case lowercase = "lowercase"
    case titleCase = "Title Case"

    // Developer transformations
    case camelCase = "camelCase"
    case snakeCase = "snake_case"
    case kebabCase = "kebab-case"

    // Cleanup transformations
    case trimWhitespace = "Trim Whitespace"
    case urlEncode = "URL Encode"
    case urlDecode = "URL Decode"

    var icon: String {
        switch self {
        case .uppercase:
            return "textformat.size.larger"
        case .lowercase:
            return "textformat.size.smaller"
        case .titleCase:
            return "textformat"
        case .camelCase:
            return "chevron.left.forwardslash.chevron.right"
        case .snakeCase:
            return "underline"
        case .kebabCase:
            return "minus"
        case .trimWhitespace:
            return "scissors"
        case .urlEncode:
            return "link"
        case .urlDecode:
            return "link.badge.plus"
        }
    }

    func apply(to text: String) -> String {
        switch self {
        case .uppercase:
            return text.uppercased()

        case .lowercase:
            return text.lowercased()

        case .titleCase:
            return text.capitalized

        case .camelCase:
            return toCamelCase(text)

        case .snakeCase:
            return toSnakeCase(text)

        case .kebabCase:
            return toKebabCase(text)

        case .trimWhitespace:
            return text.trimmingCharacters(in: .whitespacesAndNewlines)

        case .urlEncode:
            return text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text

        case .urlDecode:
            return text.removingPercentEncoding ?? text
        }
    }

    // MARK: - Private Helpers

    private func toCamelCase(_ text: String) -> String {
        let words = splitIntoWords(text)
        guard !words.isEmpty else { return text }

        var result = words[0].lowercased()
        for word in words.dropFirst() {
            result += word.capitalized
        }
        return result
    }

    private func toSnakeCase(_ text: String) -> String {
        let words = splitIntoWords(text)
        return words.map { $0.lowercased() }.joined(separator: "_")
    }

    private func toKebabCase(_ text: String) -> String {
        let words = splitIntoWords(text)
        return words.map { $0.lowercased() }.joined(separator: "-")
    }

    private func splitIntoWords(_ text: String) -> [String] {
        // Handle already camelCase or PascalCase
        var result = text

        // Insert space before uppercase letters that follow lowercase letters
        var chars: [Character] = []
        for (index, char) in result.enumerated() {
            if index > 0 && char.isUppercase {
                let prevIndex = result.index(result.startIndex, offsetBy: index - 1)
                if result[prevIndex].isLowercase {
                    chars.append(" ")
                }
            }
            chars.append(char)
        }
        result = String(chars)

        // Replace common separators with spaces
        result = result.replacingOccurrences(of: "_", with: " ")
        result = result.replacingOccurrences(of: "-", with: " ")

        // Split by whitespace and filter empty strings
        return result.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    }
}
