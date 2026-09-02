import Foundation

struct PreparedDocumentCacheMetadata: Codable, Equatable {
    let version: Int
    let preparationFlavor: String
    let sourceSHA256: String
    let resources: [PreparedDocumentResourceFingerprint]
}

struct PreparedDocumentResourceFingerprint: Codable, Equatable {
    let path: String
    let fileSize: Int64
    let modificationIntervalSince1970: TimeInterval
}

enum PreparedDocumentAttributeStore {
    static let payloadAttributeName = PreparedDocumentFileCache.attributeName
    static let metadataAttributeName = "com.hectorlizard.GLTFQuickLook.PreparedGLTFMetadata"

    static func metadata(for url: URL) -> PreparedDocumentCacheMetadata? {
        guard let data = data(for: metadataAttributeName, at: url) else {
            return nil
        }
        return try? JSONDecoder().decode(PreparedDocumentCacheMetadata.self, from: data)
    }

    static func write(preparedData: Data, metadata: PreparedDocumentCacheMetadata, to url: URL) throws {
        let metadataData = try JSONEncoder().encode(metadata)
        try set(data: preparedData, for: payloadAttributeName, at: url)
        try set(data: metadataData, for: metadataAttributeName, at: url)
    }

    private static func data(for attributeName: String, at url: URL) -> Data? {
        let path = url.path
        let size = getxattr(path, attributeName, nil, 0, 0, 0)
        guard size >= 0 else {
            return nil
        }

        let expectedCount = Int(size)
        var data = Data(count: expectedCount)
        let readCount = data.withUnsafeMutableBytes { bytes -> ssize_t in
            getxattr(path, attributeName, bytes.baseAddress, expectedCount, 0, 0)
        }

        guard readCount >= 0 else {
            return nil
        }

        if readCount != expectedCount {
            data.removeSubrange(Int(readCount)..<expectedCount)
        }
        return data
    }

    private static func set(data: Data, for attributeName: String, at url: URL) throws {
        let path = url.path
        let result = data.withUnsafeBytes { bytes in
            setxattr(path, attributeName, bytes.baseAddress, data.count, 0, 0)
        }

        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
