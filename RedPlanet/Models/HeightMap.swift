//
//  HeightMap.swift
//  RedPlanet
//
//  Created by Matti Dahlbom on 7.2.2024.
//

import UIKit
import RealityKit
import GameplayKit

/*
  A height map generated using the Diamond-Square algorithm with recursion for a minimal code complexity.
 
  See:
   - https://en.wikipedia.org/wiki/Diamond-square_algorithm

 */
final class HeightMap {
    private static let heightMapModelName = "HeightMap"
    
    private let random = GKRandomSource.sharedRandom()
    
    private var values: [Float]
    private let mapSize: Int
    
    private var minValue: Float = 0.0
    private var maxValue: Float = 0.0

    private let gaussianKernel: [Float] = [0.006, 0.061, 0.242, 0.383, 0.242, 0.061, 0.006]

    enum Error: Swift.Error {
        case invalidArgument(message: String)
        case bitmapCreationFailed
        case invalidPosition
    }
    
    // MARK: Initializers
    
    /// Creates a new square heightmap with a given size (number of values per side) and roughness.
    ///
    /// - Parameters:
    ///   - size: Length / width of the generated map. The value must be 2^n+1 where n = positive integer.
    ///   - roughness: Determines the roughness of the terrain. Must be [0..1].
    init(size: Int, roughness: Float) throws {
        self.mapSize = size
        self.values = Array(repeating: 0, count: size * size)
        
        try check(size: size)
        
        if roughness < 0.0 {
            throw Error.invalidArgument(message: "roughness must be a positive value")
        }
        
        // Set corner values
//        let cornerValue = (random.nextUniform() - 0.5) * 0.3
        let cornerValue: Float = -0.1
        self[0, 0] = cornerValue
        self[0, size - 1] = cornerValue
        self[size - 1, 0] = cornerValue
        self[size - 1, size - 1] = cornerValue
        
        let startTime = CFAbsoluteTimeGetCurrent()

        var tileSize = mapSize - 1
        var randomness: Float = 1.0
        
        while tileSize >= 2 {
            try diamondSquare(x: 0, y: 0, tileSize: tileSize, randomness: randomness)
            tileSize /= 2
            randomness *= roughness
        }

        print("HeightMap generation took \(CFAbsoluteTimeGetCurrent() - startTime)")

        let startTime2 = CFAbsoluteTimeGetCurrent()
        self.values = convolveHorizontal()
        self.values = convolveVertical()
        print("Gaussian blur took \(CFAbsoluteTimeGetCurrent() - startTime2)")

        self.minValue = values.min()!
        self.maxValue = values.max()!
    }
    
    // MARK: Public methods

    /// Returns a modulus for a compared to n (a % n in some environments)
    @inline(__always)
    func mod(_ a: Int, _ n: Int) -> Int {
        let r = a % n
        return r >= 0 ? r : r + n
    }
    
    /// Returns a value at [x, y]. No bounds checking.
    @inline(__always)
    subscript(x: Int, y: Int) -> Float {
        get {
            values[y * mapSize + x]
        }
        set {
            values[y * mapSize + x] = newValue
        }
    }
    
    /// Returns a value at [x, y]. If coordinates are out of bounds, wrap them.
    @inline(__always)
    func getValue(x: Int, y: Int) -> Float {
        return self[mod(x, (mapSize - 1)), mod(y, (mapSize - 1))]
    }

    /// Creates an UIImage out of the heightmap, eg. for visualization purposes
    func toImage() throws -> UIImage {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            print("toImage() took \(CFAbsoluteTimeGetCurrent() - startTime)")
        }
        
        // Create a bitmap context
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(data: nil,
                                      width: mapSize,
                                      height: mapSize,
                                      bitsPerComponent: 8,
                                      bytesPerRow: mapSize * 4,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo.rawValue) else {
            throw HeightMap.Error.bitmapCreationFailed
        }

        let valueRange = maxValue - minValue
        
        var pixelData = [UInt8](repeating: 0, count: values.count * 4)
        let valueMultiplier = 255.0 / valueRange
        var offset = 0
        
