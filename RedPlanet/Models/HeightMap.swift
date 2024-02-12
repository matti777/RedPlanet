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
    private var values: [Float]
    private let mapSize: Int
    private let roughness: Float
    
    private var minValue: Float = 0.0
    private var maxValue: Float = 0.0

    enum Error: Swift.Error {
        case invalidArgument(message: String)
        case bitmapCreationFailed
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
    
    private func squareStep(x: Int, y: Int, tileSize: Int) {
        let halfSize = tileSize / 2
        let average = (getValue(x: x, y: y - halfSize) +
                       getValue(x: x + halfSize, y: y) +
                       getValue(x: x, y: y + halfSize) +
                       getValue(x: x - halfSize, y: y)) / 4.0
        
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

        self.minValue = values.min()!
        self.maxValue = values.max()!
        let valueRange = maxValue - minValue
        
        print("minValue = \(minValue) maxValue = \(maxValue) valueRange = \(valueRange)")
        
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

    private func calculateFaceNormal(positions: [SIMD3<Float>], triangleIndices: ArraySlice<UInt32>) -> SIMD3<Float> {
        assert(triangleIndices.count == 3, "indices array size must be 3")
        
        // Calculate vectors representing two edges of the face
        let v1 = positions[Int(triangleIndices[1])] - positions[Int(triangleIndices[0])]
        let v2 = positions[Int(triangleIndices[2])] - positions[Int(triangleIndices[0])]

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
    ///             multiplying the normalized heightmap value by this parameter. Thus supplying yScale: 10.0 would result
    ///             in a landscape where the height difference between the lowest and the highest point
    ///             would be 10 meters.
    func createEntity(xzScale: Float, yScale: Float) throws -> Entity {
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
        var positionIndex = 0
        
        var zoffset = Float(-(mapSize / 2)) * xzScale
        
        // Create vertex positions
        for y in stride(from: 0, to: mapSize, by: 1) {
            var xoffset = Float(-(mapSize / 2)) * xzScale
        
            for x in stride(from: 0, to: mapSize, by: 1) {
                let normalizedValue = self[x, y] * normalizationScaler
                positions[positionIndex] = ([xoffset, normalizedValue * yScale, zoffset])
                positionIndex += 1
                xoffset += xzScale
            }
            zoffset += xzScale
        }
        
        print("vertex position generation took \(CFAbsoluteTimeGetCurrent() - startTime)")

        let startTime2 = CFAbsoluteTimeGetCurrent()
        
        // This will contain the vertex indices for all the triangles in the mesh
        var indices: [UInt32] = Array.init(repeating: 0, count: numIndices)

        // This is used to store normals of all faces to which a given vertex belongs. Once
        // all normals for all vertices have been gathered, they will be summed up and normalized to form
        // a smoothed vertex normal.
        var normalsPerVertex = [[SIMD3<Float>]]()
        normalsPerVertex.reserveCapacity(numVertices)
        for vertexIndex in stride(from: 0, to: numVertices, by: 1) {
            normalsPerVertex[vertexIndex] = [SIMD3<Float>]()
        }

        var indicesIndex = 0
        
        // Create vertex indices and face normals. Create 2 triangles per iteration,
        // in counterclockwise vertex order.
        for y in stride(from: 0, to: mapSize - 1, by: 1) {
            for x in stride(from: 0, to: mapSize - 1, by: 1) {
                // Triangle one is the "upper left corner"
                indices[indicesIndex] = UInt32(y * mapSize + x)
                indices[indicesIndex + 1] = UInt32((y + 1) * mapSize + x)
                indices[indicesIndex + 2] = UInt32(y * mapSize + (x + 1))

                let faceNormal1 = calculateFaceNormal(positions: positions, triangleIndices: indices[indicesIndex..<(indicesIndex + 3)])
                
                // Add the face normal to every vertex in the triangle
                normalsPerVertex[indicesIndex].append(faceNormal1)
                normalsPerVertex[indicesIndex + 1].append(faceNormal1)
                normalsPerVertex[indicesIndex + 2].append(faceNormal1)

                indicesIndex += 3
                
                // Triangle two is the "lower left corner"
                indices[indicesIndex] = UInt32((y + 1) * mapSize + x)
                indices[indicesIndex + 1] = UInt32((y + 1) * mapSize + (x + 1))
                indices[indicesIndex + 2] = UInt32(y * mapSize + (x + 1))
                
                let faceNormal2 = calculateFaceNormal(positions: positions, triangleIndices: indices[indicesIndex..<(indicesIndex + 3)])

                // Add the face normal to every vertex in the triangle
                normalsPerVertex[indicesIndex].append(faceNormal2)
                normalsPerVertex[indicesIndex + 1].append(faceNormal2)
                normalsPerVertex[indicesIndex + 2].append(faceNormal2)
                
                indicesIndex += 3
            }
        }
        
        // Create smoothed vertex normals by adding all the face normals at each vertex together and normalizing the result
        let vertexNormals = normalsPerVertex.map { normalize($0.reduce(SIMD3<Float>(), +)) }
        assert(vertexNormals.count == numVertices, "invalid number of vertex normals generated")
        
        print("indices / normals generation took \(CFAbsoluteTimeGetCurrent() - startTime2)")

        let startTime3 = CFAbsoluteTimeGetCurrent()

        let entity = Entity()
        entity.components.set(ModelComponent(mesh: try .generateFrom(positions: positions, normals: vertexNormals, uvs: nil, indices: indices), materials: [SimpleMaterial()]))

        // TODO remove debug stuff
        entity.components[ModelDebugOptionsComponent.self] = ModelDebugOptionsComponent(visualizationMode: .normal)

        print("entity creation took \(CFAbsoluteTimeGetCurrent() - startTime3)")

        return entity
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
