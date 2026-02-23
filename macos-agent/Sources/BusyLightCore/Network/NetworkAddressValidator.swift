import Foundation

public enum NetworkAddressValidator {
    public static func normalizeIPv4Address(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }

        for part in parts {
            if part.isEmpty { return nil }
            if part.count > 3 { return nil }
            guard let octet = Int(part), (0...255).contains(octet) else { return nil }
        }

        return trimmed
    }

    public static func isValidIPv4Address(_ input: String) -> Bool {
        return normalizeIPv4Address(input) != nil
    }
}
