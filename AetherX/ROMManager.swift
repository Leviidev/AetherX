import Foundation
import Combine
import SwiftUI

struct GameROM: Identifiable, Codable {
    var id = UUID()
    var filename: String
    var name: String
    var system: String
    var boxArtPath: String?
    
    var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("ROMs").appendingPathComponent(filename)
    }
}

enum ConsoleSystem: String, CaseIterable, Identifiable {
    case ps1 = "Sony - PlayStation"
    case snes = "Nintendo - Super Nintendo Entertainment System"
    case gba = "Nintendo - Game Boy Advance"
    case nds = "Nintendo - Nintendo DS"
    case n64 = "Nintendo - Nintendo 64"
    case genesis = "Sega - Mega Drive - Genesis"
    case dreamcast = "Sega - Dreamcast"
    case psp = "Sony - PlayStation Portable"
    case nes = "Nintendo - Nintendo Entertainment System"
    case gbc = "Nintendo - Game Boy Color"
    case arcade = "Arcade Games"
    case segacd = "Sega - Mega-CD - Sega CD"
    
    var id: String { self.rawValue }
    
    var displayName: String {
        switch self {
        case .ps1: return "PlayStation (PS1)"
        case .snes: return "Super Nintendo (SNES)"
        case .gba: return "Game Boy Advance"
        case .nds: return "Nintendo DS"
        case .n64: return "Nintendo 64"
        case .genesis: return "Sega Genesis"
        case .dreamcast: return "Sega Dreamcast"
        case .psp: return "PlayStation Portable"
        case .nes: return "Nintendo Entertainment System"
        case .gbc: return "Game Boy Color"
        case .arcade: return "Arcade"
        case .segacd: return "Sega CD"
        }
    }
    
    var requiredBiosNames: [String] {
        switch self {
        case .ps1: return ["scph5500.bin", "scph5501.bin", "scph5502.bin", "scph1001.bin"]
        case .snes: return []
        case .gba: return ["gba_bios.bin"]
        case .nds: return ["bios7.bin", "bios9.bin", "firmware.bin"]
        case .n64: return []
        case .genesis: return []
        case .dreamcast: return ["dc_boot.bin"]
        case .psp: return []
        case .nes: return []
        case .gbc: return []
        case .arcade: return []
        case .segacd: return ["bios_CD_U.bin", "bios_CD_E.bin", "bios_CD_J.bin"]
        }
    }
    
    var requiresBios: Bool {
        return !requiredBiosNames.isEmpty
    }
}

class ROMManager: ObservableObject {
    @Published var games: [GameROM] = []
    @Published var biosStatus: [ConsoleSystem: Bool] = [:]
    
    @Published var showingAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""
    
    private let fileManager = FileManager.default
    
    init() {
        createDirectories()
        scanROMs()
        checkAllBiosStatus()
    }
    
    func createDirectories() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let romsDir = docs.appendingPathComponent("ROMs")
        let biosDir = docs.appendingPathComponent("BIOS")
        let boxartDir = docs.appendingPathComponent("Boxarts")
        
