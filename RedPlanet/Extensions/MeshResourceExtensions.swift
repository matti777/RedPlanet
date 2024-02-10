//
//  MeshResourceExtensions.swift
//  RedPlanet
//
//  Created by Matti Dahlbom on 7.2.2024.
//

import RealityKit

extension MeshResource {
    static func generateFrom(positions: [SIMD3<Float>], normals: [SIMD3<Float>], uvs: [SIMD2<Float>]?, indices: [UInt32]) throws -> MeshResource {

        var meshDescriptor = MeshDescriptor()
        meshDescriptor.positions = MeshBuffers.Positions(positions)
        meshDescriptor.normals = MeshBuffers.Normals(normals)
        if let uvs = uvs {
            meshDescriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs)
        }
        meshDescriptor.primitives = .triangles(indices)

        return try MeshResource.generate(from: [meshDescriptor])
    }
}
