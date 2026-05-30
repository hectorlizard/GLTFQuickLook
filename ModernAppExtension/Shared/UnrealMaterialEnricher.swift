import CoreGraphics
import Foundation
import ImageIO

struct UnrealMaterialEnrichmentResult {
    let additionalResourceURLs: [URL]
}

enum UnrealMaterialEnricher {
    static func enrich(rootObject: inout [String: Any], documentURL: URL) -> UnrealMaterialEnrichmentResult {
        guard var materials = rootObject["materials"] as? [[String: Any]], !materials.isEmpty else {
            return UnrealMaterialEnrichmentResult(additionalResourceURLs: [])
        }

        var materialLibrary = UnrealMaterialLibrary(documentURL: documentURL)
        var dependencyPaths: Set<String> = []
        var images = rootObject["images"] as? [[String: Any]] ?? []
        var textures = rootObject["textures"] as? [[String: Any]] ?? []
        var imageIndicesByKey: [String: Int] = [:]
        var textureIndicesByKey: [String: Int] = [:]

        for (index, image) in images.enumerated() {
            if let uri = image["uri"] as? String {
                imageIndicesByKey["uri:\(uri)"] = index
            }
        }

        for (index, texture) in textures.enumerated() {
            if let source = texture["source"] as? Int {
                textureIndicesByKey["source:\(source)"] = index
            }
        }

        for materialIndex in materials.indices {
            guard let materialName = materials[materialIndex]["name"] as? String,
                  let props = materialLibrary.props(forMaterialNamed: materialName) else {
                continue
            }

            dependencyPaths.insert(props.propsFileURL.standardizedFileURL.path)

            var material = materials[materialIndex]
            var pbr = material["pbrMetallicRoughness"] as? [String: Any] ?? [:]

            if let baseColorTextureIndex = textureIndex(
                for: props.textureReference(exactNames: ["Color", "Diffuse Map"], containsKeywords: ["diffuse map", "albedo map"]),
                images: &images,
                textures: &textures,
                imageIndicesByKey: &imageIndicesByKey,
                textureIndicesByKey: &textureIndicesByKey,
                dependencyPaths: &dependencyPaths
            ) {
                pbr["baseColorTexture"] = ["index": baseColorTextureIndex]
                pbr["baseColorFactor"] = [1.0, 1.0, 1.0, 1.0]
            }

            if let normalTextureIndex = textureIndex(
                for: props.textureReference(exactNames: ["Normal", "Normal Map"], containsKeywords: ["normal map"]),
                images: &images,
                textures: &textures,
                imageIndicesByKey: &imageIndicesByKey,
                textureIndicesByKey: &textureIndicesByKey,
                dependencyPaths: &dependencyPaths
            ) {
                material["normalTexture"] = ["index": normalTextureIndex]
            }

            if let emissiveTextureIndex = textureIndex(
                for: props.textureReference(exactNames: ["Emissive", "Emissive Map"], containsKeywords: ["emissive map"]),
                images: &images,
                textures: &textures,
                imageIndicesByKey: &imageIndicesByKey,
                textureIndicesByKey: &textureIndicesByKey,
                dependencyPaths: &dependencyPaths
            ) {
                material["emissiveTexture"] = ["index": emissiveTextureIndex]
                material["emissiveFactor"] = props.vectorParameter(named: "Emissive Color")?.prefix(3).map { $0 } ?? [1.0, 1.0, 1.0]
            }

            if let packedTexture = makeMetallicRoughnessTexture(from: props, dependencyPaths: &dependencyPaths),
               let metallicRoughnessTextureIndex = textureIndex(
                for: packedTexture,
                images: &images,
                textures: &textures,
                imageIndicesByKey: &imageIndicesByKey,
                textureIndicesByKey: &textureIndicesByKey
               ) {
                pbr["metallicRoughnessTexture"] = ["index": metallicRoughnessTextureIndex]
                pbr["metallicFactor"] = 1.0
                pbr["roughnessFactor"] = 1.0
            }

            if let armeTextureIndex = textureIndex(
                for: props.textureReference(exactNames: ["ARME Map"], containsKeywords: ["arme map"]),
                images: &images,
                textures: &textures,
                imageIndicesByKey: &imageIndicesByKey,
                textureIndicesByKey: &textureIndicesByKey,
                dependencyPaths: &dependencyPaths
            ) {
                material["occlusionTexture"] = ["index": armeTextureIndex]
            }

            switch props.blendMode {
            case .masked:
                material["alphaMode"] = "MASK"
                if let opacityMaskClipValue = props.opacityMaskClipValue {
                    material["alphaCutoff"] = opacityMaskClipValue
                }
            case .translucent:
                material["alphaMode"] = "BLEND"
            case .opaque, .none:
                break
            }

            if let twoSided = props.twoSided {
                material["doubleSided"] = twoSided
            }

            material["pbrMetallicRoughness"] = pbr
            materials[materialIndex] = material
        }

        rootObject["materials"] = materials
        if images.isEmpty {
            rootObject.removeValue(forKey: "images")
        } else {
            rootObject["images"] = images
        }
        if textures.isEmpty {
            rootObject.removeValue(forKey: "textures")
        } else {
            rootObject["textures"] = textures
        }

        let dependencyURLs = dependencyPaths
            .sorted()
            .map { URL(fileURLWithPath: $0) }
        return UnrealMaterialEnrichmentResult(additionalResourceURLs: dependencyURLs)
    }

