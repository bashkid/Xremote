//
//  XremoteApp.swift
//  Xremote
//
//  Created by Rohit Kumar on 22/06/26.
//

import SwiftUI
import CoreData

@main
struct XremoteApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
