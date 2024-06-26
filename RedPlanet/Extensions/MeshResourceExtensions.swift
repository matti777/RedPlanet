//
//  MeshResourceExtensions.swift
//  RedPlanet
//
//  Created by Matti Dahlbom on 7.2.2024.
//

import RealityKit

extension MeshResource {
    /// Generates a mesh resource from a list of primitives.
    ///
    /// - Parameters:
    ///   - name: name for the mesh resource
    ///   - positions: vertex coordinates
    ///   - normals: vertex normals
    ///   - uvs: vertex texture UV coordinates (optional)
    ///   - indices: triangle indices (indices into the other arrays)
    static func generateFrom(name: String, positions: [SIMD3<Float>], normals: [SIMD3<Float>], uvs: [SIMD2<Float>]?, indices: [UInt32]) throws -> MeshResource {

        assert(positions.count == normals.count, "invalid array sizes")
        
        var meshDescriptor = MeshDescriptor(name: name)
        meshDescriptor.positions = MeshBuffers.Positions(positions)
        meshDescriptor.normals = MeshBuffers.Normals(normals)
        if let uvs = uvs {
            assert(uvs.count == positions.count, "invalid number of uvs")
            meshDescriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        }
        meshDescriptor.primitives = .triangles(indices)

        return try MeshResource.generate(from: [meshDescriptor])
    }
}
