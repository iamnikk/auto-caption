//
//  autocaption_iosApp.swift
//  autocaption-ios
//
//  Created by Nikhil Patil on 19/10/26.
//

import SwiftUI

@main
struct autocaption_iosApp: App {
    init() {
        #if DEBUG
        _ = CaptionSegmenterTests.runAllTests()
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
