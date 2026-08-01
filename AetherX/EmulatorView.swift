import SwiftUI

struct EmulatorView: View {
    let game: GameROM
    
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.dismiss) var dismiss
    @StateObject private var core = EmulatorCore.shared
    @AppStorage("showFPS") private var showFPS: Bool = false
    @State private var showingLogs = false
    @State private var showingMenu = false
    
    var body: some View {
        if game.system == ConsoleSystem.switchConsole.rawValue {
            SwitchStubView(game: game)
        } else {
            ZStack {
                Color.black.ignoresSafeArea()
            
            if verticalSizeClass == .regular {
                // Portrait Layout: Split-Screen exactly 50/50
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        ZStack(alignment: .topTrailing) {
                            GameSurfacePlaceholder(frame: core.currentFrame)
                                .frame(width: geo.size.width, height: geo.size.height / 2)
                                .background(Color.black)
                            
                            if showFPS {
                                Text(core.currentFPS)
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.green)
                                    .padding(4)
                                    .background(Color.black.opacity(0.5))
                                    .cornerRadius(4)
                                    .padding()
                                    .padding(.top, 40) // avoid notch
                            }
                        }
                        
                        TouchControllerView()
                            .frame(width: geo.size.width, height: geo.size.height / 2)
                    }
                }
            } else {
                // Landscape Layout: Full screen game with overlay controls
                ZStack(alignment: .topTrailing) {
                    GameSurfacePlaceholder(frame: core.currentFrame)
                        .ignoresSafeArea()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    if showFPS {
                        Text(core.currentFPS)
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.green)
                            .padding(4)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(4)
                            .padding()
                            .padding(.top, 40) // avoid notch
                    }
                    
                    HStack {
                        VStack(spacing: 30) {
                            DPadView()
                            JoystickView()
                        }
                        .padding(.leading, 40)
                        
                        Spacer()
                        
                        ActionButtonsView()
                            .padding(.trailing, 40)
                    }
                    
                    VStack {
                        Spacer()
                        HStack {
                            ControlButton(title: "Select", shape: .capsule, buttonId: 2)
                            Spacer()
                            ControlButton(title: "Start", shape: .capsule, buttonId: 3)
                        }
                        .padding(.horizontal, 150)
                        .padding(.bottom, 20)
                    }
                    
                    VStack {
                        HStack {
                            ControlButton(title: "L", shape: .capsule, buttonId: 10)
                            Spacer()
                            ControlButton(title: "R", shape: .capsule, buttonId: 11)
                        }
                        .padding(.horizontal, 40)
                        .padding(.top, 20)
                        Spacer()
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar) // Hide the bottom tab bar!
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    dismiss()
                }) {
                    Text("Close")
                        .foregroundColor(.red)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingMenu = true
                }) {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.white)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingLogs = true
                }) {
                    Image(systemName: "list.clipboard")
                        .foregroundColor(.white)
                }
            }
        }
        .confirmationDialog("Emulator Menu", isPresented: $showingMenu, titleVisibility: .visible) {
            Button("Save State") {
                core.saveState()
            }
            Button("Load State") {
                core.loadState()
            }
            Button("Save Game Data (SRAM)") {
                core.saveSRAM()
            }
            Button("Cancel", role: .cancel) { }
        }
        .sheet(isPresented: $showingLogs) {
            LogView()
        }
            .onAppear {
                core.start(game: game)
            }
            .onDisappear {
                core.stop()
            }
        }
    }
}

struct SwitchStubView: View {
    let game: GameROM
    @Environment(\.dismiss) var dismiss
    @StateObject private var core = SwitchEmulatorCore.shared

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if core.isRunning {
                    VStack(spacing: 0) {
                        // Game surface – MeloNX renders here via CAMetalLayer
                        ZStack {
                            Color.black
                                .frame(width: geo.size.width, height: geo.size.height * 0.55)
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { v in core.sendTouch(at: v.location) }
                                        .onEnded { _ in core.releaseTouch() }
                                )
                            Text("🕹 Switch surface active")
                                .foregroundColor(.gray.opacity(0.3))
                                .font(.caption)
                        }
                        // Controller overlay
                        SwitchControllerView(core: core)
                            .frame(width: geo.size.width, height: geo.size.height * 0.45)
                    }

                } else if let err = core.errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.orange)
                        Text("Launch Failed")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        Text(err)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                        Button("Dismiss") { dismiss() }
                            .foregroundColor(.red)
                    }

                } else {
                    // Loading state
                    VStack(spacing: 24) {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.1), lineWidth: 4)
                                .frame(width: 80, height: 80)
                            Circle()
                                .trim(from: 0, to: 0.7)
                                .stroke(
                                    LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                                )
                                .frame(width: 80, height: 80)
                                .rotationEffect(.degrees(-90))
                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                        }
                        Text(game.name)
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(core.status)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
            .onAppear {
                core.start(game: game, viewportSize: geo.size)
            }
            .onDisappear {
                core.stop()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Close") { dismiss() }
                    .foregroundColor(.red)
            }
        }
    }
}

