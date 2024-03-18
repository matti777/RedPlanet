//
//  CollisionBox.swift
//  RedPlanet
//
//  Created by Matti Dahlbom on 18.3.2024.
//

import RealityKit

/// An invisible, enclosing box of collision shapes to capture gestures anywhere
class CollisionBox: Entity {
    required init() {
        super.init()
        
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
        
        let faces = [front, back, right, left, top, bottom]
        
        for face in faces {
            face.components.set(InputTargetComponent())
            addChild(face)
        }
    }
}
