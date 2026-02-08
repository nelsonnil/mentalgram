//
//  MentalGram1App.swift
//  MentalGram1
//
//  Created by NELSON SUÁREZ ARTEAGA on 8/2/26.
//

import SwiftUI

@main
struct MentalGram1App: App {
    @ObservedObject var instagram = InstagramService.shared
    
    var body: some Scene {
        WindowGroup {
            if instagram.isLoggedIn {
                HomeView()
            } else {
                LoginView()
            }
        }
    }
}