        // Create RGBA values
        for value in values {
            pixelData[offset + 0] = UInt8((value - minValue) * valueMultiplier)
            pixelData[offset + 1] = 0
            pixelData[offset + 2] = 0
            pixelData[offset + 3] = 255
            offset += 4
        }
        
        // Set the pixel data in the context
        guard let imageData = context.data else {
            throw HeightMap.Error.bitmapCreationFailed
        }
        imageData.copyMemory(from: pixelData, byteCount: pixelData.count)
        
        // Create a CGImage from the context
        guard let cgImage = context.makeImage() else {
            throw HeightMap.Error.bitmapCreationFailed
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    /// Creates a RealityKit entity from the heightmap, in the XZ plane where the heightmap values will be
    /// used for the Y coordinate.
    ///
    /// The geometry is created like so - from "back" (negatize Z) to "front", left to right:
    ///
    /// +------+------+
    /// |0   / |1   / |2
    /// |  /   |  /   |
    /// |/     |/     |
    /// +------+------+
    /// |3   / |4   / |5
    /// |  /   |  /   |
    /// |/     |/     |
    /// +------+------+
    ///
    /// - Parameters:
    ///   - xzScale: Distance (in meters) between vertices in the ZX plane. Supplyinh xzScale: 1.0 would
    ///              mean a distance of 1.0 meters between heightmap value points in the landscape's XZ plane.
    ///   - yScale: Distance (in meters) between value points in the Y direction. This determines the height at each
    ///             heightmap value (vertex). The final height (Y value) at a vertex is determined by
    ///             multiplying the normalized heightmap value by this parameter. 
    ///             Thus supplying yScale: 10.0 would result
    ///             in a landscape where the height difference between the lowest and the highest point
    ///             would be 10 meters.
    ///   - uvScale: How many times the texture should wrap in the object. Value of 1.0 means the entire texture
    ///              is used exactly once, 2.0 means it is repeated twice over the mesh etc.
    func createEntity(xzScale: Float, yScale: Float, uvScale: Float) throws -> ModelEntity {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            log.debug("createEntity() took \(CFAbsoluteTimeGetCurrent() - startTime)")
        }

        let numVertices = mapSize * mapSize
        let numFaces = (mapSize - 1) * (mapSize - 1) * 2
        let numIndices = numFaces * 3
        log.debug("Will generate: \(numVertices) vertices, \(numFaces) faces, \(numIndices) indices.")

        let normalizationScaler = 1.0 / (maxValue - minValue)

        // This will store our vertex positions (coordinates)
        var positions: [SIMD3<Float>] = Array.init(repeating: SIMD3<Float>(), count: numVertices)

        // This will store our texture UV coordinates
        var uvs: [SIMD2<Float>] = Array.init(repeating: SIMD2<Float>(), count: numVertices)

        var positionIndex = 0
        
        let xzMinPos = -((Float(mapSize - 1) / 2.0) * xzScale)
        let yMinPos = minValue * yScale * normalizationScaler
        let yMaxPos = maxValue * yScale * normalizationScaler
        var zoffset = xzMinPos
        log.debug("Will generate geometry in XZ plane [\(xzMinPos)..\(-xzMinPos)] and Y direction [\(yMinPos)..\(yMaxPos)]")
        
        let uvStep = (1.0 / Float(mapSize - 1)) * uvScale
        var v: Float = 0.0
        
        // Create vertex positions
        for y in stride(from: 0, to: mapSize, by: 1) {
            var xoffset = xzMinPos
            var u: Float = 0.0

            for x in stride(from: 0, to: mapSize, by: 1) {
                let normalizedValue = self[x, y] * normalizationScaler
                positions[positionIndex] = [xoffset, normalizedValue * yScale, zoffset]
                uvs[positionIndex] = [u, v]
                
                positionIndex += 1
                xoffset += xzScale
                u += uvStep
            }
            zoffset += xzScale
            v += uvStep
        }
        
        log.debug("vertex position generation took \(CFAbsoluteTimeGetCurrent() - startTime)")

        let startTime2 = CFAbsoluteTimeGetCurrent()
        
        // This will contain the vertex indices for all the triangles in the mesh
        var indices: [UInt32] = Array.init(repeating: 0, count: numIndices)

        // This is used to store normals of all faces to which a given vertex belongs. Once
        // all normals for all vertices have been gathered, they will be summed up and normalized to form
        // a smoothed vertex normal.
        var normalsPerVertex: [[SIMD3<Float>]] = Array.init(repeating: [SIMD3<Float>](), count: numVertices)
        for vertexIndex in stride(from: 0, to: numVertices, by: 1) {
            normalsPerVertex[vertexIndex] = [SIMD3<Float>]()
        }

        var indicesIndex = 0
        
        // Create vertex indices and face normals. Create 2 triangles per iteration,
        // in counterclockwise vertex order.
        for y in stride(from: 0, to: mapSize - 1, by: 1) {
            for x in stride(from: 0, to: mapSize - 1, by: 1) {
                // Triangle one is the "upper left corner"
                let i0 = y * mapSize + x
                let i1 = (y + 1) * mapSize + x
                let i2 = y * mapSize + (x + 1)
                indices[indicesIndex] = UInt32(i0)
                indices[indicesIndex + 1] = UInt32(i1)
                indices[indicesIndex + 2] = UInt32(i2)
                indicesIndex += 3

                let faceNormal1 = calculateFaceNormal(positions: positions, triangleIndices: [i0, i1, i2])
                
                // Add the face normal to every vertex in the triangle
                normalsPerVertex[i0].append(faceNormal1)
                normalsPerVertex[i1].append(faceNormal1)
                normalsPerVertex[i2].append(faceNormal1)

                // Triangle two is the "lower right corner"
                let i3 = (y + 1) * mapSize + x
                let i4 = (y + 1) * mapSize + (x + 1)
                let i5 = y * mapSize + (x + 1)
                indices[indicesIndex] = UInt32(i3)
                indices[indicesIndex + 1] = UInt32(i4)
                indices[indicesIndex + 2] = UInt32(i5)
                indicesIndex += 3

                let faceNormal2 = calculateFaceNormal(positions: positions, triangleIndices: [i3, i4, i5])

                // Add the face normal to every vertex in the triangle
                normalsPerVertex[i3].append(faceNormal2)
                normalsPerVertex[i4].append(faceNormal2)
                normalsPerVertex[i5].append(faceNormal2)
            }
        }
        
        // Create smoothed vertex normals by adding all the face normals at each vertex together and normalizing the result
        let vertexNormals = normalsPerVertex.map { normalize($0.reduce(SIMD3<Float>(), +)) }
        assert(vertexNormals.count == numVertices, "invalid number of vertex normals generated")
        
        log.debug("indices / normals generation took \(CFAbsoluteTimeGetCurrent() - startTime2)")

        let startTime3 = CFAbsoluteTimeGetCurrent()

        let entity = ModelEntity()
        entity.components.set(ModelComponent(mesh: try .generateFrom(name: HeightMap.heightMapModelName, positions: positions, normals: vertexNormals, uvs: uvs, indices: indices), materials: []))

        entity.components.set(HeightMapComponent(numVertices: numVertices, numFaces: numFaces, mapSize: mapSize, xzScale: xzScale, geometryMinY: yMinPos, geometryMaxY: yMaxPos, positions: positions))
        
        log.debug("entity creation took \(CFAbsoluteTimeGetCurrent() - startTime3)")

        return entity
    }
    
