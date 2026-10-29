import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct ContentView: View {
    @EnvironmentObject var store: PhraseStore
    @StateObject private var player = AudioPlayerManager.shared
    @StateObject private var notifications = NotificationManager.shared
    @StateObject private var creatorImporter = InstagramCreatorImporter.shared

    @State private var selectedTab: Int = 0
    @State private var selectedCategory: String = "Todas"
    @State private var searchText: String = ""

    // Estado para añadir nueva alarma fija
    @State private var showingAddAlarmSheet = false
    @State private var newAlarmDate = Date()
    @State private var newAlarmLabel = "Alarma Motivadora (Audio Completo)"
    @State private var newAlarmPhraseId: String = "random"

    // Estado para importar un Creador completo poniendo solo su @usuario
    @State private var targetInstagramUsername = ""
    @State private var maxReelsToExtract: Int = 10

    // Estado para importar un Reel/Audio individual desde el iPhone
    @State private var showingFileImporter = false
    @State private var importedQuoteText = ""
    @State private var importedCategory = "Disciplina"
    @State private var importFeedbackMessage = ""

    private let categories = ["Todas", "Favoritas", "Disciplina", "Mentalidad", "Enfoque", "Éxito"]
    private let intervalOptions = [
        (15, "Cada 15 minutos"),
        (30, "Cada 30 minutos"),
        (60, "Cada 1 hora"),
        (120, "Cada 2 horas"),
        (180, "Cada 3 horas"),
        (240, "Cada 4 horas")
    ]

    var filteredPhrases: [MotivationalPhrase] {
        store.phrases.filter { phrase in
            let matchesCategory: Bool = {
                if selectedCategory == "Todas" { return true }
                if selectedCategory == "Favoritas" { return phrase.isFavorite }
                return phrase.category.lowercased() == selectedCategory.lowercased()
            }()
            let matchesSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || phrase.text.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            soundboardTab
                .tabItem {
                    Label("Reels Completos", systemImage: "waveform.circle.fill")
                }
                .tag(0)

            notificationsTab
                .tabItem {
                    Label("Alarmas y Avisos", systemImage: "bell.badge.waveform.fill")
                }
                .tag(1)

            importTab
                .tabItem {
                    Label("Importar Reel", systemImage: "person.crop.rectangle.badge.plus.fill")
                }
                .tag(2)
        }
        .preferredColorScheme(.dark)
        .tint(.orange)
    }

    // MARK: - TAB 1: SOUNDBOARD DE REELS COMPLETOS DEL CREADOR ACTIVO
    private var soundboardTab: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerHeroCard
                    .padding(.horizontal)
                    .padding(.top, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(categories, id: \.self) { category in
                            Button {
                                selectedCategory = category
                            } label: {
                                Text(category)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        selectedCategory == category
                                            ? Color.orange
                                            : Color.white.opacity(0.08)
                                    )
                                    .foregroundColor(selectedCategory == category ? .black : .white)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }

                if !notifications.statusMessage.isEmpty {
                    Text(notifications.statusMessage)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.orange)
                        .padding(.horizontal)
                        .padding(.bottom, 6)
                        .multilineTextAlignment(.center)
                }

                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(filteredPhrases) { phrase in
                            phraseCard(phrase)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
            .background(Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea())
            .navigationTitle("🔥 \(store.activeCreatorHandle)")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Buscar frase de \(store.activeCreatorHandle)...")
        }
    }

    private var headerHeroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MODO AUDIO COMPLETO • \(store.activeCreatorHandle.uppercased())")
                        .font(.caption.weight(.heavy))
                        .foregroundColor(.orange)
                    Text("\(store.phrases.count) Reels enteros • \(notifications.pendingCount) avisos activos")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()
                Button {
                    selectedTab = 2
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Cambiar @")
                    }
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.2))
                    .foregroundColor(.orange)
                    .clipShape(Capsule())
                }
            }

            HStack(spacing: 10) {
                Button {
                    if let randomPhrase = store.phrases.randomElement() {
                        player.play(fileName: randomPhrase.audioFile, forceStartFromBeginning: true)
                    }
                } label: {
                    Label("Reel Completo Aleatorio", systemImage: "shuffle")
                        .font(.footnote.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.orange)
                        .foregroundColor(.black)
                        .cornerRadius(10)
                }

                Button {
                    if let randomPhrase = store.phrases.randomElement() {
                        notifications.sendTestNotification(with: randomPhrase)
                    }
                } label: {
                    Label("Probar Alarma (5s)", systemImage: "bell.and.waves.left.and.right.fill")
                        .font(.footnote.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.12))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                )
        )
    }

    private func phraseCard(_ phrase: MotivationalPhrase) -> some View {
        let isPlayingThis = (player.currentlyPlayingFile == phrase.audioFile && player.isPlaying)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(phrase.category.uppercased())
                    .font(.caption2.weight(.heavy))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.2))
                    .foregroundColor(.orange)
                    .cornerRadius(6)

                Text("AUDIO COMPLETO • \(String(format: "%.1fs", phrase.durationSeconds))")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundColor(.green)

                Spacer()

                Button {
                    store.toggleNotificationEnabled(for: phrase)
                } label: {
                    Image(systemName: phrase.isEnabledForNotifications ? "bell.fill" : "bell.slash")
                        .foregroundColor(phrase.isEnabledForNotifications ? .orange : .gray)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)

                Button {
                    store.toggleFavorite(for: phrase)
                } label: {
                    Image(systemName: phrase.isFavorite ? "star.fill" : "star")
                        .foregroundColor(phrase.isFavorite ? .yellow : .gray)
                }
                .buttonStyle(.plain)
            }

            Text("\"\(phrase.text)\"")
                .font(.body.weight(.medium))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button {
                    player.play(fileName: phrase.audioFile)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isPlayingThis ? "stop.fill" : "play.fill")
                        Text(isPlayingThis ? "Detener (\(String(format: "%.0fs", phrase.durationSeconds)))" : "Escuchar Completo (\(String(format: "%.0fs", phrase.durationSeconds)))")
                            .font(.caption.weight(.bold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(isPlayingThis ? Color.red : Color.orange)
                    .foregroundColor(isPlayingThis ? .white : .black)
                    .cornerRadius(8)
                }

                Button {
                    notifications.sendTestNotification(with: phrase)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.iphone")
                        Text("Sonar en Bloqueo (5s)")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }

                Spacer()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isPlayingThis ? Color.orange : Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    // MARK: - TAB 2: PROGRAMACIÓN DE ALARMAS Y NOTIFICACIONES DE AUDIO COMPLETO
    private var notificationsTab: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: notifications.isAuthorized ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(notifications.isAuthorized ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Creador Activo: \(store.activeCreatorHandle)")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.orange)
                            Text("Motor de Audio Completo: \(player.isBackgroundAlarmEngineActive ? "Activo (Sin límite de 30s)" : "Encadenado por partes")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if !notifications.isAuthorized {
                            Button("Autorizar") {
                                notifications.requestAuthorization()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    Toggle("Sonar Audio Completo sin Cortes (Modo Alarma)", isOn: $store.intervalConfig.fullAudioAlarmMode)
                        .onChange(of: store.intervalConfig.fullAudioAlarmMode) { newVal in
                            player.setBackgroundAlarmEngine(enabled: newVal)
                            store.saveAll()
                        }
                } header: {
                    Text("Motor de Audio Completo en Notificación y Alarma")
                } footer: {
                    Text("Garantiza que cuando salte una notificación o alarma suene el Reel COMPLETO de principio a fin (incluso si dura 60s o 90s), combinando reproducción íntegra en segundo plano y partes encadenadas.")
                }

                Section {
                    Toggle("Activar Notificaciones por Intervalo", isOn: $store.intervalConfig.isEnabled)

                    Picker("Frecuencia", selection: $store.intervalConfig.intervalMinutes) {
                        ForEach(intervalOptions, id: \.0) { mins, label in
                            Text(label).tag(mins)
                        }
                    }

                    Picker("Hora de inicio", selection: $store.intervalConfig.startHour) {
                        ForEach(0..<24, id: \.self) { h in
                            Text(String(format: "%02d:00", h)).tag(h)
                        }
                    }

                    Picker("Hora de fin", selection: $store.intervalConfig.endHour) {
                        ForEach(0..<24, id: \.self) { h in
                            Text(String(format: "%02d:00", h)).tag(h)
                        }
                    }

                    Toggle("Usar solo mis Reels Favoritos ⭐", isOn: $store.intervalConfig.onlyFavorites)
                } header: {
                    Text("1. Notificaciones Periódicas (\(store.activeCreatorHandle))")
                }

                Section {
                    ForEach($store.fixedSchedules) { $alarm in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(alarm.formattedTime)
                                    .font(.title3.monospacedDigit().weight(.bold))
                                    .foregroundColor(.orange)
                                Text(alarm.label)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $alarm.isEnabled)
                                .labelsHidden()
                        }
                    }
                    .onDelete(perform: store.removeFixedAlarm)

                    Button {
                        showingAddAlarmSheet = true
                    } label: {
                        Label("Añadir Alarma con Audio Completo", systemImage: "alarm.waves.left.and.right.fill")
                            .foregroundColor(.orange)
                    }
                } header: {
                    Text("2. Alarmas en Horarios Fijos Diarios")
                }

                Section {
                    Button {
                        store.applyAndScheduleNotifications()
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "bell.badge.waveform.fill")
                            Text("Guardar y Activar Audio Completo")
                                .fontWeight(.bold)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Color.orange)
                    .foregroundColor(.black)

                    if !notifications.statusMessage.isEmpty {
                        Text(notifications.statusMessage)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            .navigationTitle("Alarmas y Avisos")
            .sheet(isPresented: $showingAddAlarmSheet) {
                addFixedAlarmSheet
            }
        }
    }

    private var addFixedAlarmSheet: some View {
        NavigationStack {
            Form {
                DatePicker("Hora de la alarma", selection: $newAlarmDate, displayedComponents: .hourAndMinute)
                TextField("Etiqueta de la alarma", text: $newAlarmLabel)

                Picker("Reel de \(store.activeCreatorHandle)", selection: $newAlarmPhraseId) {
                    Text("🎲 Reel Completo Aleatorio").tag("random")
                    ForEach(store.phrases) { p in
                        Text("(\(String(format: "%.0fs", p.durationSeconds))) \(p.text)").lineLimit(1).tag(p.id)
                    }
                }
            }
            .navigationTitle("Nueva Alarma")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        showingAddAlarmSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Añadir") {
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: newAlarmDate)
                        store.addFixedAlarm(
                            hour: comps.hour ?? 8,
                            minute: comps.minute ?? 0,
                            label: newAlarmLabel,
                            specificPhraseId: newAlarmPhraseId == "random" ? nil : newAlarmPhraseId
                        )
                        store.applyAndScheduleNotifications()
                        showingAddAlarmSheet = false
                    }
                }
            }
        }
    }

    // MARK: - TAB 3: IMPORTAR CUALQUIER @USUARIO DE INSTAGRAM O REEL INDIVIDUAL
    private var importTab: some View {
        NavigationStack {
            Form {
                // SECCIÓN 1: PONER SOLO EL @USUARIO Y CONFIGURAR TODA LA APP AUTOMÁTICAMENTE
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "sparkles.tv.fill")
                                .foregroundColor(.orange)
                            Text("Clonador Automático por @Usuario")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.orange)
                        }
                        Text("Escribe únicamente el nombre de usuario de Instagram (igual que hiciste con @mrsergiogarza). La app buscará todos sus Reels, descargará sus audios completos, los escuchará con IA para transcribir sus frases y configurará toda la app y las notificaciones con su voz.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Text("@")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.orange)
                        TextField("Ej: mrsergiogarza, lladosfitness, eltemach...", text: $targetInstagramUsername)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    }

                    Stepper("Reels a escuchar: \(maxReelsToExtract)", value: $maxReelsToExtract, in: 3...20)

                    Button {
                        Task {
                            await creatorImporter.importCreatorByUsername(
                                rawUsername: targetInstagramUsername,
                                maxReels: maxReelsToExtract,
                                store: store
                            )
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if creatorImporter.isImporting {
                                ProgressView()
                                    .tint(.black)
                                    .padding(.trailing, 6)
                                Text("Escuchando Reels...")
                                    .fontWeight(.bold)
                            } else {
                                Image(systemName: "bolt.horizontal.circle.fill")
                                Text("Escuchar Reels y Configurar Toda la App")
                                    .fontWeight(.bold)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .disabled(creatorImporter.isImporting || targetInstagramUsername.trimmingCharacters(in: .whitespaces).isEmpty)
                    .listRowBackground(Color.orange)
                    .foregroundColor(.black)

                    if creatorImporter.isImporting || !creatorImporter.progressText.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            if creatorImporter.isImporting {
                                ProgressView(value: creatorImporter.progressFraction)
                                    .tint(.orange)
                            }
                            Text(creatorImporter.progressText)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        creatorImporter.showLoginWebView = true
                    } label: {
                        Label("Iniciar sesión en Instagram (si pide cuenta para ver más Reels)", systemImage: "key.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("1. Configurar App con Cualquier @Usuario")
                }

                // SECCIÓN 2: PERFILES DE CREADORES YA IMPORTADOS (CAMBIO EN 1 TOQUE)
                Section {
                    ForEach(store.creatorProfiles) { profile in
                        Button {
                            store.switchActiveCreator(to: profile)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.handle)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundColor(.white)
                                    Text("\(profile.phrases.count) Reels completos listos")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                if store.activeCreatorHandle.lowercased() == profile.handle.lowercased() {
                                    Label("Activo", systemImage: "checkmark.circle.fill")
                                        .font(.caption.weight(.bold))
                                        .foregroundColor(.orange)
                                } else {
                                    Text("Usar este @")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }
                } header: {
                    Text("2. Creadores Guardados en tu iPhone")
                }

                // SECCIÓN 3: IMPORTAR UN VÍDEO O AUDIO SUELTO DESDE EL IPHONE (AUDIO COMPLETO)
                Section {
                    TextField("Escribe la frase del Reel (opcional)...", text: $importedQuoteText, axis: .vertical)
                        .lineLimit(2...4)

                    Picker("Categoría", selection: $importedCategory) {
                        ForEach(["Disciplina", "Mentalidad", "Enfoque", "Éxito"], id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }

                    Button {
                        showingFileImporter = true
                    } label: {
                        HStack {
                            Image(systemName: "video.badge.plus")
                            Text("Seleccionar Vídeo o Audio Completo...")
                                .fontWeight(.semibold)
                        }
                    }

                    if !importFeedbackMessage.isEmpty {
                        Text(importFeedbackMessage)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                } header: {
                    Text("3. Añadir Archivo de Reel Individual (Audio Completo)")
                }
            }
            .navigationTitle("Importar Reel / @Usuario")
            .sheet(isPresented: $creatorImporter.showLoginWebView) {
                InstagramLoginSheetView(webView: creatorImporter.webView)
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.audio, .movie, .mpeg4Movie, .quickTimeMovie, .mp3, .wav],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let quote = importedQuoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Reel completo de \(store.activeCreatorHandle) (\(url.deletingPathExtension().lastPathComponent))"
                        : importedQuoteText

                    AudioPlayerManager.shared.importCompleteReelAudio(sourceURL: url) { conversion in
                        switch conversion {
                        case .success(let info):
                            store.addImportedPhrase(
                                text: quote,
                                category: importedCategory,
                                audioFile: info.fullFileName,
                                audioParts: info.partFileNames,
                                duration: info.duration
                            )
                            importedQuoteText = ""
                            importFeedbackMessage = "✅ Reel completo importado (\(String(format: "%.1fs", info.duration)) sin cortes) y activado en tus notificaciones."
                        case .failure(let err):
                            importFeedbackMessage = "❌ Error importando archivo: \(err.localizedDescription)"
                        }
                    }
                case .failure(let error):
                    importFeedbackMessage = "❌ Error al abrir archivo: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct InstagramLoginSheetView: View {
    @Environment(\.dismiss) private var dismiss
    let webView: WKWebView

    var body: some View {
        NavigationStack {
            WebViewContainer(webView: webView)
                .navigationTitle("Sesión de Instagram")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Listo") {
                            dismiss()
                        }
                    }
                }
                .onAppear {
                    if webView.url == nil {
                        if let url = URL(string: "https://www.instagram.com/accounts/login/") {
                            webView.load(URLRequest(url: url))
                        }
                    }
                }
        }
    }
}

struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
