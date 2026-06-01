import Cocoa
import QuickLookThumbnailing
import OSLog
import SceneKit

class ThumbnailProvider: QLThumbnailProvider {
    private let logger = Logger(subsystem: "com.hectorlizard.GLTFQuickLook", category: "Thumbnail")
    private static let renderSemaphore = DispatchSemaphore(value: 1)
    private static let denseSceneMaxRenderDimension: CGFloat = 512
    
    override func provideThumbnail(for request: QLFileThumbnailRequest, _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let size = request.maximumSize
        
        // Use a QLThumbnailReply with drawing context to correctly handle scaling
        let reply = QLThumbnailReply(contextSize: size) { () -> Bool in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            Self.renderSemaphore.wait()
            defer { Self.renderSemaphore.signal() }

            return autoreleasepool {
                do {
                    let loadedScene = try SceneLoadCoordinator.loadScene(at: request.fileURL)
                    let renderScene = SceneLoadCoordinator.optimizedRenderScene(from: loadedScene, purpose: "thumbnail")
                    let renderSize = self.denseSceneRenderSize(for: size, isDenseScene: renderScene.isDenseScene)
                    let antialiasingMode: SCNAntialiasingMode = renderScene.isDenseScene ? .none : .multisampling4X

                    self.logger.notice(
                        """
                        Loaded thumbnail scene for \(request.fileURL.lastPathComponent, privacy: .public) geometry=\(renderScene.geometryNodeCount, privacy: .public) cameras=\(renderScene.cameraNodeCount, privacy: .public) dense=\(renderScene.isDenseScene, privacy: .public) renderSize=\(Int(renderSize.width), privacy: .public)x\(Int(renderSize.height), privacy: .public)
                        """
                    )

                    let renderer = SCNRenderer(device: nil, options: nil)
                    renderer.scene = renderScene.scene
                    renderer.autoenablesDefaultLighting = true
                    renderer.pointOfView = renderScene.pointOfView

                    let image = renderer.snapshot(atTime: 0.0, with: renderSize, antialiasingMode: antialiasingMode)
                    renderer.scene = nil

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
        }
        
        handler(reply, nil)
    }

    private func denseSceneRenderSize(for requestedSize: CGSize, isDenseScene: Bool) -> CGSize {
        guard isDenseScene else {
            return requestedSize
        }

        let largestDimension = max(requestedSize.width, requestedSize.height)
        guard largestDimension > Self.denseSceneMaxRenderDimension else {
            return requestedSize
        }

        let scale = Self.denseSceneMaxRenderDimension / largestDimension
        return CGSize(
            width: max(1, floor(requestedSize.width * scale)),
            height: max(1, floor(requestedSize.height * scale))
        )
    }
}
