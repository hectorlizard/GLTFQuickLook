import Cocoa
import OSLog

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.hectorlizard.GLTFQuickLook", category: "HostApp")
    private let watchedFoldersKey = "WatchedFolderPaths"
    private var statusItem: NSStatusItem?
    private var statusLabelItem = NSMenuItem(title: "Prêt", action: nil, keyEquivalent: "")
    private var isPreparing = false

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        configureStatusItem()

        let savedFolderURLs = watchedFolderURLs()
        print("GLTFQuickLook host launched with \(savedFolderURLs.count) watched folders")
        logger.notice("Host app launched with \(savedFolderURLs.count, privacy: .public) watched folders")
        if savedFolderURLs.isEmpty {
            logger.notice("No watched folders yet, opening folder picker")
            presentFolderPicker()
            return
        }

        prepare(folderURLs: savedFolderURLs, notifyUser: false)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let folderURLs = urls.map { $0.hasDirectoryPath ? $0 : $0.deletingLastPathComponent() }
        addWatchedFolders(folderURLs)
        prepare(folderURLs: watchedFolderURLs(), notifyUser: true)
    }

    @objc private func chooseFolders(_ sender: Any?) {
        presentFolderPicker()
    }

    @objc private func rescanFolders(_ sender: Any?) {
        prepare(folderURLs: watchedFolderURLs(), notifyUser: true)
    }

    @objc private func quitApp(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "GLTFQL"

        let menu = NSMenu()
        menu.addItem(withTitle: "Ajouter des dossiers…", action: #selector(chooseFolders(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Réanalyser les dossiers", action: #selector(rescanFolders(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        statusLabelItem.isEnabled = false
        menu.addItem(statusLabelItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter", action: #selector(quitApp(_:)), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }

        item.menu = menu
        statusItem = item
    }

    private func presentFolderPicker() {
        let panel = NSOpenPanel()
        panel.title = "Choisir les dossiers glTF a preparer"
        panel.message = "Selectionne les dossiers contenant tes exports .gltf pour generer automatiquement le cache Quick Look."
        panel.prompt = "Preparer"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true

        if panel.runModal() == .OK {
            addWatchedFolders(panel.urls)
            prepare(folderURLs: watchedFolderURLs(), notifyUser: true)
        }
    }

    private func watchedFolderURLs() -> [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: watchedFoldersKey) ?? []
        return paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private func addWatchedFolders(_ urls: [URL]) {
        let existingPaths = Set(UserDefaults.standard.stringArray(forKey: watchedFoldersKey) ?? [])
        let newPaths = urls
            .map { $0.standardizedFileURL.path }
            .filter { FileManager.default.fileExists(atPath: $0) }

        let mergedPaths = Array(existingPaths.union(newPaths)).sorted()
        UserDefaults.standard.set(mergedPaths, forKey: watchedFoldersKey)
    }

    private func prepare(folderURLs: [URL], notifyUser: Bool) {
        guard !isPreparing else {
            logger.notice("Skipping prepare request because another preparation is already running")
            return
        }
        guard !folderURLs.isEmpty else {
            statusLabelItem.title = "Aucun dossier configuré"
            logger.notice("Skipping prepare request because no folder is configured")
            if notifyUser {
                presentFolderPicker()
            }
            return
        }

        isPreparing = true
        statusLabelItem.title = "Préparation en cours…"
        print("Preparing \(folderURLs.count) folders")
        logger.notice("Preparing \(folderURLs.count, privacy: .public) folders")

        Task.detached(priority: .userInitiated) { [logger] in
            let summary = PreparedDocumentPreparer.prepare(urls: folderURLs, logger: logger)
            await MainActor.run {
                self.isPreparing = false
                self.statusLabelItem.title = "Préparés: \(summary.documentsPrepared) | Inchangés: \(summary.documentsSkipped) | Échecs: \(summary.failures.count)"
                self.logger.notice(
                    """
                    Preparation finished folders=\(summary.foldersScanned, privacy: .public) seen=\(summary.documentsSeen, privacy: .public) prepared=\(summary.documentsPrepared, privacy: .public) skipped=\(summary.documentsSkipped, privacy: .public) failures=\(summary.failures.count, privacy: .public)
                    """
                )
                if notifyUser {
                    self.presentSummary(summary)
                }
            }
        }
    }

    private func presentSummary(_ summary: PreparationRunSummary) {
        let alert = NSAlert()
        alert.messageText = "Préparation Quick Look terminée"
        alert.informativeText = """
        Dossiers scannés : \(summary.foldersScanned)
        Fichiers .gltf vus : \(summary.documentsSeen)
        Nouveaux caches : \(summary.documentsPrepared)
        Déjà à jour : \(summary.documentsSkipped)
        Échecs : \(summary.failures.count)
        """
        alert.alertStyle = summary.failures.isEmpty ? .informational : .warning
        if let firstFailure = summary.failures.first {
            alert.informativeText += "\n\nPremier échec :\n\(firstFailure)"
        }
        alert.runModal()
    }
}