// ── Nintendo Switch controller overlay ───────────────────────────────────────
struct SwitchControllerView: View {
    let core: SwitchEmulatorCore

    var body: some View {
        ZStack {
            Color(white: 0.08)
            HStack {
                // Left Joy-Con
                VStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Spacer()
                        SwitchBtn(label: "↑", core: core, btn: .dpadUp)
                        Spacer()
                    }
                    HStack(spacing: 4) {
                        SwitchBtn(label: "←", core: core, btn: .dpadLeft)
                        SwitchBtn(label: "↓", core: core, btn: .dpadDown)
                        SwitchBtn(label: "→", core: core, btn: .dpadRight)
                    }
                    HStack(spacing: 8) {
                        SwitchBtn(label: "−", core: core, btn: .minus)
                        SwitchBtn(label: "ZL", core: core, btn: .zl)
                        SwitchBtn(label: "L",  core: core, btn: .l)
                    }
                }
                .padding(.leading, 20)

                Spacer()

                // Right Joy-Con
                VStack(spacing: 12) {
                    HStack { Spacer(); SwitchBtn(label: "X", core: core, btn: .x); Spacer() }
                    HStack(spacing: 4) {
                        SwitchBtn(label: "Y", core: core, btn: .y)
                        SwitchBtn(label: "A", core: core, btn: .a)
                    }
                    HStack { Spacer(); SwitchBtn(label: "B", core: core, btn: .b); Spacer() }
                    HStack(spacing: 8) {
                        SwitchBtn(label: "R",  core: core, btn: .r)
                        SwitchBtn(label: "ZR", core: core, btn: .zr)
                        SwitchBtn(label: "+",  core: core, btn: .plus)
                    }
                }
                .padding(.trailing, 20)
            }
        }
    }
}

struct SwitchBtn: View {
    let label: String
    let core: SwitchEmulatorCore
    let btn: SwitchButton
    @State private var pressed = false

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 42, height: 42)
            .background(pressed ? Color.red.opacity(0.7) : Color.white.opacity(0.15))
            .clipShape(Circle())
            .scaleEffect(pressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.2), value: pressed)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressed { pressed = true; core.buttonDown(btn) }
                    }
                    .onEnded { _ in
                        pressed = false; core.buttonUp(btn)
                    }
            )
    }
}


struct GameSurfacePlaceholder: View {
    var frame: CGImage?
    
    @AppStorage("crtShader") private var crtShader = false
    @AppStorage("aspectRatio") private var aspectRatio = 0
    @AppStorage("pixelPerfect") private var pixelPerfect = true
    
    var body: some View {
        let ratio: CGFloat = (aspectRatio == 1) ? 16/9 : 4/3
        let mode: ContentMode = (aspectRatio == 2) ? .fill : .fit
        
        Group {
            if let cgImage = frame {
                Image(cgImage, scale: 1.0, orientation: .up, label: Text("Game View"))
                    .resizable()
                    .interpolation(pixelPerfect ? .none : .high)
                    .aspectRatio(aspectRatio == 2 ? nil : ratio, contentMode: mode)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .aspectRatio(aspectRatio == 2 ? nil : ratio, contentMode: mode)
                    .overlay(
                        Text("Loading Core...")
                            .foregroundColor(.white)
                    )
            }
        }
        .overlay(
            Group {
                if crtShader {
                    ScanlineOverlay()
                }
            }
        )
        .clipped()
    }
}

