import Foundation

enum OversizedAnimationOptimizer {
    // Quick Look needs a representative animation set, not thousands of clips at once.
    private static let animationThreshold = 100
    private static let accessorThreshold = 10_000
    private static let retainedAnimationCount = 10

    static func shouldOptimize(_ rootObject: [String: Any]) -> Bool {
        guard ((rootObject["extensionsRequired"] as? [Any]) ?? []).isEmpty else {
            return false
        }

        let animationCount = (rootObject["animations"] as? [Any])?.count ?? 0
        let accessorCount = (rootObject["accessors"] as? [Any])?.count ?? 0
        return animationCount >= animationThreshold || accessorCount >= accessorThreshold
    }

    static func optimize(_ rootObject: inout [String: Any]) -> [Int: Int] {
        guard shouldOptimize(rootObject) else {
            return [:]
        }

        let retainedAnimations = Array(
            ((rootObject["animations"] as? [[String: Any]]) ?? []).prefix(retainedAnimationCount)
        )
        var usedAccessorIndices = collectStaticAccessorIndices(in: rootObject)
        collectAnimationAccessorIndices(in: retainedAnimations, into: &usedAccessorIndices)
        guard !usedAccessorIndices.isEmpty,
              let accessors = rootObject["accessors"] as? [[String: Any]],
              let bufferViews = rootObject["bufferViews"] as? [[String: Any]] else {
            return [:]
        }

        let retainedAccessorIndices = usedAccessorIndices.sorted()
        let accessorIndexMap = indexMap(for: retainedAccessorIndices)
        let retainedAccessors = retainedAccessorIndices.compactMap { index in
            accessors.indices.contains(index) ? accessors[index] : nil
        }
        guard retainedAccessors.count == retainedAccessorIndices.count else {
            return [:]
        }

        var usedBufferViewIndices = collectBufferViewIndices(from: retainedAccessors)
        collectImageBufferViewIndices(in: rootObject, into: &usedBufferViewIndices)

        let retainedBufferViewIndices = usedBufferViewIndices.sorted()
        let bufferViewIndexMap = indexMap(for: retainedBufferViewIndices)
        let retainedBufferViews = retainedBufferViewIndices.compactMap { index in
            bufferViews.indices.contains(index) ? bufferViews[index] : nil
        }
        guard retainedBufferViews.count == retainedBufferViewIndices.count else {
            return [:]
        }

        rewriteAccessorReferences(in: &rootObject, using: accessorIndexMap)
        rootObject["animations"] = rewriteAnimations(retainedAnimations, using: accessorIndexMap)
        rootObject["accessors"] = retainedAccessors.map {
            rewritingBufferViewReferences(in: $0, using: bufferViewIndexMap)
        }
        rootObject["bufferViews"] = retainedBufferViews
        rewriteImageBufferViewReferences(in: &rootObject, using: bufferViewIndexMap)

        let maximumByteLengths = maximumUsedByteLengths(for: retainedBufferViews)
        if var buffers = rootObject["buffers"] as? [[String: Any]] {
            for index in buffers.indices {
                if let maximumByteLength = maximumByteLengths[index] {
                    buffers[index]["byteLength"] = maximumByteLength
                }
            }
            rootObject["buffers"] = buffers
        }

        return maximumByteLengths
    }

    private static func collectStaticAccessorIndices(in rootObject: [String: Any]) -> Set<Int> {
        var indices: Set<Int> = []

        for mesh in (rootObject["meshes"] as? [[String: Any]]) ?? [] {
            for primitive in (mesh["primitives"] as? [[String: Any]]) ?? [] {
                if let index = primitive["indices"] as? Int {
                    indices.insert(index)
                }
                for index in ((primitive["attributes"] as? [String: Int]) ?? [:]).values {
                    indices.insert(index)
                }
                for target in (primitive["targets"] as? [[String: Int]]) ?? [] {
                    indices.formUnion(target.values)
                }
            }
        }

        for skin in (rootObject["skins"] as? [[String: Any]]) ?? [] {
            if let index = skin["inverseBindMatrices"] as? Int {
                indices.insert(index)
            }
        }
        return indices
    }

    private static func collectBufferViewIndices(from accessors: [[String: Any]]) -> Set<Int> {
        var indices: Set<Int> = []
        for accessor in accessors {
            if let index = accessor["bufferView"] as? Int {
                indices.insert(index)
            }
            if let sparse = accessor["sparse"] as? [String: Any] {
                if let sparseIndices = sparse["indices"] as? [String: Any],
                   let index = sparseIndices["bufferView"] as? Int {
                    indices.insert(index)
                }
                if let sparseValues = sparse["values"] as? [String: Any],
                   let index = sparseValues["bufferView"] as? Int {
                    indices.insert(index)
                }
            }
        }
        return indices
    }

