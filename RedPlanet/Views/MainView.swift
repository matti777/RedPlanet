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
import GameplayKit

struct MainView: View {
    private let arkitSession = ARKitSession()
    private let worldTrackingProvider = WorldTrackingProvider()
    
    private let heightMapSize = 1025
    private let heightMapRoughness: Float = 0.55
    private let heightMapXZScale: Float = 0.5
    private let heightMapYScale: Float = 105.0
    private let heightMapUVScale: Float = 150.0
    
    /// Direction to the light source
    private let lightDirectionVector: SIMD3<Float> = [0.4, 0.5, -0.8]

    /// Color for the distance fog
//    private let distanceFogColor = UIColor(red: 0, green: 0, blue: 0)
    private let distanceFogColor = UIColor(red: 230, green: 230, blue: 230)

    /// Distance after which the geometry is no longer rendered
    private let distanceFogFarDistance: Float = -90

    /// Distance fog thickness factor. Given the fog factor equation f = e(-d * t) where t is the thickness
    /// and d is the distance (from the camera), a value of t = 0.03 gives almost full fog at d = 100.0
    private let distanceFogThickness: Float = 0.004
    
    /// Number of trees in the instance
    private let numberOfTrees = 1000
    
    /// Controls the movement speed
    private let movementSpeedMultiplier: Float = 0.00000001
    
    /// Defines the width of the no-go area on the map (in normalized coordinates)
    private let normalizedPositionMargin: Float = 0.1
    
    /// Normalized position on the heightmap; start in the center (0.5, 0.5).
    @State private var normalizedPosition = SIMD2<Float>(0.5, 0.5)