struct ScanlineOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                for y in stride(from: 0, to: geo.size.height, by: 3) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
            }
            .stroke(Color.black.opacity(0.25), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

struct TouchControllerView: View {
    var body: some View {
        VStack(spacing: 5) {
            // L (10) and R (11)
            HStack {
                ControlButton(title: "L", shape: .capsule, buttonId: 10)
                Spacer()
                ControlButton(title: "R", shape: .capsule, buttonId: 11)
            }
            .padding(.horizontal, 30)
            
            HStack {
                VStack(spacing: 5) {
                    DPadView()
                    JoystickView()
                }
                Spacer()
                ActionButtonsView()
                    .padding(.trailing, 20)
            }
            .padding(.horizontal, 20)
            
            // Select (2) and Start (3)
            HStack(spacing: 30) {
                ControlButton(title: "Select", shape: .capsule, buttonId: 2)
                ControlButton(title: "Start", shape: .capsule, buttonId: 3)
            }
        }
    }
}

enum ButtonShape {
    case circle
    case capsule
}

struct ControlButton: View {
    let title: String
    let shape: ButtonShape
    let buttonId: Int32
    
    @State private var isPressed = false
    
    var body: some View {
        ZStack {
            if shape == .circle {
                Circle()
                    .fill(Color.white.opacity(isPressed ? 0.4 : 0.2))
                    .frame(width: 46, height: 46)
            } else {
                Capsule()
                    .fill(Color.white.opacity(isPressed ? 0.4 : 0.2))
                    .frame(width: 60, height: 32)
            }
            
            Text(title)
                .font(.footnote).bold()
                .foregroundColor(.white)
        }
        .glassmorphic(cornerRadius: shape == .circle ? 23 : 16)
        .padding(18) // Expands the hit area massively without inflating ZStack footprint due to explicit container bounds
        .background(
            TouchButtonView(
                onTouchDown: {
                    if !isPressed {
                        isPressed = true
                        EmulatorCore.shared.setButton(buttonId, pressed: true)
                    }
                },
                onTouchUp: {
                    isPressed = false
                    EmulatorCore.shared.setButton(buttonId, pressed: false)
                }
            )
        )
    }
}

struct DPadView: View {
    var body: some View {
        ZStack {
            Color.clear.frame(width: 140, height: 140)
            ControlButton(title: "▲", shape: .circle, buttonId: 4) // UP
                .offset(y: -42)
            ControlButton(title: "▼", shape: .circle, buttonId: 5) // DOWN
                .offset(y: 42)
            ControlButton(title: "◀", shape: .circle, buttonId: 6) // LEFT
                .offset(x: -42)
            ControlButton(title: "▶", shape: .circle, buttonId: 7) // RIGHT
                .offset(x: 42)
        }
    }
}

struct ActionButtonsView: View {
    var body: some View {
        ZStack {
            Color.clear.frame(width: 140, height: 140)
            ControlButton(title: "X", shape: .circle, buttonId: 9) // X
                .offset(y: -42)
            ControlButton(title: "B", shape: .circle, buttonId: 0) // B
                .offset(y: 42)
            ControlButton(title: "Y", shape: .circle, buttonId: 1) // Y
                .offset(x: -42)
            ControlButton(title: "A", shape: .circle, buttonId: 8) // A
                .offset(x: 42)
        }
    }
}

struct LogView: View {
    @State private var logText: String = ""
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                Text(logText)
                    .font(.system(size: 10, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle("Console Logs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        UIPasteboard.general.string = logText
                    }) {
                        Image(systemName: "doc.on.doc")
                    }
                }
            }
            .onAppear {
                logText = ConsoleLogger.shared.readLogs()
            }
        }
    }
}

struct JoystickView: View {
    @State private var thumbPosition: CGSize = .zero
    private let maxRadius: CGFloat = 35.0 // Drag distance
    
    var body: some View {
        ZStack {
            // Base
            Circle()
                .fill(Color.white.opacity(0.1))
                .frame(width: 80, height: 80)
                .glassmorphic(cornerRadius: 40)
            
            // Thumb
            Circle()
                .fill(Color.white.opacity(0.8))
                .frame(width: 40, height: 40)
                .shadow(radius: 5)
                .offset(thumbPosition)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let distance = sqrt(pow(value.translation.width, 2) + pow(value.translation.height, 2))
                            let factor = min(maxRadius, distance) / max(distance, 1)
                            let newX = value.translation.width * factor
                            let newY = value.translation.height * factor
                            
                            thumbPosition = CGSize(width: newX, height: newY)
                            
                            let analogX = Int16((newX / maxRadius) * 32767)
                            let analogY = Int16((newY / maxRadius) * 32767)
                            EmulatorCore.shared.setAnalog(x: analogX, y: analogY)
                            
                            // Map joystick to D-pad buttons for older consoles
                            let threshold = maxRadius * 0.4
                            EmulatorCore.shared.setButton(6, pressed: newX < -threshold) // LEFT
                            EmulatorCore.shared.setButton(7, pressed: newX > threshold)  // RIGHT
                            EmulatorCore.shared.setButton(4, pressed: newY < -threshold) // UP
                            EmulatorCore.shared.setButton(5, pressed: newY > threshold)  // DOWN
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                thumbPosition = .zero
                            }
                            EmulatorCore.shared.setAnalog(x: 0, y: 0)
                            
                            // Release D-pad buttons
                            EmulatorCore.shared.setButton(4, pressed: false)
                            EmulatorCore.shared.setButton(5, pressed: false)
                            EmulatorCore.shared.setButton(6, pressed: false)
                            EmulatorCore.shared.setButton(7, pressed: false)
                        }
                )
        }
    }
}

struct TouchButtonView: UIViewRepresentable {
    var onTouchDown: () -> Void
    var onTouchUp: () -> Void

    class TouchView: UIView {
        var onTouchDown: (() -> Void)?
        var onTouchUp: (() -> Void)?

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            onTouchDown?()
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            onTouchUp?()
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            onTouchUp?()
        }
    }

    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        view.isMultipleTouchEnabled = true
        view.isUserInteractionEnabled = true
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: TouchView, context: Context) {
        uiView.onTouchDown = onTouchDown
        uiView.onTouchUp = onTouchUp
    }
}