    private static func collectAnimationAccessorIndices(
        in animations: [[String: Any]],
        into indices: inout Set<Int>
    ) {
        for animation in animations {
            for sampler in (animation["samplers"] as? [[String: Any]]) ?? [] {
                if let index = sampler["input"] as? Int {
                    indices.insert(index)
                }
                if let index = sampler["output"] as? Int {
                    indices.insert(index)
                }
            }
        }
    }

    private static func rewriteAnimations(
        _ animations: [[String: Any]],
        using indexMap: [Int: Int]
    ) -> [[String: Any]] {
        animations.map { animation in
            var rewrittenAnimation = animation
            if var samplers = animation["samplers"] as? [[String: Any]] {
                for index in samplers.indices {
                    if let oldInput = samplers[index]["input"] as? Int {
                        samplers[index]["input"] = indexMap[oldInput]
                    }
                    if let oldOutput = samplers[index]["output"] as? Int {
                        samplers[index]["output"] = indexMap[oldOutput]
                    }
                }
                rewrittenAnimation["samplers"] = samplers
            }
            return rewrittenAnimation
        }
    }

    private static func collectImageBufferViewIndices(
        in rootObject: [String: Any],
        into indices: inout Set<Int>
    ) {
        for image in (rootObject["images"] as? [[String: Any]]) ?? [] {
            if let index = image["bufferView"] as? Int {
                indices.insert(index)
            }
        }
    }

    private static func rewriteAccessorReferences(
        in rootObject: inout [String: Any],
        using indexMap: [Int: Int]
    ) {
        if var meshes = rootObject["meshes"] as? [[String: Any]] {
            for meshIndex in meshes.indices {
                guard var primitives = meshes[meshIndex]["primitives"] as? [[String: Any]] else {
                    continue
                }
                for primitiveIndex in primitives.indices {
                    if let oldIndex = primitives[primitiveIndex]["indices"] as? Int {
                        primitives[primitiveIndex]["indices"] = indexMap[oldIndex]
                    }
                    if let attributes = primitives[primitiveIndex]["attributes"] as? [String: Int] {
                        primitives[primitiveIndex]["attributes"] = attributes.compactMapValues { indexMap[$0] }
                    }
                    if let targets = primitives[primitiveIndex]["targets"] as? [[String: Int]] {
                        primitives[primitiveIndex]["targets"] = targets.map {
                            $0.compactMapValues { indexMap[$0] }
                        }
                    }
                }
                meshes[meshIndex]["primitives"] = primitives
            }
            rootObject["meshes"] = meshes
        }

        if var skins = rootObject["skins"] as? [[String: Any]] {
            for index in skins.indices {
                if let oldIndex = skins[index]["inverseBindMatrices"] as? Int {
                    skins[index]["inverseBindMatrices"] = indexMap[oldIndex]
                }
            }
            rootObject["skins"] = skins
        }
    }

    private static func rewritingBufferViewReferences(
        in accessor: [String: Any],
        using indexMap: [Int: Int]
    ) -> [String: Any] {
        var rewritten = accessor
        if let oldIndex = rewritten["bufferView"] as? Int {
            rewritten["bufferView"] = indexMap[oldIndex]
        }
        if var sparse = rewritten["sparse"] as? [String: Any] {
            if var indices = sparse["indices"] as? [String: Any],
               let oldIndex = indices["bufferView"] as? Int {
                indices["bufferView"] = indexMap[oldIndex]
                sparse["indices"] = indices
            }
            if var values = sparse["values"] as? [String: Any],
               let oldIndex = values["bufferView"] as? Int {
                values["bufferView"] = indexMap[oldIndex]
                sparse["values"] = values
            }
            rewritten["sparse"] = sparse
        }
        return rewritten
    }

    private static func rewriteImageBufferViewReferences(
        in rootObject: inout [String: Any],
        using indexMap: [Int: Int]
    ) {
        guard var images = rootObject["images"] as? [[String: Any]] else {
            return
        }
        for index in images.indices {
            if let oldIndex = images[index]["bufferView"] as? Int {
                images[index]["bufferView"] = indexMap[oldIndex]
            }
        }
        rootObject["images"] = images
    }

    private static func maximumUsedByteLengths(for bufferViews: [[String: Any]]) -> [Int: Int] {
        var maximums: [Int: Int] = [:]
        for bufferView in bufferViews {
            guard let bufferIndex = bufferView["buffer"] as? Int,
                  let byteLength = bufferView["byteLength"] as? Int else {
                continue
            }
            let end = (bufferView["byteOffset"] as? Int ?? 0) + byteLength
            maximums[bufferIndex] = max(maximums[bufferIndex] ?? 0, end)
        }
        return maximums
    }

    private static func indexMap(for retainedIndices: [Int]) -> [Int: Int] {
        Dictionary(uniqueKeysWithValues: retainedIndices.enumerated().map { ($1, $0) })
    }
}
