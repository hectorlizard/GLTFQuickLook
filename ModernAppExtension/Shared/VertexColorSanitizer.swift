import Foundation

enum VertexColorSanitizer {
    static func removeUniformRedVertexColors(
        from rootObject: inout [String: Any],
        relativeTo baseDirectoryURL: URL
    ) {
        guard var meshes = rootObject["meshes"] as? [[String: Any]],
              let accessors = rootObject["accessors"] as? [[String: Any]],
              let bufferViews = rootObject["bufferViews"] as? [[String: Any]],
              let buffers = rootObject["buffers"] as? [[String: Any]] else {
            return
        }

        let sampler = AccessorColorSampler(
            accessors: accessors,
            bufferViews: bufferViews,
            buffers: buffers,
            baseDirectoryURL: baseDirectoryURL
        )

        var meshChanged = false

        for meshIndex in meshes.indices {
            guard var primitives = meshes[meshIndex]["primitives"] as? [[String: Any]] else {
                continue
            }

            var primitiveChanged = false

            for primitiveIndex in primitives.indices {
                guard var attributes = primitives[primitiveIndex]["attributes"] as? [String: Any],
                      let colorAccessorIndex = attributes["COLOR_0"] as? Int else {
                    continue
                }

                guard sampler.isUniformPrimaryRedColor(accessorIndex: colorAccessorIndex) else {
                    continue
                }

                attributes.removeValue(forKey: "COLOR_0")
                primitives[primitiveIndex]["attributes"] = attributes
                primitiveChanged = true
            }

            if primitiveChanged {
                meshes[meshIndex]["primitives"] = primitives
                meshChanged = true
            }
        }

        if meshChanged {
            rootObject["meshes"] = meshes
        }
    }
}

private struct AccessorColorSampler {
    let accessors: [[String: Any]]
    let bufferViews: [[String: Any]]
    let buffers: [[String: Any]]
    let baseDirectoryURL: URL

    func isUniformPrimaryRedColor(accessorIndex: Int) -> Bool {
        guard accessorIndex >= 0, accessorIndex < accessors.count else {
            return false
        }

        let accessor = accessors[accessorIndex]
        guard let accessorBufferViewIndex = accessor["bufferView"] as? Int,
              accessorBufferViewIndex >= 0,
              accessorBufferViewIndex < bufferViews.count else {
            return false
        }

        let componentType = accessor["componentType"] as? Int ?? -1
        let accessorType = accessor["type"] as? String ?? ""
        let componentCount = vectorComponentCount(for: accessorType)
        guard componentCount == 3 || componentCount == 4 else {
            return false
        }

        guard let format = componentFormat(for: componentType) else {
            return false
        }

        let bufferView = bufferViews[accessorBufferViewIndex]
        guard let bufferIndex = bufferView["buffer"] as? Int,
              bufferIndex >= 0,
              bufferIndex < buffers.count else {
            return false
        }

        let buffer = buffers[bufferIndex]
        guard let bufferURI = buffer["uri"] as? String,
              let bufferURL = GLTFDocumentInliner.localResourceURL(for: bufferURI, relativeTo: baseDirectoryURL),
              let rawData = try? Data(contentsOf: bufferURL) else {
            return false
        }

        let count = accessor["count"] as? Int ?? 0
        guard count > 0 else {
            return false
        }

        let normalized = accessor["normalized"] as? Bool ?? false
        let bufferViewOffset = bufferView["byteOffset"] as? Int ?? 0
        let accessorOffset = accessor["byteOffset"] as? Int ?? 0
        let stride = bufferView["byteStride"] as? Int ?? (format.size * componentCount)
        let startOffset = bufferViewOffset + accessorOffset
        let sampleIndices = sampledIndices(count: count, maxSamples: 16)

        var referenceColor: [Double]?

        for sampleIndex in sampleIndices {
            let byteOffset = startOffset + (sampleIndex * stride)
            guard let color = readColor(
                data: rawData,
                byteOffset: byteOffset,
                componentCount: componentCount,
                format: format,
                normalized: normalized
            ) else {
                return false
            }

            if let referenceColor {
                guard approximatelyEqual(color, referenceColor) else {
                    return false
                }
            } else {
                referenceColor = color
            }
        }

        guard let referenceColor else {
            return false
        }

        return isPrimaryRed(referenceColor)
    }

    private func readColor(
        data: Data,
        byteOffset: Int,
        componentCount: Int,
        format: ComponentFormat,
        normalized: Bool
    ) -> [Double]? {
        let totalSize = format.size * componentCount
        guard byteOffset >= 0, byteOffset + totalSize <= data.count else {
            return nil
        }

        return data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress?.advanced(by: byteOffset) else {
                return nil
            }

            switch format {
            case .uint8:
                let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
                return (0..<componentCount).map { normalized ? Double(pointer[$0]) / 255.0 : Double(pointer[$0]) }
            case .uint16:
                let pointer = baseAddress.assumingMemoryBound(to: UInt16.self)
                return (0..<componentCount).map { normalized ? Double(UInt16(littleEndian: pointer[$0])) / 65535.0 : Double(UInt16(littleEndian: pointer[$0])) }
            case .float32:
                let pointer = baseAddress.assumingMemoryBound(to: Float.self)
                return (0..<componentCount).map { Double(Float(bitPattern: UInt32(littleEndian: pointer[$0].bitPattern))) }
            }
        }
    }

    private func isPrimaryRed(_ color: [Double]) -> Bool {
        guard color.count >= 3 else {
            return false
        }

        let red = color[0]
        let green = color[1]
        let blue = color[2]
        let alpha = color.count >= 4 ? color[3] : 1.0

        return red >= 0.99 &&
            green <= 0.01 &&
            blue <= 0.01 &&
            alpha >= 0.99
    }

    private func approximatelyEqual(_ lhs: [Double], _ rhs: [Double], tolerance: Double = 0.002) -> Bool {
        guard lhs.count == rhs.count else {
            return false
        }

        for (leftValue, rightValue) in zip(lhs, rhs) {
            if abs(leftValue - rightValue) > tolerance {
                return false
            }
        }
        return true
    }

    private func sampledIndices(count: Int, maxSamples: Int) -> [Int] {
        guard count > maxSamples else {
            return Array(0..<count)
        }

        let lastIndex = count - 1
        return (0..<maxSamples).map { sample in
            Int((Double(sample) / Double(maxSamples - 1)) * Double(lastIndex))
        }
    }

    private func vectorComponentCount(for type: String) -> Int {
        switch type {
        case "SCALAR":
            return 1
        case "VEC2":
            return 2
        case "VEC3":
            return 3
        case "VEC4":
            return 4
        default:
            return 0
        }
    }

    private func componentFormat(for componentType: Int) -> ComponentFormat? {
        switch componentType {
        case 5121:
            return .uint8
        case 5123:
            return .uint16
        case 5126:
            return .float32
        default:
            return nil
        }
    }
}

private enum ComponentFormat {
    case uint8
    case uint16
    case float32

    var size: Int {
        switch self {
        case .uint8:
            return 1
        case .uint16:
            return 2
        case .float32:
            return 4
        }
    }
}
