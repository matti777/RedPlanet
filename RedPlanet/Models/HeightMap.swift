//
//  HeightMap.swift
//  RedPlanet
//
//  Created by Matti Dahlbom on 7.2.2024.
//

import UIKit
import RealityKit

/*
  A height map generated using the Diamond-Square algorithm with recursion for a minimal code complexity.
 
  See:
   - https://en.wikipedia.org/wiki/Diamond-square_algorithm

 */
final class HeightMap {
    private static let heightMapModelName = "HeightMap"
    
    private var values: [Float]
    private let mapSize: Int
    private let roughness: Float
    
    private var minValue: Float = 0.0
    private var maxValue: Float = 0.0

    enum Error: Swift.Error {
        case invalidArgument(message: String)
        case bitmapCreationFailed
        case invalidPosition
    }
    
    /// Creates a new square heightmap with a given size (number of values per side) and roughness.
    ///
    /// - Parameters:
    ///   - size: Length / width of the generated map. The value must be 2^n+1 where n = positive integer.
    ///   - roughness: Determines the roughness of the terrain. Must be [0..1].
    init(size: Int, roughness: Float) throws {
        self.mapSize = size
        self.values = Array(repeating: 0, count: size * size)
        self.roughness = roughness
        
        try check(size: size)
        
        if roughness < 0.0 {
            throw Error.invalidArgument(message: "roughness must be a positive value")
        }
        
        // Set corner values
//        let cornerValue = Float(drand48())
        self[0, 0] = Float(drand48())
        self[0, size - 1] = Float(drand48())
        self[size - 1, 0] = Float(drand48())
        self[size - 1, size - 1] = Float(drand48())
        
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            print("HeightMap generation took \(CFAbsoluteTimeGetCurrent() - startTime)")
        }

        var tileSize = mapSize - 1
        while tileSize >= 2 {
            try diamondSquare(x: 0, y: 0, tileSize: tileSize)
            tileSize /= 2
        }
        
