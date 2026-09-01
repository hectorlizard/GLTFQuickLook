import Foundation

enum SkinWeightNormalizer {
    // SceneKit requires floating-point skin weights even though glTF also permits normalized integers.
    private static let floatComponentType = 5_126
    private static let unsignedByteComponentType = 5_121
    private static let unsignedShortComponentType = 5_123

    static func requiresNormalization(_ rootObject: [String: Any]) -> Bool {
        guard let accessors = rootObject["accessors"] as? [[String: Any]] else {
            return false
        }
        return weightAccessorIndices(in: rootObject).contains { index in
            guard accessors.indices.contains(index) else { return false }
            let accessor = accessors[index]
            return accessor["normalized"] as? Bool == true
                && supportedIntegerComponentTypes.contains(accessor["componentType"] as? Int ?? 0)
        }
    }

    static func normalize(
        _ rootObject: inout [String: Any],
        relativeTo baseDirectoryURL: URL
    ) throws -> Bool {
        guard requiresNormalization(rootObject),
              var accessors = rootObject["accessors"] as? [[String: Any]],
              var bufferViews = rootObject["bufferViews"] as? [[String: Any]],
              var buffers = rootObject["buffers"] as? [[String: Any]] else {
            return false
        }

        var normalizedData = Data()
        var normalizedAccessors: [(index: Int, byteOffset: Int, byteLength: Int)] = []

        for accessorIndex in weightAccessorIndices(in: rootObject).sorted() {
            guard accessors.indices.contains(accessorIndex) else { continue }
            let accessor = accessors[accessorIndex]
            guard accessor["normalized"] as? Bool == true,
                  let componentType = accessor["componentType"] as? Int,
                  supportedIntegerComponentTypes.contains(componentType),
                  let bufferViewIndex = accessor["bufferView"] as? Int,
                  bufferViews.indices.contains(bufferViewIndex) else {
                continue
            }

            let floatData = try normalizedFloatData(
                for: accessor,
                bufferView: bufferViews[bufferViewIndex],
                buffers: buffers,
                relativeTo: baseDirectoryURL
            )
            while normalizedData.count % MemoryLayout<Float>.alignment != 0 {
                normalizedData.append(0)
            }
            let byteOffset = normalizedData.count
            normalizedData.append(floatData)
            normalizedAccessors.append((accessorIndex, byteOffset, floatData.count))
        }

        guard !normalizedAccessors.isEmpty else {
            return false
        }

        let bufferIndex = buffers.count
        buffers.append([
            "byteLength": normalizedData.count,
            "uri": "data:application/octet-stream;base64,\(normalizedData.base64EncodedString())"
        ])

        for normalizedAccessor in normalizedAccessors {
            let bufferViewIndex = bufferViews.count
            bufferViews.append([
                "buffer": bufferIndex,
                "byteOffset": normalizedAccessor.byteOffset,
                "byteLength": normalizedAccessor.byteLength
            ])
            accessors[normalizedAccessor.index]["bufferView"] = bufferViewIndex
            accessors[normalizedAccessor.index]["byteOffset"] = 0
            accessors[normalizedAccessor.index]["componentType"] = floatComponentType
            accessors[normalizedAccessor.index].removeValue(forKey: "normalized")
        }

        rootObject["accessors"] = accessors
        rootObject["bufferViews"] = bufferViews
        rootObject["buffers"] = buffers
        return true
    }

    private static var supportedIntegerComponentTypes: Set<Int> {
        [unsignedByteComponentType, unsignedShortComponentType]
    }

    private static func weightAccessorIndices(in rootObject: [String: Any]) -> Set<Int> {
        var indices: Set<Int> = []
        for mesh in (rootObject["meshes"] as? [[String: Any]]) ?? [] {
            for primitive in (mesh["primitives"] as? [[String: Any]]) ?? [] {
                for (semantic, index) in (primitive["attributes"] as? [String: Int]) ?? [:]
                    where semantic.hasPrefix("WEIGHTS_") {
                    indices.insert(index)
                }
            }
        }
        return indices
    }

    private static func normalizedFloatData(
        for accessor: [String: Any],
        bufferView: [String: Any],
        buffers: [[String: Any]],
        relativeTo baseDirectoryURL: URL
    ) throws -> Data {
        guard let componentType = accessor["componentType"] as? Int,
              let componentCount = componentCount(for: accessor["type"] as? String),
              let vectorCount = accessor["count"] as? Int,
              let bufferIndex = bufferView["buffer"] as? Int,
              buffers.indices.contains(bufferIndex),
              let uri = buffers[bufferIndex]["uri"] as? String else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let bytesPerComponent = componentType == unsignedByteComponentType ? 1 : 2
        let packedStride = bytesPerComponent * componentCount
        let sourceStride = bufferView["byteStride"] as? Int ?? packedStride
        let sourceOffset = (bufferView["byteOffset"] as? Int ?? 0)
            + (accessor["byteOffset"] as? Int ?? 0)
        let sourceLength = sourceStride * max(0, vectorCount - 1) + packedStride
        let sourceData = try readBufferRange(
            uri: uri,
            offset: sourceOffset,
            length: sourceLength,
            relativeTo: baseDirectoryURL
        )

        var floats: [Float] = []
        floats.reserveCapacity(vectorCount * componentCount)
        for vectorIndex in 0..<vectorCount {
            let vectorOffset = vectorIndex * sourceStride
            for componentIndex in 0..<componentCount {
                let componentOffset = vectorOffset + componentIndex * bytesPerComponent
                if componentType == unsignedByteComponentType {
                    floats.append(Float(sourceData[componentOffset]) / Float(UInt8.max))
                } else {
                    let value = UInt16(sourceData[componentOffset])
                        | UInt16(sourceData[componentOffset + 1]) << 8
                    floats.append(Float(value) / Float(UInt16.max))
                }
            }
        }
        return floats.withUnsafeBytes { Data($0) }
    }

    private static func readBufferRange(
        uri: String,
        offset: Int,
        length: Int,
        relativeTo baseDirectoryURL: URL
    ) throws -> Data {
        if uri.hasPrefix("data:"),
           let commaIndex = uri.firstIndex(of: ","),
           let data = Data(base64Encoded: String(uri[uri.index(after: commaIndex)...])) {
            guard offset >= 0, length >= 0, offset + length <= data.count else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return data.subdata(in: offset..<(offset + length))
        }

        guard let resourceURL = GLTFDocumentInliner.localResourceURL(
            for: uri,
            relativeTo: baseDirectoryURL
        ) else {
            throw CocoaError(.fileReadNoPermission)
        }
        let handle = try FileHandle(forReadingFrom: resourceURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        let data = try handle.read(upToCount: length) ?? Data()
        guard data.count == length else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return data
    }

    private static func componentCount(for accessorType: String?) -> Int? {
        switch accessorType {
        case "SCALAR": return 1
        case "VEC2": return 2
        case "VEC3": return 3
        case "VEC4": return 4
        default: return nil
        }
    }
}
