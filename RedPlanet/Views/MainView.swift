//
//  MainView.swift
//  RedPlanet
//
//  Created by Matti Dahlbom on 10.2.2024.
//

import SwiftUI
import RealityKit
import RealityKitContent
import ARKit

struct MainView: View {
    private let heightMapSize = 5 // 4097
    private let heightMapRoughness: Float = 0.1
    private let heightMapXZScale: Float = 0.5
    private let heightMapYScale: Float = 0.9
    private let heightMapUVScale: Float = 1.0
    private let lightDirectionVector: SIMD3<Float> = [3, 1, -3]

    private let arkitSession = ARKitSession()
    private let worldTrackingProvider = WorldTrackingProvider()
    
    var body: some View {
        RealityView { content in
            content.add(createSkySphere())
            
            let heightMap = try! HeightMap(size: heightMapSize, roughness: heightMapRoughness)
//            let debugPlane = try! heightMap.createDebugPlane()
//            debugPlane.position = [0, 1.0, -1.5]
//            content.add(debugPlane)
            let heightMapEntity = try! heightMap.createEntity(xzScale: heightMapXZScale, yScale: heightMapYScale, uvScale: heightMapUVScale)

//            let textureResource = try! TextureResource.generate(from: experience.lobbyArtistBackgroundImage.cgImage!, options: .init(semantic: nil, mipmapsMode: .none))
//            let texture = try! TextureResource.load(named: "red_mountain_rock.jpg")
//            var material = UnlitMaterial()
//            material.color = .init(texture: .init(texture))
            var material = try! await ShaderGraphMaterial(named: "/Root/TerrainMaterial", from: "Scene.usda", in: realityKitContentBundle)
            try! material.setParameter(name: "LightDirection", value: .simd3Float(lightDirectionVector))
            heightMapEntity.model!.materials = [material]
            
            heightMapEntity.position = [0, -1.0, -2]
            content.add(heightMapEntity)
        } update: { content in
            // TBD
        }.onAppear {
            Task {
                try! await arkitSession.run([worldTrackingProvider])
            }
        }
    }
    
    /// Gets the current transform (in world space) of the (Vision Pro) device 
    /// (ie. head / "camera" position + orientation
    private func getDeviceTransform() async -> simd_float4x4? {
        guard let deviceAnchor = worldTrackingProvider.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else {
            return nil
        }
        
        return deviceAnchor.originFromAnchorTransform
    }
    
    /// Creates a "sky sphere" with the given material
    private func createSkySphere() -> Entity {
        let texture = try! TextureResource.load(named: "space_skybox")
        var material = UnlitMaterial()
        material.color = .init(texture: .init(texture))
        
        // Create spherical geometry with an immense radius to act as our "skybox"
        let skySphere = Entity()
        skySphere.components.set(ModelComponent(mesh: .generateSphere(radius: 1E3), materials: [material]))
        
        // Trick to flip vertex normals on the generated geometry so we can display
        // our image / video on the inside of the sphere
        skySphere.scale = .init(x: 1, y: 1, z: -1)
        
        return skySphere
    }
}