        self.minValue = values.min()!
        self.maxValue = values.max()!
    }

    /// Returns a value at [x, y]. No bounds checking.
    subscript(x: Int, y: Int) -> Float {
        get {
            values[y * mapSize + x]
        }
        set {
            values[y * mapSize + x] = newValue
        }
    }
    
    func debugPrintValues() {
        for y in stride(from: 0, to: mapSize, by: 1) {
            var values = ""
            for x in stride(from: 0, to: mapSize, by: 1) {
                values += "\t\(self[x, y])"
            }
            print(values)
        }
    }

    /// Returns a value at [x, y]. If coordinates are out of bounds, wrap them.
    func getValue(x: Int, y: Int) -> Float {
        
        // TODO write this using modulo
        
        var wrapx = x
        while wrapx < 0 {
            wrapx += mapSize
        }
        
        var wrapy = y
        while wrapy < 0 {
            wrapy += mapSize
        }
        
        return self[wrapx % mapSize, wrapy % mapSize]
    }

    /// Checks that the size value is in form of 2^n+1
    private func check(size: Int) throws {
        // TODO check for 2^n+1 instead
        if size % 2 != 1 {
            throw Error.invalidArgument(message: "size must be 2n+1 instead of: \(size)")
        }
    }
    
    @inline(__always)
    private func squareStep(x: Int, y: Int, tileSize: Int) {
        let halfSize = tileSize / 2
        let average = (getValue(x: x, y: y - halfSize) +
                       getValue(x: x + halfSize, y: y) +
                       getValue(x: x, y: y + halfSize) +
                       getValue(x: x - halfSize, y: y)) * 0.25
        
        let offset = Float(drand48() - 0.5) * roughness * Float(tileSize)
        self[x, y] = average + offset
    }

    private func diamondSquare(x: Int, y: Int, tileSize: Int) throws {
        let halfSize = tileSize / 2

        // Diamond steps (set the center point value of each 'tile')
        for x in stride(from: 0, to: mapSize - 1, by: tileSize) {
            for y in stride(from: 0, to: mapSize - 1, by: tileSize) {
                let average = (self[x, y] +
                               self[x + tileSize, y] +
                               self[x + tileSize, y + tileSize] +
                               self[x, y + tileSize]) / 4.0
                let offset = Float(drand48() - 0.5) * roughness * Float(tileSize)
                self[x + halfSize, y + halfSize] = average + offset
            }
        }
        
        // Square steps (set the middle point of each edge of the each 'tile'
        for x in stride(from: 0, to: mapSize - 1, by: tileSize) {
            for y in stride(from: 0, to: mapSize - 1, by: tileSize) {
                squareStep(x: x + halfSize, y: y, tileSize: tileSize) // top
                squareStep(x: x + tileSize, y: y + halfSize, tileSize: tileSize) // right
                squareStep(x: x + halfSize, y: y + tileSize, tileSize: tileSize) // bottom
                squareStep(x: x, y: y + halfSize, tileSize: tileSize) // left
            }
        }
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
 
    @inline(__always)
    private func calculateFaceNormal(positions: [SIMD3<Float>], triangleIndices: [Int]) -> SIMD3<Float> {
        assert(triangleIndices.count == 3, "indices array size must be 3")
        
        // Calculate vectors representing two edges of the face
        let v1 = positions[triangleIndices[1]] - positions[triangleIndices[0]]
        let v2 = positions[triangleIndices[2]] - positions[triangleIndices[0]]

        // Calculate the cross product to get the face normal
        return normalize(cross(v1, v2))
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
            print("createEntity() took \(CFAbsoluteTimeGetCurrent() - startTime)")
        }

        let numVertices = mapSize * mapSize
        let numFaces = (mapSize - 1) * (mapSize - 1) * 2
        let numIndices = numFaces * 3
        print("Will generate: \(numVertices) vertices, \(numFaces) faces, \(numIndices) indices.")

        let normalizationScaler = 1.0 / (maxValue - minValue)

        // This will store our vertex positions (coordinates)
        var positions: [SIMD3<Float>] = Array.init(repeating: SIMD3<Float>(), count: numVertices)

        // This will store our texture UV coordinates
        var uvs: [SIMD2<Float>] = Array.init(repeating: SIMD2<Float>(), count: numVertices)

        var positionIndex = 0
        
        let xzMinPos = -((Float(mapSize - 1) / 2.0) * xzScale)
        var zoffset = xzMinPos
        print("Will generate geometry in XZ plane [\(xzMinPos)..\(-xzMinPos)] and Y direction [\(minValue * yScale * normalizationScaler)..\(maxValue * yScale * normalizationScaler)]")
        
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
        
        print("vertex position generation took \(CFAbsoluteTimeGetCurrent() - startTime)")

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
        
        print("indices / normals generation took \(CFAbsoluteTimeGetCurrent() - startTime2)")

        let startTime3 = CFAbsoluteTimeGetCurrent()

        let entity = ModelEntity()
        entity.components.set(ModelComponent(mesh: try .generateFrom(name: HeightMap.heightMapModelName, positions: positions, normals: vertexNormals, uvs: uvs, indices: indices), materials: [SimpleMaterial()]))

        entity.components.set(HeightMapComponent(mapSize: mapSize, xzScale: xzScale))
        
        print("entity creation took \(CFAbsoluteTimeGetCurrent() - startTime3)")

        return entity
    }
    
    /// Finds the geometry polygon at the normalized position ([0..1, 0..1]) on the heightmap and then
    /// finds the Y coordinate on the polygon at that location.
    ///
    /// TODO: handle device transform as well?
    static func getTerrainSurfacePoint(at normalizedPosition: SIMD2<Float>, entity: ModelEntity) throws -> SIMD3<Float> {
        if normalizedPosition.x <= 0 || normalizedPosition.x >= 1 ||
            normalizedPosition.y <= 0 || normalizedPosition.y >= 1 {
            log.error("invalid normalizedPosition: \(normalizedPosition)")
            throw Error.invalidPosition
        }
            
        let part = entity.model!.mesh.contents.models[heightMapModelName]!.parts[heightMapModelName]!
        let m = entity.heightMap!
        
//        log.debug("normalizedPosition: \(normalizedPosition)")
        
        // The co-ordinatesu,v are coordinates to the height map and will identify the map "square"
        // made up of 2 triangles. Their fractional parts indicate the exact location on the "square" and thus
        // can be used to find the correct triangle to look at for the height check.
        let uf = normalizedPosition.x * Float(m.mapSize - 1)
        let vf = normalizedPosition.y * Float(m.mapSize - 1)
        let ufrac = uf.truncatingRemainder(dividingBy: 1.0)
        let vfrac = vf.truncatingRemainder(dividingBy: 1.0)
        let u = Int(floor(uf))
        let v = Int(floor(vf))
        
//        log.debug("(uf,vf): \(uf),\(vf)")
//        log.debug("(u,v): \(u),\(v), frac: \(ufrac),\(vfrac)")

        // Get geometry (x, z) positions by translating from [0,0..1,1] to [-0.5..0.5] and
        // multiplying by the geometry scale
        let geometryPosition = (normalizedPosition - [0.5, 0.5]) * (Float(m.mapSize - 1) * m.xzScale)

//        log.debug("geometryPosition: \(geometryPosition)")
        
        // Figure out of the triangle indices of the polygon at the normalized position.
        // Each "square" on the heightmap (x * y) is made up of 2 triangles, 3 indices each.
        let indicesOffset = (v * (m.mapSize - 1) * 3 * 2) + (u * 3 * 2)
        let indices = part.triangleIndices!.elements
        let i0, i1, i2: UInt32
        
        if ufrac + vfrac <= 1.0 {
            // First triangle of the "square", the "upper left half"
//            log.debug("selecting upper left triangle")
            i0 = indices[indicesOffset]
            i1 = indices[indicesOffset + 1]
            i2 = indices[indicesOffset + 2]
        } else {
            // Second triangle of the "square", the "bottom right half"
//            log.debug("selecting lower right triangle")
            i0 = indices[indicesOffset + 3]
            i1 = indices[indicesOffset + 4]
            i2 = indices[indicesOffset + 5]
        }
        
//        log.debug("triangle indices: (\(i0),\(i1),\(i2))")
        
        // Extract the polygon vertices (positions)
        let positions = part.positions.elements
        let v0 = positions[Int(i0)]
        let v1 = positions[Int(i1)]
        let v2 = positions[Int(i2)]
        
//        log.debug("triangle vertices: (\(v0),\(v1),\(v2)")
        
        // Form a downwards vector from a position (far) above the XZ position indicated
        // by the normalized position
        let lineOrigin = SIMD3<Float>(geometryPosition.x, 1e4, geometryPosition.y)
        let lineDirection = SIMD3<Float>(0, -1, 0)
        
        // Find the intersection point between said downwards vector and the terrain geometry polygon
        guard let intersectionPoint = linePolygonIntersection(v0, v1, v2, lineOrigin, lineDirection) else {
            log.error("failed to find intersection point")
            return [geometryPosition.x, 0.0, geometryPosition.y]
        }
        
        return intersectionPoint
    }
    
    /// Calculates the intersection point of a directional line ("ray") and a polygon (triangle)
    /// in 3D space, if any, using the Möller–Trumbore intersection algorithm.
    ///
    /// See: https://en.wikipedia.org/wiki/M%C3%B6ller%E2%80%93Trumbore_intersection_algorithm
    ///
    /// Vertices are to be defined in the counter-clockwise order.
    ///
    ///  - Parameters:
    ///    - v0: vertex of the triangle
    ///    - v1: vertex of the triangle
    ///    - v2: vertex of the triangle
    ///    - lineOrigin: an "origin" point for the line (ie. any point on the line)
    ///    - lineDirection: direction vector for the line, from the lineOrigin.
    ///  - Returns: the intersection point or nil if the line ("ray") does not intersect with the polygon (triangle)
    private static func linePolygonIntersection(_ v0: SIMD3<Float>, _ v1: SIMD3<Float>, _ v2: SIMD3<Float>, _ lineOrigin: SIMD3<Float>, _ lineDirection: SIMD3<Float>) -> SIMD3<Float>? {
        // 'epsilon' is a very small tolerance value used for ~equality comparison and it is used to
        // counter floating-point math accuracy issues.
        let epsilon: Float = 1e-6

        let edge1 = v1 - v0
        let edge2 = v2 - v0

        // Check if the line is parallel to the plane; that is, if the dot product between the line direction
        // and the polygon's normal is zero. For this, we will find the value of the determinant (used later
        // in the solution). The determinant is the area of the parallelogram created by two vectors. If this
        // area is zero, the vectors are parallel.
        let lineCrossEdge2 = cross(lineDirection, edge2)
        let det = dot(edge1, lineCrossEdge2)
        if abs(det) < epsilon {
            // In our use case, this should never happen, thus log it as error
            log.error("line is parallel to the polygon")
            return nil
        }

        // Find "u" and reject values outside their range
        let invdet = 1.0 / det;
        let s = lineOrigin - v0;
        let u = invdet * dot(s, lineCrossEdge2);
        
        if u < 0 || u > 1 {
            log.error("u is outside [0,1]: \(u)")
            return nil;
        }

        // Find "v" and reject values outside their range
        let sCrossEdge1 = cross(s, edge1);
        let v = invdet * dot(lineDirection, sCrossEdge1);
        
        if v < 0 || u + v > 1 {
            log.error("v is outside its range")
            return nil;
        }
        
        // Compute "t" to find where the intersection point is on the line
        let t = invdet * dot(edge2, sCrossEdge1);
        
        if t > epsilon {
            return lineOrigin + lineDirection * t
        } else {
            // Intersection point is on the line but not on the "ray" (from origin towards direction)
            log.debug("the intersection point is in the opposite direction on the line")
//            return lineOrigin + lineDirection * t
            return nil
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
    let mapSize: Int
    let xzScale: Float
}

extension ModelEntity {
    var heightMap: HeightMapComponent? {
        return self.components[HeightMapComponent.self]
    }
}