    // MARK: Private methods
    
    /// Applias a 1D convolution kernel to the heightmap data in the horizontal dimension
    private func convolveHorizontal() -> [Float] {
        var result: [Float] = Array(repeating: 0, count: mapSize * mapSize)
        let kernelSize = gaussianKernel.count
        let halfSize = kernelSize / 2
        
        var valueOffset = 0
        for y in stride(from: 0, through: mapSize - 1, by: 1) {
            for x in stride(from: 0, through: mapSize - 1, by: 1) {
                var value: Float = 0.0
                for kx in stride(from: 0, through: kernelSize - 1, by: 1) {
                    value += getValue(x: x + kx - halfSize, y: y) * gaussianKernel[kx]
                }
                result[valueOffset] = value
                valueOffset += 1
            }
        }
        
        return result
    }

    /// Applias a 1D convolution kernel to the heightmap data in the vertical dimension
    private func convolveVertical() -> [Float] {
        var result: [Float] = Array(repeating: 0, count: mapSize * mapSize)
        let kernelSize = gaussianKernel.count
        let halfSize = kernelSize / 2

        var valueOffset = 0
        for y in stride(from: 0, through: mapSize - 1, by: 1) {
            for x in stride(from: 0, through: mapSize - 1, by: 1) {
                var value: Float = 0.0
                for ky in stride(from: 0, through: kernelSize - 1, by: 1) {
                    value += getValue(x: x, y: y + ky - halfSize) * gaussianKernel[ky]
                }
                result[valueOffset] = value
                valueOffset += 1
            }
        }
        
        return result
    }

