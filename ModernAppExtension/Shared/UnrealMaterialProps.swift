import Foundation

enum UnrealBlendMode {
    case opaque
    case masked
    case translucent
}

enum UnrealResolvedTextureSource: Hashable {
    case file(URL)
    case solidGray(UInt8)

    var fileURL: URL? {
        switch self {
        case let .file(url):
            return url
        case .solidGray:
            return nil
        }
    }
}

struct UnrealTextureReference: Hashable {
    let parameterName: String
    let unrealAssetPath: String
    let source: UnrealResolvedTextureSource?
}

struct UnrealMaterialProps {
    let propsFileURL: URL
    let parentMaterialPath: String?
    let textureParameters: [String: UnrealTextureReference]
    let vectorParameters: [String: [Double]]
    let blendMode: UnrealBlendMode?
    let twoSided: Bool?
    let opacityMaskClipValue: Double?

    func textureReference(
        exactNames: [String],
        containsKeywords: [String] = []
    ) -> UnrealTextureReference? {
        let exactLookup = Dictionary(
            uniqueKeysWithValues: textureParameters.map { key, value in
                (key.lowercased(), value)
            }
        )

        for exactName in exactNames {
            if let match = exactLookup[exactName.lowercased()] {
                return match
            }
        }

        guard !containsKeywords.isEmpty else {
            return nil
        }

        let candidates = textureParameters
            .sorted { $0.key < $1.key }
            .map(\.value)

        for keyword in containsKeywords {
            if let match = candidates.first(where: { $0.parameterName.lowercased().contains(keyword.lowercased()) }) {
                return match
            }
        }

        return nil
    }

    func vectorParameter(named parameterName: String) -> [Double]? {
        vectorParameters.first { $0.key.caseInsensitiveCompare(parameterName) == .orderedSame }?.value
    }
}

struct UnrealMaterialLibrary {
    private static let textureExtensions = ["png", "jpg", "jpeg", "webp", "tga", "bmp", "gif", "dds", "ktx", "ktx2", "basis"]

    private let exportRootURL: URL?
    private let materialsRootURL: URL?
    private let propsURLsByMaterialName: [String: URL]
    private var parsedPropsCache: [String: UnrealMaterialProps] = [:]

    init(documentURL: URL) {
        exportRootURL = Self.findAncestor(named: "Modèles exportés", from: documentURL)

        if let contentRootURL = Self.findAncestor(named: "Content", from: documentURL) {
            let materialsRootCandidate = contentRootURL.appendingPathComponent("Materials", isDirectory: true)
            if FileManager.default.fileExists(atPath: materialsRootCandidate.path) {
                materialsRootURL = materialsRootCandidate
            } else {
                materialsRootURL = nil
            }
        } else {
            materialsRootURL = nil
        }

        propsURLsByMaterialName = Self.indexMaterialProps(in: materialsRootURL)
    }

    mutating func props(forMaterialNamed materialName: String) -> UnrealMaterialProps? {
        if let cached = parsedPropsCache[materialName] {
            return cached
        }

        guard let propsFileURL = propsURLsByMaterialName[materialName] else {
            return nil
        }

        guard let parsedProps = parseMaterialProps(at: propsFileURL) else {
            return nil
        }

        parsedPropsCache[materialName] = parsedProps
        return parsedProps
    }

    private static func findAncestor(named ancestorName: String, from url: URL) -> URL? {
        var currentURL = url.deletingLastPathComponent()
        while currentURL.path != "/" {
            if currentURL.lastPathComponent == ancestorName {
                return currentURL
            }
            currentURL.deleteLastPathComponent()
        }
        return nil
    }

    private static func indexMaterialProps(in materialsRootURL: URL?) -> [String: URL] {
        guard let materialsRootURL else {
            return [:]
        }

        var result: [String: URL] = [:]
        guard let enumerator = FileManager.default.enumerator(
            at: materialsRootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return [:]
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent.hasSuffix(".props.txt") else {
                continue
            }

            let materialName = String(fileURL.lastPathComponent.dropLast(".props.txt".count))
            result[materialName] = fileURL
        }

        return result
    }

