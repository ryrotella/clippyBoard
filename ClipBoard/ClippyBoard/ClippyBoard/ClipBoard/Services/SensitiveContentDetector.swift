import Foundation

/// Detects potentially sensitive content like passwords, API keys, and tokens
enum SensitiveContentDetector {

    /// Known API key and token prefixes
    private static let knownPrefixes: [String] = [
        // OpenAI
        "sk-proj-", "sk-",
        // Anthropic
        "sk-ant-",
        // GitHub
        "ghp_", "gho_", "ghu_", "ghs_", "ghr_",
        // GitLab
        "glpat-",
        // Stripe
        "sk_live_", "pk_live_", "sk_test_", "pk_test_", "rk_live_", "rk_test_",
        // AWS
        "AKIA", "ABIA", "ACCA", "AGPA", "AIDA", "AIPA", "ANPA", "ANVA", "APKA", "AROA", "ASCA", "ASIA",
        // Slack
        "xoxb-", "xoxp-", "xoxa-", "xoxr-",
        // Twilio
        "SK",
        // SendGrid
        "SG.",
        // Mailchimp
        "-us", // API keys end with region like "-us19"
        // Discord
        "Bot ", "Bearer ",
        // Google
        "AIza",
        // Heroku
        "HRKU-",
        // DigitalOcean
        "dop_v1_",
        // npm
        "npm_",
        // PyPI
        "pypi-",
        // NuGet
        "oy2",
        // Shopify
        "shpat_", "shpca_", "shppa_",
        // Linear
        "lin_api_",
        // Vercel
        "vercel_",
        // Supabase
        "sbp_",
        // PlanetScale
        "pscale_",
        // Railway
        "railway_",
        // Doppler
        "dp.st.",
        // Postman
        "PMAK-",
        // Figma
        "figd_",
    ]

    /// Patterns that indicate sensitive content
    private static let sensitivePatterns: [NSRegularExpression] = {
        let patterns = [
            // JWT tokens (header.payload.signature)
            #"^eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+"#,
            // AWS Access Key ID
            #"^AKIA[0-9A-Z]{16}$"#,
            // AWS Secret Access Key (40 char base64-like)
            #"^[A-Za-z0-9/+=]{40}$"#,
            // Generic API key patterns (long alphanumeric with dashes/underscores)
            #"^[a-zA-Z0-9_-]{32,}$"#,
            // UUID-based tokens
            #"^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$"#,
            // Hex strings (32+ chars, likely hashes or keys)
            #"^[a-fA-F0-9]{32,}$"#,
            // Base64-encoded data (likely secrets if 20+ chars)
            #"^[A-Za-z0-9+/]{20,}={0,2}$"#,
            // Private key markers
            #"-----BEGIN.*PRIVATE KEY-----"#,
            #"-----BEGIN.*SECRET-----"#,
            // Connection strings
            #"^(mongodb|postgresql|mysql|redis|amqp|mssql)(\+srv)?://"#,
            // Bearer token in header format
            #"^Bearer\s+[A-Za-z0-9_-]+"#,
        ]

        return patterns.compactMap { pattern in
            try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
    }()

    /// Checks if the given text appears to be sensitive content
    /// - Parameter text: The text to analyze
    /// - Returns: True if the content appears to be a password, API key, or token
    static func isSensitive(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip very short or very long content
        guard trimmed.count >= 8 && trimmed.count <= 500 else {
            return false
        }

        // Skip if it contains spaces (likely not a single token/key)
        // Exception: "Bearer " prefix
        if trimmed.contains(" ") && !trimmed.hasPrefix("Bearer ") {
            return false
        }

        // Check for known prefixes
        for prefix in knownPrefixes {
            if trimmed.hasPrefix(prefix) {
                return true
            }
        }

        // Check against regex patterns
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        for pattern in sensitivePatterns {
            if pattern.firstMatch(in: trimmed, options: [], range: range) != nil {
                return true
            }
        }

        // Entropy check for high-randomness strings
        if isHighEntropy(trimmed) && looksLikeSecret(trimmed) {
            return true
        }

        return false
    }

    /// Calculates Shannon entropy of a string
    /// High entropy indicates randomness (likely a generated secret)
    private static func isHighEntropy(_ text: String) -> Bool {
        guard text.count >= 16 else { return false }

        var frequency: [Character: Int] = [:]
        for char in text {
            frequency[char, default: 0] += 1
        }

        let length = Double(text.count)
        var entropy: Double = 0

        for (_, count) in frequency {
            let probability = Double(count) / length
            entropy -= probability * log2(probability)
        }

        // Threshold: random base64 has entropy ~5.7, English text ~4.0
        // API keys typically have entropy > 4.5
        return entropy > 4.5
    }

    /// Additional heuristics to check if a string looks like a secret
    private static func looksLikeSecret(_ text: String) -> Bool {
        // Must be alphanumeric with allowed special chars
        let allowedSet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-+=/."))
        guard text.unicodeScalars.allSatisfy({ allowedSet.contains($0) }) else {
            return false
        }

        // Should have a mix of character types for generated secrets
        let hasUppercase = text.contains(where: { $0.isUppercase })
        let hasLowercase = text.contains(where: { $0.isLowercase })
        let hasDigit = text.contains(where: { $0.isNumber })

        // Generated secrets typically have at least 2 of these 3
        let typeCount = [hasUppercase, hasLowercase, hasDigit].filter { $0 }.count
        return typeCount >= 2
    }
}
