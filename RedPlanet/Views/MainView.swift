//
//  MainView.swift
//  RedPlanet
//
//  Created by Matti Dahlbom on 10.2.2024.
//

import SwiftUI
import RealityKit

struct MainView: View {
    private let heightMapSize = 4097
    private let heightMapRoughness: Float = 0.1
    
    var body: some View {
        RealityView { content in
            content.add(createSkySphere())
            
            let heightMap = try! HeightMap(size: heightMapSize, roughness: heightMapRoughness)
            let debugPlane = try! heightMap.createDebugPlane()
            debugPlane.position = [0, 1.0, -1.5]
            content.add(debugPlane)
        } update: { content in
            // TBD
        }
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
