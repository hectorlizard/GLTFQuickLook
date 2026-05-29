import Foundation
import OSLog

struct PreparationRunSummary {
    var foldersScanned = 0
    var documentsSeen = 0
    var documentsPrepared = 0
    var documentsSkipped = 0
    var failures: [String] = []
}

enum PreparedDocumentPreparer {
    static func prepare(urls: [URL], logger: Logger? = nil) -> PreparationRunSummary {
        var summary = PreparationRunSummary()
        let fileManager = FileManager.default

        for url in urls {
            if url.hasDirectoryPath {
                prepareDirectory(url, fileManager: fileManager, logger: logger, summary: &summary)
            } else if url.pathExtension.lowercased() == "gltf" {
                prepareDocument(url, logger: logger, summary: &summary)
            }
        }

        return summary
    }

    private static func prepareDirectory(
        _ directoryURL: URL,
        fileManager: FileManager,
        logger: Logger?,
        summary: inout PreparationRunSummary
    ) {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            summary.failures.append("Dossier introuvable: \(directoryURL.path)")
            return
        }

        summary.foldersScanned += 1

        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            summary.failures.append("Enumeration impossible: \(directoryURL.path)")
            return
        }

        for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "gltf" {
            prepareDocument(fileURL, logger: logger, summary: &summary)
        }
    }

    private static func prepareDocument(_ fileURL: URL, logger: Logger?, summary: inout PreparationRunSummary) {
        summary.documentsSeen += 1

        do {
            let currentMetadata = try GLTFDocumentInliner.metadata(for: fileURL)
            if PreparedDocumentAttributeStore.metadata(for: fileURL) == currentMetadata {
                summary.documentsSkipped += 1
                return
            }

            let preparedDocument = try GLTFDocumentInliner.prepareDocument(at: fileURL)
            try PreparedDocumentAttributeStore.write(
                preparedData: preparedDocument.data,
                metadata: preparedDocument.metadata,
                to: fileURL
            )
            summary.documentsPrepared += 1
            logger?.notice("Prepared cache for \(fileURL.path, privacy: .public)")
            print("Prepared \(fileURL.path)")
        } catch {
            summary.failures.append("\(fileURL.lastPathComponent): \(error.localizedDescription)")
            logger?.error("Preparation failed for \(fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            print("Failed \(fileURL.path): \(error.localizedDescription)")
        }
    }
}