    private static func textureIndex(
        for textureReference: UnrealTextureReference?,
        images: inout [[String: Any]],
        textures: inout [[String: Any]],
        imageIndicesByKey: inout [String: Int],
        textureIndicesByKey: inout [String: Int],
        dependencyPaths: inout Set<String>
    ) -> Int? {
        guard let textureReference else {
            return nil
        }

        if let fileURL = textureReference.source?.fileURL {
            dependencyPaths.insert(fileURL.standardizedFileURL.path)
        }

        return textureIndex(
            for: MaterialTextureSource.textureReference(textureReference),
            images: &images,
            textures: &textures,
            imageIndicesByKey: &imageIndicesByKey,
            textureIndicesByKey: &textureIndicesByKey
        )
    }

    private static func textureIndex(
        for textureSource: MaterialTextureSource,
        images: inout [[String: Any]],
        textures: inout [[String: Any]],
        imageIndicesByKey: inout [String: Int],
        textureIndicesByKey: inout [String: Int]
    ) -> Int? {
        let imageKey = textureSource.cacheKey
        let imageIndex: Int

        if let cachedImageIndex = imageIndicesByKey[imageKey] {
            imageIndex = cachedImageIndex
        } else {
            let imageURI: String
            switch textureSource {
            case let .textureReference(textureReference):
                guard let source = textureReference.source else {
                    return nil
                }
                switch source {
                case let .file(fileURL):
                    imageURI = fileURL.standardizedFileURL.absoluteString
                case let .solidGray(grayValue):
                    guard let generatedImageURI = makeSolidGrayDataURI(grayValue: grayValue) else {
                        return nil
                    }
                    imageURI = generatedImageURI
                }
            case let .dataURI(dataURI, _):
                imageURI = dataURI
            }

            images.append(["uri": imageURI])
            imageIndex = images.count - 1
            imageIndicesByKey[imageKey] = imageIndex
        }

        let textureKey = "source:\(imageIndex)"
        if let cachedTextureIndex = textureIndicesByKey[textureKey] {
            return cachedTextureIndex
        }

        textures.append(["source": imageIndex])
        let textureIndex = textures.count - 1
        textureIndicesByKey[textureKey] = textureIndex
        return textureIndex
    }

    private static func makeMetallicRoughnessTexture(
        from props: UnrealMaterialProps,
        dependencyPaths: inout Set<String>
    ) -> MaterialTextureSource? {
        if let armeTexture = props.textureReference(exactNames: ["ARME Map"], containsKeywords: ["arme map"]) {
            if let fileURL = armeTexture.source?.fileURL {
                dependencyPaths.insert(fileURL.standardizedFileURL.path)
            }
            return .textureReference(armeTexture)
        }

        let roughnessTexture = props.textureReference(
            exactNames: ["Roughness", "Roughness Map"],
            containsKeywords: ["roughness map"]
        )
        let metallicTexture = props.textureReference(
            exactNames: ["Metal", "Metal Map", "Metalness Map"],
            containsKeywords: ["metal map", "metalness map"]
        )

        guard roughnessTexture != nil || metallicTexture != nil else {
            return nil
        }

        if let fileURL = roughnessTexture?.source?.fileURL {
            dependencyPaths.insert(fileURL.standardizedFileURL.path)
        }
        if let fileURL = metallicTexture?.source?.fileURL {
            dependencyPaths.insert(fileURL.standardizedFileURL.path)
        }

        guard let packedDataURI = try? makePackedMetallicRoughnessDataURI(
            roughnessSource: roughnessTexture?.source,
            metallicSource: metallicTexture?.source
        ) else {
            return nil
        }

        let cacheKey = [
            roughnessTexture?.unrealAssetPath ?? "roughness:none",
            metallicTexture?.unrealAssetPath ?? "metal:none"
        ].joined(separator: "|")
        return .dataURI(packedDataURI, cacheKey: "packed:\(cacheKey)")
    }