        try? fileManager.createDirectory(at: romsDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: biosDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: boxartDir, withIntermediateDirectories: true)
    }
    
    func scanROMs() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let romsDir = docs.appendingPathComponent("ROMs")
        
        guard let files = try? fileManager.contentsOfDirectory(atPath: romsDir.path) else { return }
        
        var foundGames: [GameROM] = []
        let cueFiles = files.filter { $0.lowercased().hasSuffix(".cue") }
        let cueBasenames = cueFiles.map { ($0 as NSString).deletingPathExtension.lowercased() }
        
        for file in files {
            if file.hasPrefix(".") { continue }
            
            let ext = (file as NSString).pathExtension.lowercased()
            
            // Skip .bin if a .cue with the same basename exists
            if ext == "bin" {
                let basename = (file as NSString).deletingPathExtension.lowercased()
                if cueBasenames.contains(basename) {
                    continue
                }
            }
            
            let system = determineSystemString(from: ext)
            if system == "Unknown" { continue }
            
            let name = (file as NSString).deletingPathExtension
            
            let boxartDir = docs.appendingPathComponent("Boxarts")
            let expectedBoxart = boxartDir.appendingPathComponent("\(name).png")
            let hasBoxArt = fileManager.fileExists(atPath: expectedBoxart.path)
            
            let game = GameROM(
                filename: file,
                name: name,
                system: system,
                boxArtPath: hasBoxArt ? expectedBoxart.path : nil
            )
            foundGames.append(game)
            
            if !hasBoxArt {
                fetchBoxArt(for: game)
            }
        }
        
        DispatchQueue.main.async {
            self.games = foundGames.sorted { $0.name < $1.name }
        }
    }
    
    func importROM(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let romsDir = docs.appendingPathComponent("ROMs")
        let destination = romsDir.appendingPathComponent(url.lastPathComponent)
        
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: url, to: destination)
            scanROMs()
        } catch {
            print("Failed to import ROM: \(error.localizedDescription)")
        }
    }
    
    func deleteROM(_ game: GameROM) {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let romsDir = docs.appendingPathComponent("ROMs")
        let boxartDir = docs.appendingPathComponent("Boxarts")
        
        // Delete the main ROM file
        let fileURL = romsDir.appendingPathComponent(game.filename)
        try? fileManager.removeItem(at: fileURL)
        
        // Also delete associated .cue or .bin if they exist
        let baseName = (game.filename as NSString).deletingPathExtension
        let possibleCue = romsDir.appendingPathComponent("\(baseName).cue")
        let possibleBin = romsDir.appendingPathComponent("\(baseName).bin")
        try? fileManager.removeItem(at: possibleCue)
        try? fileManager.removeItem(at: possibleBin)
        
        // Delete box art if it exists
        if let boxArtPath = game.boxArtPath {
            try? fileManager.removeItem(atPath: boxArtPath)
        } else {
            let possibleBoxArt = boxartDir.appendingPathComponent("\(game.name).png")
            try? fileManager.removeItem(at: possibleBoxArt)
        }
        
        scanROMs()
    }
    
    func renameROM(_ game: GameROM, to newName: String) {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let romsDir = docs.appendingPathComponent("ROMs")
        let boxartDir = docs.appendingPathComponent("Boxarts")
        
        let oldBaseName = (game.filename as NSString).deletingPathExtension
        let ext = (game.filename as NSString).pathExtension
        
        // Rename the primary file
        let oldURL = romsDir.appendingPathComponent(game.filename)
        let newURL = romsDir.appendingPathComponent("\(newName).\(ext)")
        try? fileManager.moveItem(at: oldURL, to: newURL)
        
        // Rename associated .cue or .bin
        let oldCue = romsDir.appendingPathComponent("\(oldBaseName).cue")
        let newCue = romsDir.appendingPathComponent("\(newName).cue")
        if fileManager.fileExists(atPath: oldCue.path) {
            try? fileManager.moveItem(at: oldCue, to: newCue)
        }
        
        let oldBin = romsDir.appendingPathComponent("\(oldBaseName).bin")
        let newBin = romsDir.appendingPathComponent("\(newName).bin")
        if fileManager.fileExists(atPath: oldBin.path) {
            try? fileManager.moveItem(at: oldBin, to: newBin)
        }
        
        // Delete old boxart (it will be refetched by scanROMs with the new name)
        if let boxArtPath = game.boxArtPath {
            try? fileManager.removeItem(atPath: boxArtPath)
        } else {
            let possibleBoxArt = boxartDir.appendingPathComponent("\(game.name).png")
            try? fileManager.removeItem(at: possibleBoxArt)
        }
        
        scanROMs()
    }
    
    // MARK: - BIOS Management
    
    func checkAllBiosStatus() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let biosDir = docs.appendingPathComponent("BIOS")
        
        guard let files = try? fileManager.contentsOfDirectory(atPath: biosDir.path) else { return }
        
        var newStatus: [ConsoleSystem: Bool] = [:]
        
        for console in ConsoleSystem.allCases {
            if !console.requiresBios {
                newStatus[console] = true
                continue
            }
            
            // For consoles with multiple required files (like NDS), we should check if they have at least one or all.
            // For PS1, they just need ONE of the valid ones.
            // For NDS, they typically need all 3.
            if console == .nds {
                let hasAll = console.requiredBiosNames.allSatisfy { requiredName in
                    files.contains { $0.lowercased() == requiredName.lowercased() }
                }
                newStatus[console] = hasAll
            } else {
                let hasValidBios = files.contains { file in
                    console.requiredBiosNames.contains(file.lowercased())
                }
                newStatus[console] = hasValidBios
            }
        }
        
        DispatchQueue.main.async {
            self.biosStatus = newStatus
        }
    }
    
    func importBIOS(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        
        let ext = url.pathExtension.lowercased()
        let validBiosExtensions = ["bin", "rom", "sys", "img", "zip"]
        
        if !validBiosExtensions.contains(ext) {
            DispatchQueue.main.async {
                self.alertTitle = "Invalid BIOS File"
                self.alertMessage = "The file type '.\(ext)' is not a recognized BIOS format. The file has been discarded."
                self.showingAlert = true
            }
            return
        }
        
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let biosDir = docs.appendingPathComponent("BIOS")
        let destination = biosDir.appendingPathComponent(url.lastPathComponent)
        
        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: url, to: destination)
            checkAllBiosStatus()
            
            DispatchQueue.main.async {
                self.alertTitle = "Success"
                self.alertMessage = "BIOS file '\(url.lastPathComponent)' imported successfully."
                self.showingAlert = true
            }
        } catch {
            print("Failed to import BIOS: \(error.localizedDescription)")
        }
    }
    
    func deleteAllBIOS() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let biosDir = docs.appendingPathComponent("BIOS")
        
        guard let files = try? fileManager.contentsOfDirectory(atPath: biosDir.path) else { return }
        for file in files {
            let fileURL = biosDir.appendingPathComponent(file)
            try? fileManager.removeItem(at: fileURL)
        }
        checkAllBiosStatus()
    }
    
    // MARK: - Helpers
    
    private func determineSystemString(from ext: String) -> String {
        switch ext {
        case "smc", "sfc": return ConsoleSystem.snes.rawValue
        case "bin", "cue": return ConsoleSystem.ps1.rawValue // Overlaps with Sega CD, defaulting to PS1
        case "iso", "cso": return ConsoleSystem.psp.rawValue
        case "nes": return ConsoleSystem.nes.rawValue
        case "gb", "gbc": return ConsoleSystem.gbc.rawValue
        case "zip": return ConsoleSystem.arcade.rawValue
        case "cdi", "gdi", "chd": return ConsoleSystem.dreamcast.rawValue // CHD overlaps with Sega CD / PS1
        case "gba": return ConsoleSystem.gba.rawValue
        case "nds": return ConsoleSystem.nds.rawValue
        case "n64", "z64", "v64": return ConsoleSystem.n64.rawValue
        case "md", "smd", "gen": return ConsoleSystem.genesis.rawValue
        default: return "Unknown"
        }
    }
    
    private func fetchBoxArt(for game: GameROM) {
        guard let encodedSystem = game.system.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let encodedName = game.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://thumbnails.libretro.com/\(encodedSystem)/Named_Boxarts/\(encodedName).png") else {
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil, let resp = response as? HTTPURLResponse, resp.statusCode == 200 else {
                return
            }
            
            let docs = self.fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let boxartDir = docs.appendingPathComponent("Boxarts")
            let destination = boxartDir.appendingPathComponent("\(game.name).png")
            
            do {
                try data.write(to: destination)
                DispatchQueue.main.async {
                    self.scanROMs()
                }
            } catch {
                print("Failed to save boxart: \(error.localizedDescription)")
            }
        }.resume()
    }
}
