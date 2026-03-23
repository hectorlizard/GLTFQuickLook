import Cocoa
import Quartz
import SceneKit
import GLTFSceneKit

class PreviewViewController: NSViewController, QLPreviewingController {
    
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
                let source = try GLTFSceneSource(url: url)
                let scene = try source.scene()
                
                DispatchQueue.main.async {
                    self.sceneView.scene = scene
                    handler(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    handler(error)
                }
            }
        }
    }
}
