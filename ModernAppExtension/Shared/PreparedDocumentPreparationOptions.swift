import Foundation

struct PreparedDocumentPreparationOptions: Equatable {
    let enrichUsingUnrealMaterialProps: Bool
    let ignoreUniformRedVertexColors: Bool

    var preparationFlavor: String {
        var parts = ["base-v1"]
        if enrichUsingUnrealMaterialProps {
            parts.append("unreal-materials-v1")
        }
        if ignoreUniformRedVertexColors {
            parts.append("ignore-red-vertex-colors-v1")
        }
        return parts.joined(separator: "+")
    }

    static func current() -> PreparedDocumentPreparationOptions {
        PreparedDocumentPreparationOptions(
            enrichUsingUnrealMaterialProps: PreparedDocumentSettings.isUnrealMaterialEnrichmentEnabled(),
            ignoreUniformRedVertexColors: PreparedDocumentSettings.isUniformRedVertexColorIgnoringEnabled()
        )
    }
}

enum PreparedDocumentSettings {
    static let suiteName = "com.hectorlizard.GLTFQuickLook"
    static let unrealMaterialEnrichmentKey = "EnableUnrealMaterialEnrichment"
    static let ignoreUniformRedVertexColorsKey = "IgnoreUniformRedVertexColors"

    static func isUnrealMaterialEnrichmentEnabled() -> Bool {
        defaults.bool(forKey: unrealMaterialEnrichmentKey)
    }

    static func setUnrealMaterialEnrichmentEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: unrealMaterialEnrichmentKey)
    }

    static func isUniformRedVertexColorIgnoringEnabled() -> Bool {
        if defaults.object(forKey: ignoreUniformRedVertexColorsKey) == nil {
            return true
        }
        return defaults.bool(forKey: ignoreUniformRedVertexColorsKey)
    }

    static func setUniformRedVertexColorIgnoringEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: ignoreUniformRedVertexColorsKey)
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }
}