    private static func makeSolidGrayDataURI(grayValue: UInt8) -> String? {
        guard let pngData = try? makePackedTexturePNGData(
            width: 1,
            height: 1,
            greenChannel: [grayValue],
            blueChannel: [grayValue]
        ) else {
            return nil
        }
        return "data:image/png;base64,\(pngData.base64EncodedString())"
    }

    private static func makePackedMetallicRoughnessDataURI(
        roughnessSource: UnrealResolvedTextureSource?,
        metallicSource: UnrealResolvedTextureSource?
    ) throws -> String {
        let targetSize = try preferredTextureSize(roughnessSource: roughnessSource, metallicSource: metallicSource)
        let roughnessChannel = try makeGrayscaleChannel(
            from: roughnessSource,
            width: targetSize.width,
            height: targetSize.height,
            defaultValue: 255
        )
        let metallicChannel = try makeGrayscaleChannel(
            from: metallicSource,
            width: targetSize.width,
            height: targetSize.height,
            defaultValue: 0
        )
        let pngData = try makePackedTexturePNGData(
            width: targetSize.width,
            height: targetSize.height,
            greenChannel: roughnessChannel,
            blueChannel: metallicChannel
        )
        return "data:image/png;base64,\(pngData.base64EncodedString())"
    }

    private static func preferredTextureSize(
        roughnessSource: UnrealResolvedTextureSource?,
        metallicSource: UnrealResolvedTextureSource?
    ) throws -> (width: Int, height: Int) {
        if let roughnessSource, case let .file(fileURL) = roughnessSource,
           let size = try imageSize(for: fileURL) {
            return size
        }
        if let metallicSource, case let .file(fileURL) = metallicSource,
           let size = try imageSize(for: fileURL) {
            return size
        }
        return (1, 1)
    }

    private static func imageSize(for fileURL: URL) throws -> (width: Int, height: Int)? {
        guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return (width, height)
    }

    private static func makeGrayscaleChannel(
        from source: UnrealResolvedTextureSource?,
        width: Int,
        height: Int,
        defaultValue: UInt8
    ) throws -> [UInt8] {
        guard let source else {
            return Array(repeating: defaultValue, count: width * height)
        }

        switch source {
        case let .solidGray(grayValue):
            return Array(repeating: grayValue, count: width * height)
        case let .file(fileURL):
            let rgbaPixels = try loadRGBA8Pixels(from: fileURL, width: width, height: height)
            return stride(from: 0, to: rgbaPixels.count, by: 4).map { rgbaPixels[$0] }
        }
    }

    private static func loadRGBA8Pixels(from fileURL: URL, width: Int, height: Int) throws -> [UInt8] {
        guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CocoaError(.coderInvalidValue)
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    private static func makePackedTexturePNGData(
        width: Int,
        height: Int,
        greenChannel: [UInt8],
        blueChannel: [UInt8]
    ) throws -> Data {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for pixelIndex in 0..<(width * height) {
            let byteOffset = pixelIndex * 4
            pixels[byteOffset] = 0
            pixels[byteOffset + 1] = greenChannel[pixelIndex]
            pixels[byteOffset + 2] = blueChannel[pixelIndex]
            pixels[byteOffset + 3] = 255
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw CocoaError(.coderInvalidValue)
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            throw CocoaError(.coderInvalidValue)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.coderInvalidValue)
        }
        return data as Data
    }
}

private enum MaterialTextureSource {
    case textureReference(UnrealTextureReference)
    case dataURI(String, cacheKey: String)

    var cacheKey: String {
        switch self {
        case let .textureReference(textureReference):
            return "texture:\(textureReference.unrealAssetPath)"
        case let .dataURI(_, cacheKey):
            return cacheKey
        }
    }
}
