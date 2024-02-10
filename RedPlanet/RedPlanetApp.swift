//
//  RedPlanetApp.swift
//  RedPlanet
//
//  Created by Matti Dahlbom on 10.2.2024.
//

import SwiftUI

@main
struct RedPlanetApp: App {
    var body: some Scene {
        ImmersiveSpace(id: "MainView") {
            MainView()
        }.immersionStyle(selection: .constant(.progressive), in: .progressive)
    }
}
