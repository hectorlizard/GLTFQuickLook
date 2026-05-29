import Foundation
import GLTFSceneKit
import OSLog
import SceneKit

struct SceneLoadResult {
    let scene: SCNScene
    let pointOfView: SCNNode
    let geometryNodeCount: Int
    let cameraNodeCount: Int
}

enum SceneLoadCoordinator {
    private static let logger = Logger(subsystem: "com.hectorlizard.GLTFQuickLook", category: "SceneLoad")

    static func loadScene(at url: URL) throws -> SceneLoadResult {
        let fileScope = url.startAccessingSecurityScopedResource()
        let directoryURL = url.deletingLastPathComponent()
        let directoryScope = directoryURL.startAccessingSecurityScopedResource()

        logger.debug("Loading scene for \(url.path, privacy: .public) fileScope=\(fileScope, privacy: .public) directoryScope=\(directoryScope, privacy: .public)")

        defer {
            if directoryScope {
                directoryURL.stopAccessingSecurityScopedResource()
            }
            if fileScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let source = makeSceneSource(for: url)
        let scene = try source.scene()

        let geometryNodeCount = countNodes(in: scene.rootNode) { $0.geometry != nil }
        let cameraNodes = collectNodes(in: scene.rootNode) { $0.camera != nil }
        let pointOfView = cameraNodes.first ?? makeFallbackCamera(for: scene)

        let (boundsMin, boundsMax) = scene.rootNode.boundingBox
        logger.debug(
            """
            Scene loaded for \(url.lastPathComponent, privacy: .public) geometryNodes=\(geometryNodeCount, privacy: .public) cameras=\(cameraNodes.count, privacy: .public) boundsMin=(\(boundsMin.x, privacy: .public), \(boundsMin.y, privacy: .public), \(boundsMin.z, privacy: .public)) boundsMax=(\(boundsMax.x, privacy: .public), \(boundsMax.y, privacy: .public), \(boundsMax.z, privacy: .public))
            """
        )

        return SceneLoadResult(
            scene: scene,
            pointOfView: pointOfView,
            geometryNodeCount: geometryNodeCount,
            cameraNodeCount: cameraNodes.count
        )
    }

    private static func makeSceneSource(for url: URL) -> GLTFSceneSource {
        if let preparedDocumentData = PreparedDocumentFileCache.preparedDocumentData(for: url, logger: logger) {
            return GLTFSceneSource(data: preparedDocumentData)
        }
        return GLTFSceneSource(url: url)
    }

    private static func countNodes(in rootNode: SCNNode, where predicate: (SCNNode) -> Bool) -> Int {
        var count = 0
        rootNode.enumerateChildNodes { node, _ in
            if predicate(node) {
                count += 1
            }
        }
        return count
    }

    private static func collectNodes(in rootNode: SCNNode, where predicate: (SCNNode) -> Bool) -> [SCNNode] {
        var nodes: [SCNNode] = []
        rootNode.enumerateChildNodes { node, _ in
            if predicate(node) {
                nodes.append(node)
            }
        }
        return nodes
    }

    private static func makeFallbackCamera(for scene: SCNScene) -> SCNNode {
        let (boundsMin, boundsMax) = scene.rootNode.boundingBox
        let center = SCNVector3(
            x: (boundsMin.x + boundsMax.x) * 0.5,
            y: (boundsMin.y + boundsMax.y) * 0.5,
            z: (boundsMin.z + boundsMax.z) * 0.5
        )

        let dx = CGFloat(boundsMax.x - boundsMin.x)
        let dy = CGFloat(boundsMax.y - boundsMin.y)
        let dz = CGFloat(boundsMax.z - boundsMin.z)
        let radius = max(sqrt(dx * dx + dy * dy + dz * dz) * 0.5, 0.001)

        let camera = SCNCamera()
        camera.fieldOfView = 50
        camera.zNear = 0.001
        camera.zFar = max(radius * 100, 100)

        let node = SCNNode()
        node.name = "__GLTFQuickLookFallbackCamera"
        node.camera = camera
        node.position = SCNVector3(
            x: CGFloat(center.x),
            y: CGFloat(center.y) + radius * 0.15,
            z: CGFloat(center.z) + radius * 2.8
        )
        node.look(at: center)
        scene.rootNode.addChildNode(node)
        return node
    }
}
