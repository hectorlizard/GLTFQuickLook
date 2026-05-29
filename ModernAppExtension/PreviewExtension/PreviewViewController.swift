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
        self.view = self.sceneView
    }
    
    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let loadResult = try SceneLoadCoordinator.loadScene(at: url)
                
                DispatchQueue.main.async {
                    self.sceneView.scene = loadResult.scene
                    self.sceneView.pointOfView = loadResult.pointOfView
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
