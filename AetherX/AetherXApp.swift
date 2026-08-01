import SwiftUI

@main
struct AetherXApp: App {
    init() {
        ConsoleLogger.shared.startRedirecting()
        _ = GamepadManager.shared
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
import GameController

class GamepadManager: ObservableObject {
    static let shared = GamepadManager()
    
    private init() {
        startListening()
    }
    
    private func startListening() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(controllerDidConnect),
            name: .GCControllerDidConnect, object: nil)
        
        NotificationCenter.default.addObserver(
            self, selector: #selector(controllerDidDisconnect),
            name: .GCControllerDidDisconnect, object: nil)
        
        // Register any already connected controllers
        for controller in GCController.controllers() {
            register(controller)
        }
    }
    
    @objc private func controllerDidConnect(notification: Notification) {
        if let controller = notification.object as? GCController {
            register(controller)
        }
    }
    
    @objc private func controllerDidDisconnect(notification: Notification) {
        // Handle disconnect if necessary
        print("Controller disconnected")
    }
    
    private func register(_ controller: GCController) {
        print("Controller connected: \(controller.vendorName ?? "Unknown")")
        
        guard let gamepad = controller.extendedGamepad else {
            return
        }
        
        // Map GameController inputs to AetherX/Libretro Button IDs
        // Retropad IDs:
        // B: 0, Y: 1, Select: 2, Start: 3, Up: 4, Down: 5, Left: 6, Right: 7, A: 8, X: 9, L: 10, R: 11
        
        // D-Pad
        gamepad.dpad.up.valueChangedHandler = { _, value, pressed in
            EmulatorCore.shared.setButton(4, pressed: pressed)
        }
        gamepad.dpad.down.valueChangedHandler = { _, value, pressed in
            EmulatorCore.shared.setButton(5, pressed: pressed)
        }
        gamepad.dpad.left.valueChangedHandler = { _, value, pressed in
            EmulatorCore.shared.setButton(6, pressed: pressed)
        }
        gamepad.dpad.right.valueChangedHandler = { _, value, pressed in
            EmulatorCore.shared.setButton(7, pressed: pressed)
        }
        
        // Face Buttons
        gamepad.buttonA.valueChangedHandler = { _, value, pressed in
            EmulatorCore.shared.setButton(8, pressed: pressed) // RetroPad A
        }
        gamepad.buttonB.valueChangedHandler = { _, value, pressed in
            EmulatorCore.shared.setButton(0, pressed: pressed) // RetroPad B
        }
        gamepad.buttonX.valueChangedHandler = { _, value, pressed in
            EmulatorCore.shared.setButton(9, pressed: pressed) // RetroPad X
        }
        gamepad.buttonY.valueChangedHandler = { _, value, pressed in
            EmulatorCore.shared.setButton(1, pressed: pressed) // RetroPad Y
        }
        
        // Shoulders
        gamepad.leftShoulder.valueChangedHandler = { _, value, pressed in
            EmulatorCore.shared.setButton(10, pressed: pressed)
        }
        gamepad.rightShoulder.valueChangedHandler = { _, value, pressed in
            EmulatorCore.shared.setButton(11, pressed: pressed)
        }
        
        // Start / Select (usually mapped to Options and Menu)
        gamepad.buttonOptions?.valueChangedHandler = { _, value, pressed in
            EmulatorCore.shared.setButton(2, pressed: pressed) // Select
        }
        gamepad.buttonMenu.valueChangedHandler = { _, value, pressed in
            EmulatorCore.shared.setButton(3, pressed: pressed) // Start
        }
        
        // Left Analog Stick
        gamepad.leftThumbstick.valueChangedHandler = { _, xValue, yValue in
            let analogX = Int16(xValue * 32767)
            let analogY = Int16(-yValue * 32767)
            EmulatorCore.shared.setAnalog(x: analogX, y: analogY)
        }
    }
}
