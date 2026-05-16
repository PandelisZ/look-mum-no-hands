import Foundation

public enum InteractionRiskCategory: String, Codable, Sendable {
    case safeObservation = "safe_observation"
    case normalInteraction = "normal_interaction"
    case sensitiveInput = "sensitive_input"
    case externalTransmission = "external_transmission"
    case destructive
    case financial
    case credential
    case systemSettings = "system_settings"
    case codeExecution = "code_execution"
    case downloadOrInstall = "download_or_install"
    case unknownHighImpact = "unknown_high_impact"
}

public struct InteractionRisk: Codable, Sendable, Equatable {
    public var category: InteractionRiskCategory
    public var requiresConfirmation: Bool
    public var reasons: [String]

    public init(
        category: InteractionRiskCategory = .normalInteraction,
        requiresConfirmation: Bool = false,
        reasons: [String] = []
    ) {
        self.category = category
        self.requiresConfirmation = requiresConfirmation
        self.reasons = reasons
    }
}

public struct SafetyClassifier: Sendable {
    private let destructiveTerms = ["delete", "remove", "discard", "erase", "trash", "destroy", "reset"]
    private let sendTerms = ["send", "submit", "post", "publish", "share", "reply", "comment"]
    private let financialTerms = ["pay", "buy", "purchase", "checkout", "transfer", "withdraw", "deposit"]
    private let settingsTerms = ["privacy", "security", "permission", "vpn", "profile", "password", "login item"]
    private let codeExecutionTerms = ["run", "execute", "terminal", "script", "shell", "command"]
    private let installTerms = ["install", "download", "open installer", "mount"]

    public init() {}

    public func classifyElement(
        role: String?,
        title: String?,
        label: String?,
        valuePreview: String?,
        isSecureTextEntry: Bool
    ) -> InteractionRisk {
        if isSecureTextEntry {
            return InteractionRisk(
                category: .credential,
                requiresConfirmation: true,
                reasons: ["secure text field"]
            )
        }

        let haystack = [role, title, label, valuePreview]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        if let risk = classifyText(haystack) {
            return risk
        }

        return InteractionRisk(category: .normalInteraction, requiresConfirmation: false, reasons: [])
    }

    public func classifyText(_ text: String) -> InteractionRisk? {
        let lowercased = text.lowercased()

        if containsAny(destructiveTerms, in: lowercased) {
            return InteractionRisk(category: .destructive, requiresConfirmation: true, reasons: ["label suggests destructive action"])
        }

        if containsAny(sendTerms, in: lowercased) {
            return InteractionRisk(category: .externalTransmission, requiresConfirmation: true, reasons: ["label suggests external transmission"])
        }

        if containsAny(financialTerms, in: lowercased) {
            return InteractionRisk(category: .financial, requiresConfirmation: true, reasons: ["label suggests financial action"])
        }

        if containsAny(settingsTerms, in: lowercased) {
            return InteractionRisk(category: .systemSettings, requiresConfirmation: true, reasons: ["label suggests system or security settings"])
        }

        if containsAny(codeExecutionTerms, in: lowercased) {
            return InteractionRisk(category: .codeExecution, requiresConfirmation: true, reasons: ["label suggests code or command execution"])
        }

        if containsAny(installTerms, in: lowercased) {
            return InteractionRisk(category: .downloadOrInstall, requiresConfirmation: true, reasons: ["label suggests download or installation"])
        }

        return nil
    }

    private func containsAny(_ needles: [String], in haystack: String) -> Bool {
        needles.contains { haystack.contains($0) }
    }
}
