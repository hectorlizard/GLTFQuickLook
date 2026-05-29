import CryptoKit
import Foundation
import UniformTypeIdentifiers

struct PreparedGLTFDocument {
    let data: Data
    let metadata: PreparedDocumentCacheMetadata
}

enum GLTFDocumentInliner {
    static func prepareDocument(at url: URL) throws -> PreparedGLTFDocument {
        let documentData = try Data(contentsOf: url)
        var rootObject = try parsedRootObject(from: documentData)
        let baseDirectoryURL = url.deletingLastPathComponent()
        let resourceURLs = localResourceURLs(in: rootObject, relativeTo: baseDirectoryURL)

        if var buffers = rootObject["buffers"] as? [[String: Any]] {
            for index in buffers.indices {
                guard let uri = buffers[index]["uri"] as? String else {
                    continue
                }
                guard let resourceURL = localResourceURL(for: uri, relativeTo: baseDirectoryURL) else {
                    continue
                }
                buffers[index]["uri"] = try dataURI(for: resourceURL, fallbackMimeType: "application/octet-stream")
            }
            rootObject["buffers"] = buffers
        }

        if var images = rootObject["images"] as? [[String: Any]] {
            for index in images.indices {
                guard let uri = images[index]["uri"] as? String else {
                    continue
                }
                guard let resourceURL = localResourceURL(for: uri, relativeTo: baseDirectoryURL) else {
                    continue
                }
                images[index]["uri"] = try dataURI(for: resourceURL, fallbackMimeType: inferredMimeType(for: resourceURL))
            }
            rootObject["images"] = images
        }

        let preparedData = try JSONSerialization.data(withJSONObject: rootObject, options: [])
        let metadata = try makeMetadata(for: documentData, resourceURLs: resourceURLs)
        return PreparedGLTFDocument(data: preparedData, metadata: metadata)
    }

    static func metadata(for url: URL) throws -> PreparedDocumentCacheMetadata {
        let documentData = try Data(contentsOf: url)
        let rootObject = try parsedRootObject(from: documentData)
        let resourceURLs = localResourceURLs(in: rootObject, relativeTo: url.deletingLastPathComponent())
        return try makeMetadata(for: documentData, resourceURLs: resourceURLs)
    }

    private static func parsedRootObject(from documentData: Data) throws -> [String: Any] {
        guard let rootObject = try JSONSerialization.jsonObject(with: documentData) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return rootObject
    }

    private static func localResourceURLs(in rootObject: [String: Any], relativeTo baseDirectoryURL: URL) -> [URL] {
        let bufferURIs = ((rootObject["buffers"] as? [[String: Any]]) ?? []).compactMap { $0["uri"] as? String }
        let imageURIs = ((rootObject["images"] as? [[String: Any]]) ?? []).compactMap { $0["uri"] as? String }

        var seenPaths: Set<String> = []
        var urls: [URL] = []
        for uri in bufferURIs + imageURIs {
            guard let resourceURL = localResourceURL(for: uri, relativeTo: baseDirectoryURL) else {
                continue
            }
            let standardizedPath = resourceURL.standardizedFileURL.path
            guard seenPaths.insert(standardizedPath).inserted else {
                continue
            }
            urls.append(resourceURL)
        }
        return urls
    }

    private static func localResourceURL(for uri: String, relativeTo baseDirectoryURL: URL) -> URL? {
        guard !uri.isEmpty, !uri.hasPrefix("data:") else {
            return nil
        }

        if let parsedURL = URL(string: uri), let scheme = parsedURL.scheme, !scheme.isEmpty {
            guard scheme == "file" else {
                return nil
            }
            return parsedURL.standardizedFileURL
        }

        let path = uri.removingPercentEncoding ?? uri
        return URL(fileURLWithPath: path, relativeTo: baseDirectoryURL).standardizedFileURL
    }

    private static func dataURI(for fileURL: URL, fallbackMimeType: String) throws -> String {
        let data = try Data(contentsOf: fileURL)
        let mimeType = inferredMimeType(for: fileURL, fallback: fallbackMimeType)
        return "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    private static func makeMetadata(for documentData: Data, resourceURLs: [URL]) throws -> PreparedDocumentCacheMetadata {
        let sourceDigest = SHA256.hash(data: documentData).map { String(format: "%02x", $0) }.joined()
        let resources = try resourceURLs.map { resourceURL in
            let values = try resourceURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return PreparedDocumentResourceFingerprint(
                path: resourceURL.standardizedFileURL.path,
                fileSize: Int64(values.fileSize ?? 0),
                modificationIntervalSince1970: values.contentModificationDate?.timeIntervalSince1970 ?? 0
            )
        }

        return PreparedDocumentCacheMetadata(version: 1, sourceSHA256: sourceDigest, resources: resources)
    }

    private static func inferredMimeType(for fileURL: URL, fallback: String = "application/octet-stream") -> String {
        if let type = UTType(filenameExtension: fileURL.pathExtension),
           let preferredMIMEType = type.preferredMIMEType {
            return preferredMIMEType
        }
        return fallback
    }
}
