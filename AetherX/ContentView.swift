import SwiftUI

struct ContentView: View {
    @StateObject var romManager = ROMManager()
    
    var body: some View {
        TabView {
            HomeView(romManager: romManager)
                .tabItem {
                    Label("Library", systemImage: "gamecontroller.fill")
                }
            
            EmulatorsView(romManager: romManager)
                .tabItem {
                    Label("Emulators", systemImage: "cpu")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .alert(isPresented: $romManager.showingAlert) {
            Alert(
                title: Text(romManager.alertTitle),
                message: Text(romManager.alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

struct HomeView: View {
    @ObservedObject var romManager: ROMManager
    @State private var showingFilePicker = false
    @State private var selectedGame: GameROM?
    @State private var showingJITAlert = false
    @State private var pendingJITGame: GameROM?
    
    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
                
                if romManager.games.isEmpty {
                    VStack {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No Games Found")
                            .font(.title2)
                            .padding(.top)
                        Text("Tap + to import a ROM")
                            .foregroundColor(.gray)
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(romManager.games) { game in
                                Button(action: {
                                    if game.system.contains("Nintendo 64") {
                                        pendingJITGame = game
                                        showingJITAlert = true
                                    } else {
                                        selectedGame = game
                                    }
                                }) {
                                    GameCardView(game: game)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .contextMenu {
                                    Button(role: .destructive, action: {
                                        romManager.deleteROM(game)
                                    }) {
                                        Label("Delete Game", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingFilePicker = true
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                }
            }
            .fullScreenCover(item: $selectedGame) { game in
                NavigationView {
                    EmulatorView(game: game)
                }
            }.fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.data],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    for url in urls {
                        romManager.importROM(from: url)
                    }
                case .failure(let error):
                    print("Error selecting file: \(error.localizedDescription)")
                }
            }
            .alert(isPresented: $showingJITAlert) {
                Alert(
                    title: Text("Coming Soon"),
                    message: Text("Sorry! Nintendo 64 games are currently in the works."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
}

struct EmulatorsView: View {
    @ObservedObject var romManager: ROMManager
    @State private var showingFilePicker = false
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Firmware / BIOS")) {
                    Button(action: {
                        showingFilePicker = true
                    }) {
                        HStack {
                            Text("Import BIOS File")
                            Spacer()
                            Image(systemName: "square.and.arrow.down")
                        }
                    }
                    
                    Button(action: {
                        showingDeleteConfirmation = true
                    }) {
                        HStack {
                            Text("Remove All BIOS Files")
                                .foregroundColor(.red)
                            Spacer()
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                }
                
                Section(header: Text("Console Status")) {
                    ForEach(ConsoleSystem.allCases) { console in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(console.displayName)
                                    .fontWeight(.medium)
                                Spacer()
                                
                                if romManager.biosStatus[console] == true {
                                    Text("Ready ✅")
                                        .foregroundColor(.green)
                                        .font(.subheadline)
                                } else {
                                    Text("Missing BIOS")
                                        .foregroundColor(.red)
                                        .font(.subheadline)
                                }
                            }
                            
                            if !console.requiresBios {
                                Text("No BIOS required")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            } else {
                                let filenames = console.requiredBiosNames.joined(separator: ", ")
                                Text("Requires: \(filenames)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Emulators")
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        romManager.importBIOS(from: url)
                    }
                case .failure(let error):
                    print("Error selecting BIOS file: \(error.localizedDescription)")
                }
            }
            .alert(isPresented: $showingDeleteConfirmation) {
                Alert(
                    title: Text("Remove All BIOS?"),
                    message: Text("Are you sure you want to delete all imported BIOS firmware?"),
                    primaryButton: .destructive(Text("Delete")) {
                        romManager.deleteAllBIOS()
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }
}

struct SettingsView: View {
    @AppStorage("opacity") private var opacity: Double = 0.5
    @AppStorage("hapticsEnabled") private var haptics = true
    @AppStorage("showFPS") private var showFPS = false
    @AppStorage("crtShader") private var crtShader = false
    @AppStorage("aspectRatio") private var aspectRatio = 0
    @AppStorage("audioSync") private var audioSync = true
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Controller Settings")) {
                    VStack(alignment: .leading) {
                        Text("On-Screen Opacity")
                        Slider(value: $opacity, in: 0.1...1.0)
                    }
                    Toggle("Haptic Feedback", isOn: $haptics)
                }
                
                Section(header: Text("Video Settings")) {
                    Toggle("Show FPS", isOn: $showFPS)
                    Toggle("CRT Scanline Shader", isOn: $crtShader)
                    Picker("Aspect Ratio", selection: $aspectRatio) {
                        Text("4:3 (Original)").tag(0)
                        Text("16:9 (Widescreen)").tag(1)
                        Text("Stretch to Fill").tag(2)
                    }
                }
                
                Section(header: Text("Audio Settings")) {
                    Toggle("Enable Audio Sync", isOn: .constant(true))
                }
                
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0").foregroundColor(.gray)
                    }
                    HStack {
                        Text("Developer")
                        Spacer()
                        Text("Leviidev").foregroundColor(.gray)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

struct GameCardView: View {
    let game: GameROM
    
    var body: some View {
        VStack {
            ZStack {
                Color.white.opacity(0.5)
                
                if let path = game.boxArtPath, let uiImage = UIImage(contentsOfFile: path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: 150)
                        .clipped()
                } else {
                    Image(systemName: "gamecontroller.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .foregroundColor(.accentColor)
                }
            }
            .frame(height: 150)
            .glassmorphic(cornerRadius: 15)
            
            Text(game.name)
                .font(.headline)
                .lineLimit(1)
                .padding(.top, 5)
            
            Text(game.system.split(separator: "-").first?.trimmingCharacters(in: .whitespaces) ?? game.system)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(10)
        .glassmorphic(cornerRadius: 20)
    }
}
