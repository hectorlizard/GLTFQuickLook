import Cocoa
import QuickLookThumbnailing
import SceneKit
import GLTFSceneKit

class ThumbnailProvider: QLThumbnailProvider {
    
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let size = request.maximumSize
        
        // Use a QLThumbnailReply with drawing context to correctly handle scaling
        let reply = QLThumbnailReply(contextSize: size) { () -> Bool in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            
            do {
                let source = try GLTFSceneSource(url: request.fileURL)
                let scene = try source.scene()
                
                let renderer = SCNRenderer(device: nil, options: nil)
                renderer.scene = scene
                renderer.autoenablesDefaultLighting = true
                
                let image = renderer.snapshot(atTime: 0.0, with: size, antialiasingMode: .multisampling4X)
                
                if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    context.draw(cgImage, in: CGRect(origin: .zero, size: size))
                    return true
                }
            } catch {
                print("Error generating thumbnail: \(error)")
            }
            return false
        }
        
        handler(reply, nil)
    }
}
