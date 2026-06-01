import CoreServices
import Foundation

final class FolderEventMonitor {
    typealias ChangeHandler = ([URL]) -> Void

    private static let relevantEventFlags = FSEventStreamEventFlags(
        kFSEventStreamEventFlagItemCreated |
        kFSEventStreamEventFlagItemRemoved |
        kFSEventStreamEventFlagItemRenamed |
        kFSEventStreamEventFlagItemModified |
        kFSEventStreamEventFlagRootChanged
    )

    private static let fileEventFlag = FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile)
    private static let rootChangedFlag = FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged)
    private static let streamFlags = FSEventStreamCreateFlags(
        kFSEventStreamCreateFlagUseCFTypes |
        kFSEventStreamCreateFlagFileEvents |
        kFSEventStreamCreateFlagNoDefer
    )
    private static let watchedExtensions: Set<String> = [
        "gltf", "glb", "bin",
        "png", "jpg", "jpeg", "webp", "bmp", "gif", "tga",
        "ktx", "ktx2", "basis", "dds", "txt"
    ]

    private let rootURLs: [URL]
    private let rootPaths: [String]
    private let onChange: ChangeHandler
    private var stream: FSEventStreamRef?

    init(rootURLs: [URL], onChange: @escaping ChangeHandler) {
        self.rootURLs = rootURLs.map(\.standardizedFileURL)
        self.rootPaths = self.rootURLs.map(\.path)
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        guard stream == nil, !rootPaths.isEmpty else {
            return
        }

        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard let newStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            FolderEventMonitor.eventCallback,
            &context,
            rootPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            FolderEventMonitor.streamFlags
        ) else {
            return
        }

        FSEventStreamSetDispatchQueue(newStream, DispatchQueue.main)
        FSEventStreamStart(newStream)
        stream = newStream
    }

    func stop() {
        guard let stream else {
            return
        }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func handleEvents(paths: [String], flags: [FSEventStreamEventFlags]) {
        var changedTargets: Set<String> = []

        for (path, flag) in zip(paths, flags) {
            guard isRelevantEvent(path: path, flag: flag) else {
                continue
            }

            guard rootPaths.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else {
                continue
            }

            let fileURL = URL(fileURLWithPath: path).standardizedFileURL
            let pathExtension = fileURL.pathExtension.lowercased()
            if pathExtension == "gltf" {
                changedTargets.insert(fileURL.path)
            } else {
                changedTargets.insert(fileURL.deletingLastPathComponent().path)
            }
        }

        guard !changedTargets.isEmpty else {
            return
        }

        let changedURLs = changedTargets
            .sorted()
            .map { path -> URL in
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                return URL(fileURLWithPath: path, isDirectory: isDirectory.boolValue)
            }
        onChange(changedURLs)
    }

    private func isRelevantEvent(path: String, flag: FSEventStreamEventFlags) -> Bool {
        guard (flag & Self.relevantEventFlags) != 0 else {
            return false
        }

        if (flag & Self.rootChangedFlag) != 0 {
            return true
        }

        guard (flag & Self.fileEventFlag) != 0 else {
            return false
        }

        let pathExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        return Self.watchedExtensions.contains(pathExtension)
    }

    private static let eventCallback: FSEventStreamCallback = { _, info, eventCount, eventPathsPointer, eventFlagsPointer, _ in
        guard let info else {
            return
        }

        let monitor = Unmanaged<FolderEventMonitor>.fromOpaque(info).takeUnretainedValue()
        let eventPaths = Unmanaged<NSArray>.fromOpaque(eventPathsPointer).takeUnretainedValue() as? [String] ?? []
        let eventFlags = Array(UnsafeBufferPointer(start: eventFlagsPointer, count: Int(eventCount)))
        monitor.handleEvents(paths: eventPaths, flags: eventFlags)
    }
}
