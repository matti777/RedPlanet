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
    private let distanceFogColor = UIColor(red: 230, green: 230, blue: 230)

    /// Distance after which the geometry is no longer rendered
    private let distanceFogFarDistance: Float = -90

    /// Distance fog thickness factor. Given the fog factor equation f = e(-d * t) where t is the thickness
    /// and d is the distance (from the camera), a value of t = 0.03 gives almost full fog at d = 100.0
    private let distanceFogThickness: Float = 0.0045
    
    /// Number of trees in the instance
    private let numberOfTrees = 750
    
    /// Controls the movement speed
    private let forwardMovementSpeedMultiplier: Float = 0.00000001
    private let sidewaysMovementSpeedMultiplier: Float = 0.01

    /// Defines the width of the no-go area on the map (in normalized coordinates)
    private let normalizedPositionMargin: Float = 0.1
    
    /// Normalized position on the heightmap; start in the center (0.5, 0.5).
    @State private var normalizedPosition = SIMD2<Float>(0.5, 0.5)
    
    @State private var attachmentText = "Generating geometry.."
    @State private var attachmentOpen = true
    
    @State private var terrainEntity: ModelEntity? = nil
    @State private var terrainMaterial: ShaderGraphMaterial? = nil
    @State private var treeMaterial: ShaderGraphMaterial? = nil

    /// Manages the collision box drag
    private var collisionBoxDragState = CollisionBoxDragState()
    
    var drag: some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                handleDragMovement(gestureValue: value)
            }
            .onEnded { _ in
                collisionBoxDragState.dragEnded()
            }
    }
    
    var body: some View {
        RealityView { content, attachments in
            // Our 'skybox'
            content.add(createSkySphere())
            
            if let attachment = attachments.entity(for: "info_attachment") {
                attachment.position = [0, 1, -0.5]
                content.add(attachment)
            }
            
            // Load our custom material for the terrain
            terrainMaterial = try! await ShaderGraphMaterial(named: "/Root/TerrainMaterial", from: "Scene.usda", in: realityKitContentBundle)
            try! terrainMaterial!.setParameter(name: "LightDirection", value: .simd3Float(lightDirectionVector))
            try! terrainMaterial!.setParameter(name: "DistanceFogColor", value: .color(distanceFogColor))
            try! terrainMaterial!.setParameter(name: "DistanceFogFarDistance", value: .float(distanceFogFarDistance))
            try! terrainMaterial!.setParameter(name: "DistanceFogThickness", value: .float(distanceFogThickness))

            // Load our custom material for the trees
            treeMaterial = try! await ShaderGraphMaterial(named: "/Root/TreeMaterial", from: "Scene.usda", in: realityKitContentBundle)
            try! treeMaterial!.setParameter(name: "LightDirection", value: .simd3Float(lightDirectionVector))
            try! treeMaterial!.setParameter(name: "DistanceFogColor", value: .color(distanceFogColor))
            try! treeMaterial!.setParameter(name: "DistanceFogFarDistance", value: .float(distanceFogFarDistance))
            try! treeMaterial!.setParameter(name: "DistanceFogThickness", value: .float(distanceFogThickness))
        } update: { content, attachments in
            if let terrain = terrainEntity,
               let terrainMaterial = terrainMaterial,
               let treeMaterial = treeMaterial {
                log.debug("Adding geometry to the scene..")
                terrain.model!.materials = [terrainMaterial]
                let iblComponent = createIBLComponent()
                terrain.components.set(iblComponent)
                terrain.components.set(ImageBasedLightReceiverComponent(imageBasedLight: terrain))
                content.add(terrain)
                
                // Add trees via instanced geometry
                let trees = try! createTrees(heightmap: terrain.heightMap!)
                
                trees.model!.materials = [treeMaterial]
                trees.components.set(iblComponent)
                trees.components.set(ImageBasedLightReceiverComponent(imageBasedLight: terrain))
                trees.components.set(GroundingShadowComponent(castsShadow: true))
                terrain.addChild(trees)
                
                // Finally, add a collision box that will receive our drag events
                content.add(CollisionBox())

                Task {
                    terrainEntity = nil
                }
            }
            
            guard let terrain = content.entities.first(where: { entity in
                entity.components.has(HeightMapComponent.self)
            }) as? ModelEntity, let heightmap = terrain.heightMap else {
                log.error("no terrain entity")
                return
            }
            
            // Get the device ("camera" / head) world position so we can compensate for it
            var devicePositionY: Float = 1.5
            
            if let deviceTransform = getDeviceTransform() {
                devicePositionY = deviceTransform[3].y
            }
            
            if let attachment = attachments.entity(for: "info_attachment") {
                attachment.position.y = devicePositionY
            }

            guard let terrainSurfacePoint = try? heightmap.getTerrainSurfacePoint(atNormalizedPosition: normalizedPosition) else {
                log.error("Could not get surface point")
                return
            }
            
            // Simulate a "virtual camera" (eg. moving on the terrain) by translating the terrain by the
            // "virtual camera" position on the terrain
            let cameraLocation = SIMD3<Float>(terrainSurfacePoint.x, terrainSurfacePoint.y + devicePositionY, terrainSurfacePoint.z)
            let cameraTransform = Transform(translation: cameraLocation)
            terrain.transform = Transform(matrix: cameraTransform.matrix.inverse)
        } attachments: {
            Attachment(id: "info_attachment") {
                InfoAttachmentView(text: $attachmentText, show: $attachmentOpen)
                    .frame(width: 350, height: 220)
                    .glassBackgroundEffect()
                    .opacity(attachmentOpen ? 1.0 : 0.0)
            }
        }
        .task {
            try! await arkitSession.run([worldTrackingProvider])
        }
        .task {
            generateGeometry()
        }
        .gesture(drag)
    }
    
    // MARK: Private methods
    
    private func generateGeometry() {
        DispatchQueue.global(qos: .userInitiated).async {
            // Create our height map + generate the terrain object from it
            let heightMap = try! HeightMap(size: heightMapSize, roughness: heightMapRoughness)
            let terrain = try! heightMap.createEntity(xzScale: heightMapXZScale, yScale: heightMapYScale, uvScale: heightMapUVScale)
            
            DispatchQueue.main.async {
                log.debug("Geometry generated, ready to add to the scene")
                terrainEntity = terrain
                let heightmap = terrain.heightMap!
                attachmentText = "Geometry generated:\n\nVertices:\t\(heightmap.numVertices)\nFaces:\t\t\(heightmap.numFaces)"
                
                Task { @MainActor in
                    try await Task.sleep(for: .seconds(7.5))
                    withAnimation(.easeIn) {
                        attachmentOpen = false
                    }
                }
            }
        }
    }
    
    private func createTrees(heightmap: HeightMapComponent) throws -> ModelEntity {
        let entity = try Entity.load(named: "Tree_trunk", in: realityKitContentBundle)
        let modelEntity = entity.findEntity(named: "tree_trunk_model") as! ModelEntity
        let modelName = modelEntity.name
        
        let random = GKRandomSource.sharedRandom()
        var instances: [MeshResource.Instance] = []
        
        let treeBaseMaxY = heightmap.geometryMinY + ((heightmap.geometryMaxY - heightmap.geometryMinY) * 0.8)
        
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
            let scale = 1.0 + (random.nextUniform() * 1.6)
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
    
    private func handleDragMovement(gestureValue: EntityTargetValue<DragGesture.Value>) {
        guard let deviceTransform = getDeviceTransform() else {
            log.error("Device transform not available!")
            return
        }
        
        // Use the device forward / right vectors to move around.
        // We start by projecting them onto the XZ plane and normalizing them.
        let deviceRightVector = deviceTransform[0]
        let deviceForwardVector = deviceTransform[2]
        let forward = normalize(SIMD2<Float>(deviceForwardVector.x, deviceForwardVector.z))
        let right = normalize(SIMD2<Float>(deviceRightVector.x, deviceRightVector.z))
        
        // Horizontal drag amount cannot be taken from dragVelocity since its sign will change
        // depending on the orientation.
        let horizontalDragAmount = collisionBoxDragState.dragChange(dragGestureValue: gestureValue, deviceTransform: deviceTransform)

        let dragVelocity = gestureValue.velocity
        
        // Calculate new position from forward vector multiplied by vertical drag amount plus
        // the right vector multiplied by the horizontal drag amount.
        var newPosition = normalizedPosition
        newPosition += forward * (Float(-dragVelocity.height) * forwardMovementSpeedMultiplier)
        newPosition += right * horizontalDragAmount * sidewaysMovementSpeedMultiplier
        
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
        skySphere.orientation *= simd_quatf(angle: Float(Angle(degrees: 150).radians), axis: [0, 1, 0])

        // Trick to flip vertex normals on the generated geometry so we can display
        // our image / video on the inside of the sphere
        skySphere.scale = .init(x: 1, y: 1, z: -1)
        
        return skySphere
    }
}

