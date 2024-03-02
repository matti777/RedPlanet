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
    private let heightMapSize = 1025
    private let heightMapRoughness: Float = 0.44
    private let heightMapXZScale: Float = 0.5
    private let heightMapYScale: Float = 150.0
    private let heightMapUVScale: Float = 150.0
    private let lightDirectionVector: SIMD3<Float> = [2, 1, 0]

    private let arkitSession = ARKitSession()
    private let worldTrackingProvider = WorldTrackingProvider()
    
    private let movementSpeedMultiplier: Float = 0.00000001
    private let normalizedPositionMargin: Float = 0.1
    
    /// Normalized position on the heightmap; start in the center (0.5, 0.5).
    @State private var normalizedPosition = SIMD2<Float>(0.5, 0.5)

    var drag: some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                // Use drag event velocity to move around on the terrain
                
                // TODO consider the camera orientation here
                var newPosition = normalizedPosition + SIMD2<Float>(Float(-value.velocity.width) * movementSpeedMultiplier, Float(-value.velocity.height) * movementSpeedMultiplier)

                // Limit the position to certain margins
                if newPosition.x < normalizedPositionMargin {
                    newPosition.x = normalizedPositionMargin
                }
                if newPosition.x > (1.0 - normalizedPositionMargin) {
                    newPosition.x = (1.0 - normalizedPositionMargin)
                }
                if newPosition.y < normalizedPositionMargin {
                    newPosition.y = normalizedPositionMargin
                }
                if newPosition.y > (1.0 - normalizedPositionMargin) {
                    newPosition.y = (1.0 - normalizedPositionMargin)
                }

                normalizedPosition = newPosition
            }
    }
    
    var body: some View {
        RealityView { content in
            content.add(createSkySphere())
            
            let heightMap = try! HeightMap(size: heightMapSize, roughness: heightMapRoughness)
            let terrain = try! heightMap.createEntity(xzScale: heightMapXZScale, yScale: heightMapYScale, uvScale: heightMapUVScale)

            var material = try! await ShaderGraphMaterial(named: "/Root/TerrainMaterial", from: "Scene.usda", in: realityKitContentBundle)
            try! material.setParameter(name: "LightDirection", value: .simd3Float(lightDirectionVector))
            terrain.model!.materials = [material]
            terrain.components.set(createIBLComponent())
            
            content.add(terrain)
            content.add(createCollisionBox())
        } update: { content in
            guard let terrain = content.entities.first(where: { entity in
                entity.components.has(HeightMapComponent.self)
            }) as? ModelEntity else {
                log.error("no terrain entity")
                return
            }

            // Get the (Vision Pro) device ("camera" / head) world position so we can compensate for it
            let deviceTransform = getDeviceTransform()!
            let devicePosition = deviceTransform[3]
            
            let terrainSurfacePoint = try! HeightMap.getTerrainSurfacePoint(at: normalizedPosition, entity: terrain)
//            log.debug("terrainSurfacePoint: \(terrainSurfacePoint)")
            
            // Simulate a "virtual camera" (eg. moving on the terrain) by translating the terrain by the
            // "virtual camera" position on the terrain
            terrain.position = -terrainSurfacePoint
//            terrain.position.y += 2.0 // TODO figure this out
            terrain.position.y += devicePosition.y - 0.8
        }.onAppear {
            Task {
                try! await arkitSession.run([worldTrackingProvider])
                
                // TODO check if we need this
                for await update in worldTrackingProvider.anchorUpdates {
                    switch update.event {
                    case .added, .updated:
                        // Update the app's understanding of this world anchor.
                        print("Anchor position updated.")
                    case .removed:
                        // Remove content related to this anchor.
                        print("Anchor position now unknown.")
                    }
                }
            }
        }.gesture(drag)
    }
    
    /// Creates an ImageBasedLightComponent from a single-color source image. This can be
    /// used to disable default scene lighting.
    private func createIBLComponent() -> ImageBasedLightComponent {
        // Create a CGImage filled with color
        let size = CGSize(width: 20, height: 10)
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        let cgImage = context.makeImage()!
        UIGraphicsEndImageContext()

        // Create the IBL component out of the image
        let resource = try! EnvironmentResource.generate(fromEquirectangular: cgImage)
        let iblComponent = ImageBasedLightComponent(source: .single(resource), intensityExponent: 10.0)

        return iblComponent
    }
    
    /// Gets the current transform (in world space) of the (Vision Pro) device
    /// (ie. head / "camera" position + orientation
    private func getDeviceTransform() -> simd_float4x4? {
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
    
    /// Creates an invisible, enclosing box of collision shapes to capture gestures anywhere
    func createCollisionBox() -> Entity {
        let size: Float = 30 // There is a maximum distance for input events so we cannot use 'infinity'
        let thickness: Float = 0.001
        let offset = size / 2
        
        let front = Entity()
        front.components.set(CollisionComponent(shapes: [.generateBox(width: size, height: size, depth: thickness)]))
        front.position.z = offset
        
        let back = Entity()
        back.components.set(CollisionComponent(shapes: [.generateBox(width: size, height: size, depth: thickness)]))
        back.position.z = -offset
        
        let right = Entity()
        right.components.set(CollisionComponent(shapes: [.generateBox(width: thickness, height: size, depth: size)]))
        right.position.x = offset
        
        let left = Entity()
        left.components.set(CollisionComponent(shapes: [.generateBox(width: thickness, height: size, depth: size)]))
        left.position.x = -offset
        
        let top = Entity()
        top.components.set(CollisionComponent(shapes: [.generateBox(width: size, height: thickness, depth: size)]))
        top.position.y = offset
        
        let bottom = Entity()
        bottom.components.set(CollisionComponent(shapes: [.generateBox(width: size, height: thickness, depth: size)]))
        bottom.position.y = -offset
        
        let entity = Entity()
        let faces = [front, back, right, left, top, bottom]
        
        for face in faces {
            face.components.set(InputTargetComponent())
            entity.addChild(face)
        }
        
        return entity
    }
}
