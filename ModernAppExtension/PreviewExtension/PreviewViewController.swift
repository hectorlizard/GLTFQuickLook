import Cocoa
import OSLog
import Quartz
import SceneKit

class PreviewViewController: NSViewController, QLPreviewingController {
    private let logger = Logger(subsystem: "com.hectorlizard.GLTFQuickLook", category: "Preview")
    
    var sceneView: SCNView!
    
    override func loadView() {
        self.sceneView = SCNView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        self.sceneView.autoresizingMask = [.width, .height]
        self.sceneView.backgroundColor = NSColor.windowBackgroundColor
        self.sceneView.allowsCameraControl = true
        self.sceneView.autoenablesDefaultLighting = true
        self.sceneView.rendersContinuously = false
        self.view = self.sceneView
    }
    
    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                do {
                    let loadedScene = try SceneLoadCoordinator.loadScene(at: url)
                    let loadResult = SceneLoadCoordinator.optimizedRenderScene(from: loadedScene, purpose: "preview")

                    DispatchQueue.main.async {
                        self.sceneView.scene = nil
                        self.applyRenderingConfiguration(isDenseScene: loadResult.isDenseScene)
                        self.sceneView.scene = loadResult.scene
                        self.sceneView.pointOfView = loadResult.pointOfView
                        self.logger.notice(
                            """
                            Preview loaded for \(url.lastPathComponent, privacy: .public) geometry=\(loadResult.geometryNodeCount, privacy: .public) cameras=\(loadResult.cameraNodeCount, privacy: .public) dense=\(loadResult.isDenseScene, privacy: .public)
                            """
                        )
                        handler(nil)
                    }
                } catch {
                    self.logger.error("Preview failed for \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    DispatchQueue.main.async {
                        handler(error)
                    }
                }
            }
        }
    }

    private func applyRenderingConfiguration(isDenseScene: Bool) {
        sceneView.antialiasingMode = isDenseScene ? .none : .multisampling4X
        sceneView.preferredFramesPerSecond = isDenseScene ? 15 : 60
    }
}
