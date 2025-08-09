//
//  Polno_3agruz0kApp.swift
//  Polno_3agruz0k
//
//  Created by soldenz on 25.03.2025.
//

import SwiftUI
import AVFoundation


@main
struct Polno_3agruz0kApp: App {
    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            print("✅ AVAudioSession активирован")
        } catch {
            print("❌ Ошибка AVAudioSession: \(error.localizedDescription)")
        }
    }
    var body: some Scene {
        WindowGroup {
            MainView()
        }
    }
}
