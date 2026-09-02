import Foundation
import GLTFSceneKit
import OSLog
import SceneKit

struct SceneLoadResult {
    let scene: SCNScene
    let pointOfView: SCNNode
    let geometryNodeCount: Int
    let cameraNodeCount: Int
    let totalNodeCount: Int
    let isDenseScene: Bool
}

enum SceneLoadCoordinator {
    private static let logger = Logger(subsystem: "com.hectorlizard.GLTFQuickLook", category: "SceneLoad")
    private static let denseSceneGeometryThreshold = 4_000
    private static let denseSceneNodeThreshold = 10_000

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

        let initialGeometryNodeCount = countNodes(in: scene.rootNode) { $0.geometry != nil }
        let initialTotalNodeCount = countNodes(in: scene.rootNode) { _ in true }
        let cameraNodes = collectNodes(in: scene.rootNode) { $0.camera != nil }

        let isDenseScene = shouldTreatAsDenseScene(
            geometryNodeCount: initialGeometryNodeCount,
            totalNodeCount: initialTotalNodeCount
        )
        let pointOfView = cameraNodes.first ?? makeFallbackCamera(for: scene)

        let (boundsMin, boundsMax) = scene.rootNode.boundingBox
        logger.debug(
            """
            Scene loaded for \(url.lastPathComponent, privacy: .public) geometryNodes=\(initialGeometryNodeCount, privacy: .public) totalNodes=\(initialTotalNodeCount, privacy: .public) cameras=\(cameraNodes.count, privacy: .public) dense=\(isDenseScene, privacy: .public) boundsMin=(\(boundsMin.x, privacy: .public), \(boundsMin.y, privacy: .public), \(boundsMin.z, privacy: .public)) boundsMax=(\(boundsMax.x, privacy: .public), \(boundsMax.y, privacy: .public), \(boundsMax.z, privacy: .public))
            """
        )

        return SceneLoadResult(
            scene: scene,
            pointOfView: pointOfView,
            geometryNodeCount: initialGeometryNodeCount,
            cameraNodeCount: cameraNodes.count,
            totalNodeCount: initialTotalNodeCount,
            isDenseScene: isDenseScene
        )
    }

    static func optimizedRenderScene(from loadResult: SceneLoadResult, purpose: StaticString) -> SceneLoadResult {
        guard loadResult.isDenseScene else {
            return loadResult
        }

        logger.notice(
            """
            Simplifying dense scene for \(purpose, privacy: .public) geometryNodes=\(loadResult.geometryNodeCount, privacy: .public) totalNodes=\(loadResult.totalNodeCount, privacy: .public)
            """
        )

        let optimizedScene = SCNScene()
        let flattenedRoot = loadResult.scene.rootNode.flattenedClone()
        optimizedScene.rootNode.addChildNode(flattenedRoot)
        let pointOfView = makeFallbackCamera(for: optimizedScene)
        let geometryNodeCount = countNodes(in: optimizedScene.rootNode) { $0.geometry != nil }
        let totalNodeCount = countNodes(in: optimizedScene.rootNode) { _ in true }

        logger.notice(
            """
            Dense scene simplified for \(purpose, privacy: .public) geometryNodes=\(geometryNodeCount, privacy: .public) totalNodes=\(totalNodeCount, privacy: .public)
            """
        )

        return SceneLoadResult(
            scene: optimizedScene,
            pointOfView: pointOfView,
            geometryNodeCount: geometryNodeCount,
            cameraNodeCount: 0,
            totalNodeCount: totalNodeCount,
            isDenseScene: true
        )
    }

    private static func makeSceneSource(for url: URL) -> GLTFSceneSource {
        if let preparedDocumentData = PreparedDocumentFileCache.preparedDocumentData(for: url, logger: logger) {
            logger.notice("Using prepared document cache for \(url.path, privacy: .public)")
            return GLTFSceneSource(data: preparedDocumentData)
        }
        logger.notice("Using source glTF directly for \(url.path, privacy: .public)")
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

    private static func shouldTreatAsDenseScene(geometryNodeCount: Int, totalNodeCount: Int) -> Bool {
        geometryNodeCount >= denseSceneGeometryThreshold || totalNodeCount >= denseSceneNodeThreshold
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