    private mutating func parseMaterialProps(at propsFileURL: URL) -> UnrealMaterialProps? {
        guard let content = try? String(contentsOf: propsFileURL, encoding: .utf8) else {
            return nil
        }

        var parentMaterialPath: String?
        var currentParameterName: String?
        var textureParameters: [String: UnrealTextureReference] = [:]
        var vectorParameters: [String: [Double]] = [:]
        var blendMode: UnrealBlendMode?
        var twoSided: Bool?
        var opacityMaskClipValue: Double?

        for line in content.components(separatedBy: .newlines) {
            if parentMaterialPath == nil,
               let match = firstMatch(in: line, pattern: #"Parent = [^']*'([^']+)'"#) {
                parentMaterialPath = match
                continue
            }

            if let match = firstMatch(in: line, pattern: #"ParameterInfo = \{ Name=(.+) \}"#) {
                currentParameterName = match
                continue
            }

            if let parameterName = currentParameterName,
               let match = firstMatch(in: line, pattern: #"ParameterValue = Texture2D'([^']+)'"#) {
                textureParameters[parameterName] = UnrealTextureReference(
                    parameterName: parameterName,
                    unrealAssetPath: match,
                    source: resolveTextureSource(forUnrealAssetPath: match)
                )
                continue
            }

            if let parameterName = currentParameterName,
               let values = parseVectorParameterValue(from: line) {
                vectorParameters[parameterName] = values
                continue
            }

            if line.contains("BlendMode = BLEND_Masked") {
                blendMode = .masked
                continue
            }

            if line.contains("BlendMode = BLEND_Translucent") {
                blendMode = .translucent
                continue
            }

            if line.contains("BlendMode = BLEND_Opaque") {
                blendMode = .opaque
                continue
            }

            if let match = firstMatch(in: line, pattern: #"TwoSided = (true|false)"#) {
                twoSided = NSString(string: match).boolValue
                continue
            }

            if let match = firstMatch(in: line, pattern: #"OpacityMaskClipValue = ([0-9.]+)"#),
               let parsedValue = Double(match) {
                opacityMaskClipValue = parsedValue
            }
        }

        return UnrealMaterialProps(
            propsFileURL: propsFileURL,
            parentMaterialPath: parentMaterialPath,
            textureParameters: textureParameters,
            vectorParameters: vectorParameters,
            blendMode: blendMode,
            twoSided: twoSided,
            opacityMaskClipValue: opacityMaskClipValue
        )
    }

    private func resolveTextureSource(forUnrealAssetPath unrealAssetPath: String) -> UnrealResolvedTextureSource? {
        if let fileURL = resolveTextureFileURL(forUnrealAssetPath: unrealAssetPath) {
            return .file(fileURL)
        }

        return resolveSolidTexture(forUnrealAssetPath: unrealAssetPath)
    }

    private func resolveTextureFileURL(forUnrealAssetPath unrealAssetPath: String) -> URL? {
        guard let exportRootURL else {
            return nil
        }

        let stemPath = NSString(string: unrealAssetPath).deletingPathExtension
        let relativePath = stemPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        for textureExtension in Self.textureExtensions {
            let candidateURL = exportRootURL
                .appendingPathComponent(relativePath)
                .appendingPathExtension(textureExtension)
            if FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL.standardizedFileURL
            }
        }

        return nil
    }

    private func resolveSolidTexture(forUnrealAssetPath unrealAssetPath: String) -> UnrealResolvedTextureSource? {
        let textureName = URL(fileURLWithPath: NSString(string: unrealAssetPath).deletingPathExtension).lastPathComponent
        guard let match = firstMatch(in: textureName, pattern: #"T_(\d+)_(\d+)_(\d+)$"#) else {
            return nil
        }

        let channels = match.split(separator: "_").compactMap { UInt8($0) }
        guard let firstChannel = channels.first else {
            return nil
        }

        return .solidGray(firstChannel)
    }

    private func parseVectorParameterValue(from line: String) -> [Double]? {
        guard let match = firstMatch(in: line, pattern: #"\{ R=([^,]+), G=([^,]+), B=([^,]+), A=([^}]+) \}"#) else {
            return nil
        }

        return match
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regularExpression = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regularExpression.firstMatch(in: text, range: range) else {
            return nil
        }

        if match.numberOfRanges == 2,
           let captureRange = Range(match.range(at: 1), in: text) {
            return String(text[captureRange])
        }

        guard match.numberOfRanges > 1 else {
            return nil
        }

        let captures = (1..<match.numberOfRanges).compactMap { captureIndex -> String? in
            guard let captureRange = Range(match.range(at: captureIndex), in: text) else {
                return nil
            }
            return String(text[captureRange])
        }
        return captures.joined(separator: ",")
    }
}
