import Foundation

struct PreparedDocumentPreparationOptions: Equatable {
    let enrichUsingUnrealMaterialProps: Bool

    var preparationFlavor: String {
        enrichUsingUnrealMaterialProps ? "base+unreal-materials-v1" : "base-v1"
    }

    static func current() -> PreparedDocumentPreparationOptions {
        PreparedDocumentPreparationOptions(
            enrichUsingUnrealMaterialProps: PreparedDocumentSettings.isUnrealMaterialEnrichmentEnabled()
        )
    }
}

enum PreparedDocumentSettings {
    static let suiteName = "com.hectorlizard.GLTFQuickLook"
    static let unrealMaterialEnrichmentKey = "EnableUnrealMaterialEnrichment"

    static func isUnrealMaterialEnrichmentEnabled() -> Bool {
        defaults.bool(forKey: unrealMaterialEnrichmentKey)
    }

    static func setUnrealMaterialEnrichmentEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: unrealMaterialEnrichmentKey)
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }
}