    /// Checks that the size value is in form of 2^n+1
    private func check(size: Int) throws {
        if size < 5 {
            throw Error.invalidArgument(message: "size must be >= 5")
        }
        
        let n = size - 1
        
        // Check if only one bit is set in the binary representation
        if (n & (n - 1)) != 0 {
            throw Error.invalidArgument(message: "size is not n^2+1")
        }
    }
    
    @inline(__always)
    private func calculateFaceNormal(positions: [SIMD3<Float>], triangleIndices: [Int]) -> SIMD3<Float> {
        assert(triangleIndices.count == 3, "indices array size must be 3")
        
        // Calculate vectors representing two edges of the face
        let v1 = positions[triangleIndices[1]] - positions[triangleIndices[0]]
        let v2 = positions[triangleIndices[2]] - positions[triangleIndices[0]]
        
        // Calculate the cross product to get the face normal
        return normalize(cross(v1, v2))
    }
    
    @inline(__always)
    private func squareStep(x: Int, y: Int, _ tileSize: Int, _ randomness: Float, _ halfSize: Int) {
        let average = (getValue(x: x, y: y - halfSize) +
                       getValue(x: x + halfSize, y: y) +
                       getValue(x: x, y: y + halfSize) +
                       getValue(x: x - halfSize, y: y)) * 0.25
        
        let value = average + Float(random.nextUniform() - 0.5) * randomness
        self[x, y] = value
        
        // Make the mep tileable
        if x == 0 {
            self[mapSize - 1, y] = value
        }
        if y == 0 {
            self[x, mapSize - 1] = value
        }
    }
    
    private func diamondSquare(x: Int, y: Int, tileSize: Int, randomness: Float) throws {
        let halfSize = tileSize / 2
        
        // Diamond steps (set the center point value of each 'tile')
        for x in stride(from: 0, to: mapSize - 1, by: tileSize) {
            for y in stride(from: 0, to: mapSize - 1, by: tileSize) {
                let average = (self[x, y] +
                               self[x + tileSize, y] +
                               self[x + tileSize, y + tileSize] +
                               self[x, y + tileSize]) * 0.25
                let value = average + Float(random.nextUniform() - 0.5) * randomness
                self[x + halfSize, y + halfSize] = value
            }
        }
        
        // Square steps (set the middle point of each edge of the each 'tile'
        for x in stride(from: 0, to: mapSize - 1, by: tileSize) {
            for y in stride(from: 0, to: mapSize - 1, by: tileSize) {
                squareStep(x: x + tileSize, y: y + halfSize, tileSize, randomness, halfSize) // right
                squareStep(x: x + halfSize, y: y + tileSize, tileSize, randomness, halfSize) // bottom
                squareStep(x: x, y: y + halfSize, tileSize, randomness, halfSize) // left (do after right)
                squareStep(x: x + halfSize, y: y, tileSize, randomness, halfSize) // top (do after bottom)
            }
        }
    }
    
    /// Creates a 1m by 1m plane (in the XY plane) with the heightmap image as a texture.
    /// Can be used to debug the map creation
    func createDebugPlane() throws -> Entity {
        let textureMap = try toImage()
        
        let plane = Entity()
        var material = UnlitMaterial()
        let textureResource = try! TextureResource.generate(from: textureMap.cgImage!, options: .init(semantic: nil, mipmapsMode: .none))
        material.color = .init(tint: .white.withAlphaComponent(1.0), texture: .init(textureResource))

        plane.components[ModelComponent.self] = .init(mesh: .generatePlane(width: 1.0,
                                                                           height: 1.0,
                                                                           cornerRadius: 0),
                                                       materials: [material])

        return plane
    }
}

