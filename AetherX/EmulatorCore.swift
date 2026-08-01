import Foundation
import CoreGraphics
import Combine
import AVFoundation
import QuartzCore

class EmulatorCore: ObservableObject {
    static let shared = EmulatorCore()
    
    @Published var currentFrame: CGImage?
    @Published var currentFPS: String = "60 FPS"
    
    private var displayLink: CADisplayLink?
    private var isRunning = false
    private var currentGame: GameROM?
    
    // FPS Tracking
    private var frameCount = 0
    private var lastFPSUpdateTime: TimeInterval = 0
    
    // Audio State
    private var audioEngine: AVAudioEngine!
    private var audioPlayerNode: AVAudioPlayerNode!
    private var audioFormat: AVAudioFormat!
    
    // The C-callbacks must be static or global. We route them to this singleton.
    
    init() {
        setupAudioEngine()
        setupCallbacks()
    }
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        audioPlayerNode = AVAudioPlayerNode()
        audioEngine.attach(audioPlayerNode)
        
        // Libretro commonly uses 44100Hz or 48000Hz stereo 16-bit PCM.
        // We will default to 44100Hz stereo for now.
        audioFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 44100, channels: 2, interleaved: true)
        
        audioEngine.connect(audioPlayerNode, to: audioEngine.mainMixerNode, format: audioFormat)
        
        do {
            try audioEngine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    private func setupCallbacks() {
        lb_set_video_callback { data, width, height, pitch in
            EmulatorCore.shared.handleVideoFrame(data: data, width: width, height: height, pitch: pitch)
        }
        
        lb_set_audio_callback { left, right in
            EmulatorCore.shared.handleAudioSample(left: left, right: right)
        }
    }
    
    func start(game: GameROM) {
        guard !isRunning else { return }
        self.currentGame = game
        
        ConsoleLogger.shared.writeLog("Starting game: \(game.name) for system: \(game.system)")
        
        // Determine core system
        let systemType: LBNESystem
        let coreFilename: String
        
        if game.system.contains("PlayStation") {
            systemType = LBSystem_PS1
            coreFilename = "pcsx_rearmed_libretro_ios.core"
        } else if game.system.contains("Nintendo 64") {
            systemType = LBN64
            coreFilename = "mupen64plus_next_libretro_ios.core"
        } else if game.system.contains("Game Boy Advance") {
            systemType = LBGBA
            coreFilename = "mgba_libretro_ios.core"
        } else if game.system.contains("Genesis") {
            systemType = LBGenesis
            coreFilename = "genesis_plus_gx_libretro_ios.core"
        } else if game.system.contains("Nintendo DS") {
            systemType = LBNDS
            coreFilename = "melonds_libretro_ios.core"
        } else {
            systemType = LBSNES
            coreFilename = "snes9x_libretro_ios.core"
        }
        
        // Resolve path to the compiled core in the app bundle (embedded as raw resource)
        // Since it might be nested in a Cores/ folder reference, we recursively search for it.
        var bundleCorePath: String? = nil
        if let enumerator = FileManager.default.enumerator(atPath: Bundle.main.bundlePath) {
            for case let path as String in enumerator {
                if path.hasSuffix(coreFilename) {
                    bundleCorePath = Bundle.main.bundlePath + "/" + path
                    break
                }
            }
        }
        
        guard let bundleCorePath = bundleCorePath else {
            ConsoleLogger.shared.writeLog("ERROR: Could not find core \(coreFilename) in bundle recursively!")
            return
        }
        
        ConsoleLogger.shared.writeLog("Found core in bundle at: \(bundleCorePath)")
        
        // We load the core directly from the read-only App Bundle because iOS 15+ 
        // blocks dynamic loading of executables from writable directories like Documents.
        let corePath = bundleCorePath
        
        // We'll need to set the Libretro system directory to our Documents/BIOS folder if the core supports it,
        // but for now we just load the ROM.
        let sysDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("BIOS").path
        
        ConsoleLogger.shared.writeLog("Initializing core at: \(corePath) with sysDir: \(sysDir)")
        let initResult = lb_init(systemType, corePath, sysDir)
        if initResult != LBError_None {
            ConsoleLogger.shared.writeLog("ERROR: Failed to init core! LBError code: \(initResult.rawValue)")
            return
        }
        
        ConsoleLogger.shared.writeLog("Core initialized. Loading ROM from: \(game.fileURL.path)")
        
        let loadResult = lb_load_rom(game.fileURL.path)
        if loadResult != LBError_None {
            ConsoleLogger.shared.writeLog("ERROR: Failed to load ROM!")
            return
        }
        
        ConsoleLogger.shared.writeLog("Game loaded successfully. Loading SRAM if exists...")
        loadSRAM()
        
        audioPlayerNode.play()
        
        displayLink = CADisplayLink(target: self, selector: #selector(runFrame))
        displayLink?.add(to: .current, forMode: .default)
        isRunning = true
    }
    
    func stop() {
        isRunning = false
        displayLink?.invalidate()
        displayLink = nil
        audioPlayerNode.stop()
        
        saveSRAM()
        lb_destroy()
        
        currentFrame = nil
        currentFPS = "0 FPS"
        currentGame = nil
    }
    
    // MARK: - Save States & SRAM
    
    private func saveDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let saveDir = docs.appendingPathComponent("Saves")
        if !FileManager.default.fileExists(atPath: saveDir.path) {
            try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        }
        return saveDir
    }

    func saveState() {
        guard let game = currentGame else { return }
        let path = saveDirectory().appendingPathComponent("\(game.name).state").path
        let success = lb_save_state(path)
        ConsoleLogger.shared.writeLog(success ? "Saved state to \(path)" : "Failed to save state")
    }
    
    func loadState() {
        guard let game = currentGame else { return }
        let path = saveDirectory().appendingPathComponent("\(game.name).state").path
        let success = lb_load_state(path)
        ConsoleLogger.shared.writeLog(success ? "Loaded state from \(path)" : "Failed to load state")
    }

    func saveSRAM() {
        guard let game = currentGame else { return }
        let path = saveDirectory().appendingPathComponent("\(game.name).srm").path
        let success = lb_save_sram(path)
        ConsoleLogger.shared.writeLog(success ? "Saved SRAM to \(path)" : "Failed to save SRAM (or unsupported by core)")
    }
    
    private func loadSRAM() {
        guard let game = currentGame else { return }
        let path = saveDirectory().appendingPathComponent("\(game.name).srm").path
        let success = lb_load_sram(path)
        ConsoleLogger.shared.writeLog(success ? "Loaded SRAM from \(path)" : "No SRAM found or loaded")
    }
    
    func setButton(_ button: Int32, pressed: Bool) {
        // We pass port 0 for Player 1
        lb_set_button_state(0, UInt32(button), pressed)
    }
    
    func setAnalog(x: Int16, y: Int16) {
        lb_set_analog_state(0, x, y)
    }
    
    @objc private func runFrame() {
        if !lb_run_frame() {
            stop()
        }
        
        // Calculate FPS
        frameCount += 1
        let now = CACurrentMediaTime()
        if now - lastFPSUpdateTime >= 1.0 {
            DispatchQueue.main.async {
                self.currentFPS = "\(self.frameCount) FPS"
                self.frameCount = 0
                self.lastFPSUpdateTime = now
            }
        }
    }
    
    // MARK: - Video Handling
    
    private func handleVideoFrame(data: UnsafeRawPointer?, width: UInt32, height: UInt32, pitch: Int) {
        guard let data = data, width > 0, height > 0 else { return }
        
        // The C-Bridge automatically converts 16-bit (0RGB1555, RGB565) to 32-bit XRGB8888
        // before passing it to this callback. So we ALWAYS read it as 32-bit XRGB8888.
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: UInt32 = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
        let bpc = 8
        let bpp = 32
        
        guard let provider = CGDataProvider(data: Data(bytes: data, count: Int(height) * pitch) as CFData) else { return }
        
        let cgImage = CGImage(width: Int(width),
                              height: Int(height),
                              bitsPerComponent: bpc,
                              bitsPerPixel: bpp,
                              bytesPerRow: pitch,
                              space: colorSpace,
                              bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                              provider: provider,
                              decode: nil,
                              shouldInterpolate: false,
                              intent: .defaultIntent)
        
        DispatchQueue.main.async {
            self.currentFrame = cgImage
        }
    }
    
    // MARK: - Audio Handling
    
    private var sampleBuffer = [Int16]()
    private let sampleBatchSize = 1024 * 2 // 1024 frames of Stereo (Left+Right)
    
    private func handleAudioSample(left: Int16, right: Int16) {
        sampleBuffer.append(left)
        sampleBuffer.append(right)
        
        if sampleBuffer.count >= sampleBatchSize {
            scheduleAudioBuffer()
        }
    }
    
    private func scheduleAudioBuffer() {
        guard let format = audioFormat,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleBuffer.count / 2)) else {
            sampleBuffer.removeAll(keepingCapacity: true)
            return
        }
        
        pcmBuffer.frameLength = pcmBuffer.frameCapacity
        
        let channels = Int(format.channelCount)
        if let channelData = pcmBuffer.int16ChannelData {
            // AVAudioPCMBuffer for interleaved format expects data in a single array pointed to by channelData[0]
            let bufferPointer = UnsafeMutableBufferPointer(start: channelData[0], count: sampleBuffer.count)
            _ = bufferPointer.initialize(from: sampleBuffer)
        }
        
        audioPlayerNode.scheduleBuffer(pcmBuffer, completionHandler: nil)
        sampleBuffer.removeAll(keepingCapacity: true)
    }
}