/// Handles the horizontal dragging with a collision box that surrounds the user. The need for this class
/// is that the horizontal drags cannot be handled via Value.velocity due to it yielding a different sign depending
/// on orientation. So instead we are looking at the "rotation" around the user caused by the drag gesture and
/// using that amount (angle updates in radians) as our horizontal drag amount.
private final class CollisionBoxDragState {
    private var prevLocation: Point3D?
    
    func dragChange(dragGestureValue: EntityTargetValue<DragGesture.Value>, deviceTransform: simd_float4x4) -> Float {
        if prevLocation == nil {
            // No drag active; start new one
            prevLocation = dragGestureValue.startLocation3D
        }
        
        // Calculate (yaw) rotation around device position in 2D space (set y = 0), as defined by the angle between
        // vectors device -> prevLocation and device -> current location.
        let prev = SIMD3<Float>(Float(prevLocation!.x), 0, Float(prevLocation!.z))
        let current = SIMD3<Float>(Float(dragGestureValue.location3D.x), 0, Float(dragGestureValue.location3D.z))
        let devicePosition = deviceTransform[3]
        let device = SIMD3<Float>(devicePosition.x, 0, devicePosition.z)
        let a = prev - device
        let b = current - device
        let len = (length(a) * length(b))

        prevLocation = dragGestureValue.location3D
        
        // If the combined lengths is zero, the division will yield NaN so in that case we'll just use 0
        if len <= 0.0001 {
            return 0.0
        }
        
        let angleInRadians = acos(dot(a, b) / len)
        if angleInRadians.isNaN {
            return 0.0
        }
        
        let sign: Float = cross(a, b).y < 0 ? -1.0 : 1.0
        
        return angleInRadians * sign
    }
    
    func dragEnded() {
        prevLocation = nil
    }
}