/// Used to attach heightmap metadata into the generated terrain ModelEntity.
struct HeightMapComponent: Component, Equatable, Codable {
    let numVertices: Int
    let numFaces: Int
    let mapSize: Int
    let xzScale: Float
    let geometryMinY: Float
    let geometryMaxY: Float
    let positions: [SIMD3<Float>]
}

extension ModelEntity {
    var heightMap: HeightMapComponent? {
        return self.components[HeightMapComponent.self]
    }
}

extension HeightMapComponent {
    /// Finds the geometry polygon at the normalized position ([0..1, 0..1])
    func getTerrainPolygon(at normalizedPosition: SIMD2<Float>) throws -> Triangle {
        if normalizedPosition.x.isNaN || normalizedPosition.y.isNaN {
            throw HeightMap.Error.invalidArgument(message: "Supplied a NaN argument")
        }
        
        if normalizedPosition.x <= 0 || normalizedPosition.x >= 1 ||
            normalizedPosition.y <= 0 || normalizedPosition.y >= 1 {
            log.error("invalid normalizedPosition: \(normalizedPosition)")
            throw HeightMap.Error.invalidPosition
        }
        
        // The co-ordinatesu,v are coordinates to the height map and will identify the map "square"
        // made up of 2 triangles. Their fractional parts indicate the exact location on the "square" and thus
        // can be used to find the correct triangle to look at for the height check.
        let uf = normalizedPosition.x * Float(mapSize - 1)
        let vf = normalizedPosition.y * Float(mapSize - 1)
        let ufrac = uf.truncatingRemainder(dividingBy: 1.0)
        let vfrac = vf.truncatingRemainder(dividingBy: 1.0)
        let u = Int(floor(uf))
        let v = Int(floor(vf))
        
        // Figure out of the triangle indices of the polygon at the normalized position.
        // Each "square" on the heightmap (x * y) is made up of 2 triangles, 3 indices each.
        let i0, i1, i2: Int
        if ufrac + vfrac <= 1.0 {
            // First triangle of the "square", the "upper left half"
            i0 = v * mapSize + u
            i1 = (v + 1) * mapSize + u
            i2 = v * mapSize + (u + 1)
        } else {
            // Second triangle of the "square", the "bottom right half"
            i0 = (v + 1) * mapSize + u
            i1 = (v + 1) * mapSize + (u + 1)
            i2 = v * mapSize + (u + 1)
        }
        
        // Extract the polygon vertices (positions)
        return Triangle(v0: positions[i0], v1: positions[i1], v2: positions[i2])
    }
    
    /// Returns geometry (x, z) positions by translating from [0,0..1,1] to [-0.5..0.5] and
    /// multiplying by the geometry scale
    func getGeometryPosition(forNormalizedPosition normalizedPosition: SIMD2<Float>) -> SIMD2<Float> {
        return (normalizedPosition - [0.5, 0.5]) * (Float(mapSize - 1) * xzScale)
    }
    
    /// Finds the geometry polygon at the normalized position ([0..1, 0..1]) on the heightmap and then
    /// finds the Y coordinate on the polygon at that location.
    func getTerrainSurfacePoint(atNormalizedPosition normalizedPosition: SIMD2<Float>) throws -> SIMD3<Float> {
        let polygon = try getTerrainPolygon(at: normalizedPosition)
        
        let geometryPosition = getGeometryPosition(forNormalizedPosition: normalizedPosition)
        
        // Form a downwards vector from a position (far) above the XZ position indicated
        // by the normalized position
        let lineOrigin = SIMD3<Float>(geometryPosition.x, 1e4, geometryPosition.y)
        let lineDirection = SIMD3<Float>(0, -1, 0)
        
        // Find the intersection point between said downwards vector and the terrain geometry polygon
        guard let intersectionPoint = linePolygonIntersection(polygon, lineOrigin, lineDirection) else {
            log.error("failed to find intersection point")
            return [geometryPosition.x, 0.0, geometryPosition.y]
        }
        
        return intersectionPoint
    }

}
