//
//  GeometryMath.swift
//  RedPlanet
//
//  Created by Matti Dahlbom on 26.3.2024.
//

import RealityKit

struct Triangle {
    let v0: SIMD3<Float>
    let v1: SIMD3<Float>
    let v2: SIMD3<Float>
}

/// Finds the geometry polygon at the normalized position ([0..1, 0..1])
func getTerrainPolygon(at normalizedPosition: SIMD2<Float>, heightmap: HeightMapComponent) throws -> Triangle {
    if normalizedPosition.x <= 0 || normalizedPosition.x >= 1 ||
        normalizedPosition.y <= 0 || normalizedPosition.y >= 1 {
        log.error("invalid normalizedPosition: \(normalizedPosition)")
        throw HeightMap.Error.invalidPosition
    }
    
    // The co-ordinatesu,v are coordinates to the height map and will identify the map "square"
    // made up of 2 triangles. Their fractional parts indicate the exact location on the "square" and thus
    // can be used to find the correct triangle to look at for the height check.
    let uf = normalizedPosition.x * Float(heightmap.mapSize - 1)
    let vf = normalizedPosition.y * Float(heightmap.mapSize - 1)
    let ufrac = uf.truncatingRemainder(dividingBy: 1.0)
    let vfrac = vf.truncatingRemainder(dividingBy: 1.0)
    let u = Int(floor(uf))
    let v = Int(floor(vf))
    
    // Figure out of the triangle indices of the polygon at the normalized position.
    // Each "square" on the heightmap (x * y) is made up of 2 triangles, 3 indices each.
    let i0, i1, i2: Int
    if ufrac + vfrac <= 1.0 {
        // First triangle of the "square", the "upper left half"
        i0 = v * heightmap.mapSize + u
        i1 = (v + 1) * heightmap.mapSize + u
        i2 = v * heightmap.mapSize + (u + 1)
    } else {
        // Second triangle of the "square", the "bottom right half"
        i0 = (v + 1) * heightmap.mapSize + u
        i1 = (v + 1) * heightmap.mapSize + (u + 1)
        i2 = v * heightmap.mapSize + (u + 1)
    }
    
    // Extract the polygon vertices (positions)
    return Triangle(v0: heightmap.positions[i0], v1: heightmap.positions[i1], v2: heightmap.positions[i2])
}

/// Calculates the intersection point of a directional line ("ray") and a polygon (triangle)
/// in 3D space, if any, using the Möller–Trumbore intersection algorithm.
///
/// See: https://en.wikipedia.org/wiki/M%C3%B6ller%E2%80%93Trumbore_intersection_algorithm
///
/// Vertices are to be defined in the counter-clockwise order.
///
///  - Parameters:
///    - polygon: vertices of the triangle
///    - lineOrigin: an "origin" point for the line (ie. any point on the line)
///    - lineDirection: direction vector for the line, from the lineOrigin.
///  - Returns: the intersection point or nil if the line ("ray") does not intersect with the polygon (triangle)
func linePolygonIntersection(_ polygon: Triangle, _ lineOrigin: SIMD3<Float>, _ lineDirection: SIMD3<Float>) -> SIMD3<Float>? {
    // 'epsilon' is a very small tolerance value used for ~equality comparison and it is used to
    // counter floating-point math accuracy issues.
    let epsilon: Float = 1e-6
    
    let edge1 = polygon.v1 - polygon.v0
    let edge2 = polygon.v2 - polygon.v0
    
    // Check if the line is parallel to the plane; that is, if the dot product between the line direction
    // and the polygon's normal is zero. For this, we will find the value of the determinant (used later
    // in the solution). The determinant is the area of the parallelogram created by two vectors. If this
    // area is zero, the vectors are parallel.
    let lineCrossEdge2 = cross(lineDirection, edge2)
    let det = dot(edge1, lineCrossEdge2)
    if abs(det) < epsilon {
        // In our use case, this should never happen, thus log it as error
        log.error("line is parallel to the polygon")
        return nil
    }
    
    // Find "u" and reject values outside their range
    let invdet = 1.0 / det;
    let s = lineOrigin - polygon.v0;
    let u = invdet * dot(s, lineCrossEdge2);
    
    if u < 0 || u > 1 {
        log.error("u is outside [0,1]: \(u)")
        return nil;
    }
    
    // Find "v" and reject values outside their range
    let sCrossEdge1 = cross(s, edge1);
    let v = invdet * dot(lineDirection, sCrossEdge1);
    
    if v < 0 || u + v > 1 {
        log.error("v is outside its range")
        return nil;
    }
    
    // Compute "t" to find where the intersection point is on the line
    let t = invdet * dot(edge2, sCrossEdge1);
    
    if t > epsilon {
        return lineOrigin + lineDirection * t
    } else {
        // Intersection point is on the line but not on the "ray" (from origin towards direction)
        log.debug("the intersection point is in the opposite direction on the line")
        return nil
    }
}
