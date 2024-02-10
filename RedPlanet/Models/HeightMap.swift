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

        let minValue = values.min()!
        let maxValue = values.max()!
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
    /*
    func getSurfaceNormal(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> GLKVector3 {
        let vectorA = GLKVector3Make(a.x, a.y, a.z)
        let vectorB = GLKVector3Make(b.x, b.y, b.z)
        let vectorC = GLKVector3Make(c.x, c.y, c.z)
        let AB = GLKVector3Subtract(vectorB, vectorA)
        let BC = GLKVector3Subtract(vectorC, vectorB)
        let crossProduct = GLKVector3CrossProduct(BC, AB)
        let normal = GLKVector3Normalize(crossProduct)
        return normal
    }
    */
    /// Creates a RealityKit entity from the heightmap, in the XZ plane where the heightmap values will be
    /// used for the Y coordinate.
    func createEntity(zxScale: Float, yScale: Float) -> Entity {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            print("createEntity() took \(CFAbsoluteTimeGetCurrent() - startTime)")
        }

        print("Will generate \(mapSize * mapSize * 2) polygons")

        let minValue = values.min()!
        let normalizationScaler = 1 / (values.max()! - minValue)

        var positions = [SIMD3<Float>]()

        var zoffset = Float(-(mapSize / 2)) * zxScale
        
        // Create vertex positions
        for y in stride(from: 0, to: mapSize, by: 1) {
            var xoffset = Float(-(mapSize / 2)) * zxScale
        
            for x in stride(from: 0, to: mapSize, by: 1) {
                let normalizedValue = (self[x, y] - minValue) * normalizationScaler
                positions.append([xoffset, normalizedValue * yScale, zoffset])
                xoffset += zxScale
            }
            zoffset += zxScale
        }
        
        var indices = [UInt32]()
        
        // Create vertex indices
        for y in stride(from: 0, to: mapSize - 1, by: 1) {
            for x in stride(from: 0, to: mapSize - 1, by: 1) {
                // Create 2 triangles per iteration, in counter clockwise vertex order
                indices += [
                    UInt32(y * mapSize + x),
                    UInt32((y + 1) * mapSize + x),
                    UInt32(y * mapSize + (x + 1)),
                    
                    UInt32((y + 1) * mapSize + x),
                    UInt32((y + 1) * mapSize + (x + 1)),
                    UInt32(y * mapSize + (x + 1))
                ]
            }
        }
        
        var normals = [SIMD3<Float>]()

        // Create vertex normals

        // TODO
        let entity = Entity()
        entity.components[ModelDebugOptionsComponent.self] = ModelDebugOptionsComponent(visualizationMode: .normal)
        
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
