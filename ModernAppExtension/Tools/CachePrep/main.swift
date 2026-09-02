import Foundation
import OSLog

let logger = Logger(subsystem: "com.hectorlizard.GLTFQuickLook", category: "CachePrepTool")
let arguments = Array(CommandLine.arguments.dropFirst())

guard !arguments.isEmpty else {
    fputs("Usage: GLTFCachePrep <file-or-folder> [<file-or-folder> ...]\n", stderr)
    exit(64)
}

let urls = arguments.map { URL(fileURLWithPath: $0) }
let summary = PreparedDocumentPreparer.prepare(urls: urls, logger: logger)

print("")
print("Folders scanned: \(summary.foldersScanned)")
print("glTF files seen: \(summary.documentsSeen)")
print("Prepared caches: \(summary.documentsPrepared)")
print("Skipped caches: \(summary.documentsSkipped)")
print("Failures: \(summary.failures.count)")

if !summary.failures.isEmpty {
    print("")
    print("First failure:")
    print(summary.failures[0])
    exit(1)
}
