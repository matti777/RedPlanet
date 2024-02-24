//
//  RedPlanetApp.swift
//  RedPlanet
//
//  Created by Matti Dahlbom on 10.2.2024.
//

import SwiftUI
import OSLog

/// Global logger instance
let log = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "app")

@main
struct RedPlanetApp: App {
    var body: some Scene {
        ImmersiveSpace(id: "MainView") {
            MainView()
        }.immersionStyle(selection: .constant(.progressive), in: .progressive)
    }
}
