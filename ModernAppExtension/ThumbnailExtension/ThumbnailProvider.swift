import Cocoa
import QuickLookThumbnailing
import OSLog
import SceneKit

class ThumbnailProvider: QLThumbnailProvider {
    private let logger = Logger(subsystem: "com.hectorlizard.GLTFQuickLook", category: "Thumbnail")
    
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let size = request.maximumSize
        
        // Use a QLThumbnailReply with drawing context to correctly handle scaling
        let reply = QLThumbnailReply(contextSize: size) { () -> Bool in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            
            do {
                let loadResult = try SceneLoadCoordinator.loadScene(at: request.fileURL)
                self.logger.notice(
                    "Loaded thumbnail scene for \(request.fileURL.lastPathComponent, privacy: .public) geometry=\(loadResult.geometryNodeCount, privacy: .public) cameras=\(loadResult.cameraNodeCount, privacy: .public)"
                )
                
                let renderer = SCNRenderer(device: nil, options: nil)
                renderer.scene = loadResult.scene
                renderer.autoenablesDefaultLighting = true
                renderer.pointOfView = loadResult.pointOfView
                
                let image = renderer.snapshot(atTime: 0.0, with: size, antialiasingMode: .multisampling4X)
                
                if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    context.draw(cgImage, in: CGRect(origin: .zero, size: size))
                    self.logger.notice("Thumbnail rendered via direct cgImage for \(request.fileURL.lastPathComponent, privacy: .public)")
                    return true
                }

                if let tiffRepresentation = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffRepresentation),
                   let cgImage = bitmap.cgImage {
                    context.draw(cgImage, in: CGRect(origin: .zero, size: size))
                    self.logger.notice("Thumbnail rendered via TIFF fallback for \(request.fileURL.lastPathComponent, privacy: .public)")
                    return true
                }

                self.logger.error("Thumbnail snapshot did not yield drawable image data for \(request.fileURL.path, privacy: .public)")
            } catch {
                self.logger.error("Thumbnail failed for \(request.fileURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            return false
        }
        
        handler(reply, nil)
    }
}
