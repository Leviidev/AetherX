import Foundation
import UIKit

/// Drives the MeloNX (LibRyujinx) Nintendo Switch engine.
/// Lifetime: one instance per Switch game session.
final class SwitchEmulatorCore: ObservableObject {

    // ── Published state ───────────────────────────────────────────────────────
    @Published var status: String = "Initializing…"
    @Published var isRunning: Bool = false
    @Published var errorMessage: String? = nil

    // ── Singleton ─────────────────────────────────────────────────────────────
    static let shared = SwitchEmulatorCore()
    private init() {}

    // ── Private state ─────────────────────────────────────────────────────────
    private var renderThread: Thread?
    private var viewportSize: CGSize = .zero

    // ── Public API ────────────────────────────────────────────────────────────

    func start(game: GameROM, viewportSize: CGSize) {
        guard !isRunning else { return }
        self.viewportSize = viewportSize

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.bootSequence(game: game)
        }
    }

    func stop() {
        isRunning = false
    }

    // ── Internal boot sequence ────────────────────────────────────────────────

    private func bootSequence(game: GameROM) {
        updateStatus("Loading MeloNX engine…")

        // 1. Load the dylib at runtime
        guard melonx_load_library() else {
            fail("Failed to load LibRyujinx.dylib. Make sure it is embedded in the app bundle.")
            return
        }

        // 2. Initialize the engine with our Documents directory as base path
        let basePath = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .path
        guard melonx_initialize(basePath) else {
            fail("LibRyujinx initialize() returned false.")
            return
        }
        updateStatus("Engine loaded. Initializing device…")

        // 3. Initialize the virtual Switch device
        guard melonx_device_initialize() else {
            fail("device_initialize() failed. Check that prod.keys and firmware are installed.")
            return
        }
        updateStatus("Device ready. Starting graphics…")

        // 4. Set up graphics (OpenGL backend for now; Vulkan/MoltenVK later)
        let w = Int32(viewportSize.width)
        let h = Int32(viewportSize.height)
        guard melonx_graphics_initialize(w, h) else {
            fail("graphics_initialize() failed.")
            return
        }

        // 5. Initialize input
        _ = melonx_input_initialize(w, h)

        // 6. Load the ROM
        updateStatus("Loading game…")
        guard melonx_device_load(game.fileURL.path) else {
            fail("device_load() failed. The ROM may be corrupt or unsupported.")
            return
        }

        updateStatus("Running!")
        DispatchQueue.main.async { [weak self] in
            self?.isRunning = true
        }

        // 7. Run the GPU loop (blocks this background thread)
        melonx_graphics_run_loop()

        // If we return here, the game has exited
        DispatchQueue.main.async { [weak self] in
            self?.isRunning = false
            self?.status = "Game exited."
        }
    }

    // ── Input forwarding ──────────────────────────────────────────────────────

    func sendTouch(at point: CGPoint) {
        melonx_input_set_touch_point(Int32(point.x), Int32(point.y))
        melonx_input_update()
    }

    func releaseTouch() {
        melonx_input_release_touch_point()
        melonx_input_update()
    }

    /// SwitchButton layout maps to LibRyujinx's NpadButton bitmask indices.
    func buttonDown(_ button: SwitchButton) {
        melonx_input_button_pressed(button.rawValue, 0)
        melonx_input_update()
    }

    func buttonUp(_ button: SwitchButton) {
        melonx_input_button_released(button.rawValue, 0)
        melonx_input_update()
    }

    func setStick(left: CGPoint) {
        melonx_input_set_stick_axis(0, Float(left.x), Float(left.y), 0)
        melonx_input_update()
    }

    func setRightStick(right: CGPoint) {
        melonx_input_set_stick_axis(1, Float(right.x), Float(right.y), 0)
        melonx_input_update()
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private func updateStatus(_ msg: String) {
        DispatchQueue.main.async { [weak self] in
            self?.status = msg
        }
    }

    private func fail(_ msg: String) {
        DispatchQueue.main.async { [weak self] in
            self?.errorMessage = msg
            self?.isRunning = false
        }
    }
}

// ── Switch Button Enum (NpadButton bitmask positions) ─────────────────────────
enum SwitchButton: Int32 {
    case a         = 0
    case b         = 1
    case x         = 2
    case y         = 3
    case leftStick = 4
    case rightStick = 5
    case l         = 6
    case r         = 7
    case zl        = 8
    case zr        = 9
    case plus      = 10
    case minus     = 11
    case dpadLeft  = 12
    case dpadUp    = 13
    case dpadRight = 14
    case dpadDown  = 15
}