    var tap: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                log.debug("Tap gesture")
            }
    }
    
    var drag: some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                handleDragMovement(dragVelocity: value.velocity)
            }
    }
    
    var body: some View {
        RealityView { content in
            content.add(createSkySphere())
            
            let heightMap = try! HeightMap(size: heightMapSize, roughness: heightMapRoughness)
            let terrain = try! heightMap.createEntity(xzScale: heightMapXZScale, yScale: heightMapYScale, uvScale: heightMapUVScale)

            var material = try! await ShaderGraphMaterial(named: "/Root/TerrainMaterial", from: "Scene.usda", in: realityKitContentBundle)
            try! material.setParameter(name: "LightDirection", value: .simd3Float(lightDirectionVector))
            try! material.setParameter(name: "DistanceFogColor", value: .color(distanceFogColor))
            try! material.setParameter(name: "DistanceFogFarDistance", value: .float(distanceFogFarDistance))
            try! material.setParameter(name: "DistanceFogThickness", value: .float(distanceFogThickness))

            terrain.model!.materials = [material]
            terrain.components.set(createIBLComponent())
            terrain.components.set(ImageBasedLightReceiverComponent(imageBasedLight: terrain))

            content.add(terrain)
            content.add(CollisionBox())
            
            try! terrain.addChild(createTrees(heightmap: terrain.heightMap!))
        } update: { content in
            guard let terrain = content.entities.first(where: { entity in
                entity.components.has(HeightMapComponent.self)
            }) as? ModelEntity, let heightmap = terrain.heightMap else {
                log.error("no terrain entity")
                return
            }

            // Get the device ("camera" / head) world position so we can compensate for it
            let deviceTransform = getDeviceTransform()!
            let devicePosition = deviceTransform[3]
            
            let terrainSurfacePoint = try! heightmap.getTerrainSurfacePoint(atNormalizedPosition: normalizedPosition)
            
            // Simulate a "virtual camera" (eg. moving on the terrain) by translating the terrain by the
            // "virtual camera" position on the terrain
            terrain.position = -terrainSurfacePoint
            terrain.position.y += devicePosition.y - 0.8
        }.onAppear {
            Task {
                try! await arkitSession.run([worldTrackingProvider])
            }
        }
        .gesture(drag)
        .gesture(tap)
    }
    
    // MARK: Private methods
    
    private func createTrees(heightmap: HeightMapComponent) throws -> Entity {
        let entity = try Entity.load(named: "Tree_trunk", in: realityKitContentBundle)
        let modelEntity = entity.findEntity(named: "tree_trunk_model") as! ModelEntity
        let modelName = modelEntity.name
        
        let random = GKRandomSource.sharedRandom()
        var instances: [MeshResource.Instance] = []
        
        let treeBaseMaxY = heightmap.geometryMinY + ((heightmap.geometryMaxY - heightmap.geometryMinY) * 0.6)
        
        var treesAdded = 0
        let startTime = CFAbsoluteTimeGetCurrent()

        while treesAdded < numberOfTrees {
            // Allocate a random location for the instance on the heightmap
            let u = (random.nextUniform() * 0.9) + 0.05
            let v = (random.nextUniform() * 0.9) + 0.05
            let instanceLocation = SIMD2<Float>(u, v)
            var surfacePoint = try heightmap.getTerrainSurfacePoint(atNormalizedPosition: instanceLocation)
            
            // Only place trees into valleys, aka the low parts of the heightmap
            if surfacePoint.y > treeBaseMaxY {
                continue
            }
            
            // Sink the tree into the ground a little bit so its roots don't show
            surfacePoint.y -= 0.1
            
            var instanceTransform = Transform(translation: surfacePoint)

            // Introduce random rotation around y axis to each instance
            let yawAngle = (random.nextUniform() - 0.5) * .pi
            instanceTransform.rotation *= .init(angle: yawAngle, axis: [0, 1, 0])
            
            // Orientate the model upright
            instanceTransform.rotation *= .init(angle: -.pi / 2, axis: [1, 0, 0])

            // Add random scaling
            let scale = 1.0 + (random.nextUniform() * 0.6)
            instanceTransform.scale = [scale, scale, scale]
            
            // Construct an instance of the model
            instances.append(.init(id: "\(modelName)-\(treesAdded)", model: modelName, at: instanceTransform.matrix))
            treesAdded += 1
        }

        // Create a model with a single mesh and multiple instances
        var resourceContents = MeshResource.Contents()
        resourceContents.instances = .init(instances)
        resourceContents.models = modelEntity.model!.mesh.contents.models
        resourceContents.skeletons = modelEntity.model!.mesh.contents.skeletons
        let meshResource = try MeshResource.generate(from: resourceContents)
        let model = ModelEntity(mesh: meshResource, materials: modelEntity.model!.materials)
        log.debug("Created trees with \(model.model!.mesh.contents.instances.count) instances")
        log.debug("Tree instance creation took \(CFAbsoluteTimeGetCurrent() - startTime)")

        return model
    }
    
    private func handleDragMovement(dragVelocity: CGSize) {
        guard let deviceTransform = getDeviceTransform() else {
            log.error("Device transform not available!")
            return
        }
        
        // Use the device forward / right vectors to move around.
        // We start by projecting them onto the XZ plane and normalizing them.
        let deviceForwardVector = deviceTransform[2]
        let deviceRightVector = deviceTransform[0]
        let forward = normalize(SIMD2<Float>(deviceForwardVector.x, deviceForwardVector.z))
        let right = normalize(SIMD2<Float>(deviceRightVector.x, deviceRightVector.z))
        
        // Calculate new position from forward vector multiplied by vertical drag amount plus
        // the right vector multiplied by the horizontal drag amount.
        var newPosition = normalizedPosition
        newPosition += forward * (Float(-dragVelocity.height) * movementSpeedMultiplier)
        newPosition += right * (Float(-dragVelocity.width) * movementSpeedMultiplier)
        
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
        
        // Update the position state variable
        normalizedPosition = newPosition
    }
    
    /// Creates an ImageBasedLightComponent from a single-color source image. This can be
    /// used to disable default scene lighting.
    private func createIBLComponent() -> ImageBasedLightComponent {
        // Create a CGImage filled with color
        let size = CGSize(width: 20, height: 10)
        UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
        let context = UIGraphicsGetCurrentContext()!
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        let cgImage = context.makeImage()!
        UIGraphicsEndImageContext()

        // Create the IBL component out of the image
        let resource = try! EnvironmentResource.generate(fromEquirectangular: cgImage)
        let iblComponent = ImageBasedLightComponent(source: .single(resource), intensityExponent: 0.0)

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
        
        // Rotate the sky so that the star (light source) is in the desired position in the sky
        skySphere.orientation *= simd_quatf(angle: Float(Angle(degrees: 30).radians), axis: [1, 0, 0])
        skySphere.orientation *= simd_quatf(angle: Float(Angle(degrees: 160).radians), axis: [0, 1, 0])

        // Trick to flip vertex normals on the generated geometry so we can display
        // our image / video on the inside of the sphere
        skySphere.scale = .init(x: 1, y: 1, z: -1)
        
        return skySphere
    }
}
