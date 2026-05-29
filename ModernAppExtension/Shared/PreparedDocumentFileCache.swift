import Foundation
import OSLog

enum PreparedDocumentFileCache {
    static let attributeName = "com.hectorlizard.GLTFQuickLook.PreparedGLTF"

    static func preparedDocumentData(for originalURL: URL, logger: Logger) -> Data? {
        guard originalURL.pathExtension.lowercased() == "gltf" else {
            return nil
        }

        let path = originalURL.path
        let name = attributeName

        let size = getxattr(path, name, nil, 0, 0, 0)
        guard size >= 0 else {
            return nil
        }

        let expectedCount = Int(size)
        var data = Data(count: expectedCount)
        let readCount = data.withUnsafeMutableBytes { bytes -> ssize_t in
            getxattr(path, name, bytes.baseAddress, expectedCount, 0, 0)
        }

        guard readCount >= 0 else {
            logger.error("Prepared xattr read failed for \(path, privacy: .public)")
            return nil
        }

        if readCount != expectedCount {
            data.removeSubrange(Int(readCount)..<expectedCount)
        }

        logger.debug("Using prepared xattr cache on \(originalURL.lastPathComponent, privacy: .public) bytes=\(data.count, privacy: .public)")
        return data
    }
}
