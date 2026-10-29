import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var store: PhraseStore
    @StateObject private var player = AudioPlayerManager.shared
    @StateObject private var notifications = NotificationManager.shared

    @State private var selectedTab: Int = 0
    @State private var selectedCategory: String = "Todas"
    @State private var searchText: String = ""

    // Estado para añadir nueva alarma fija
    @State private var showingAddAlarmSheet = false
    @State private var newAlarmDate = Date()
    @State private var newAlarmLabel = "Dosis de Disciplina"
    @State private var newAlarmPhraseId: String = "random"

    // Estado para importar un Reel/Audio desde el iPhone
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
                    Label("Audios", systemImage: "waveform.circle.fill")
                }
                .tag(0)

            notificationsTab
                .tabItem {
                    Label("Notificaciones", systemImage: "bell.badge.waveform.fill")
                }
                .tag(1)

            importTab
                .tabItem {
                    Label("Importar Reel", systemImage: "plus.rectangle.on.folder.fill")
                }
                .tag(2)
        }
        .preferredColorScheme(.dark)
        .tint(.orange)
    }

    // MARK: - TAB 1: SOUNDBOARD Y FRASES DE @MRSERGIOGAZA
    private var soundboardTab: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerHeroCard
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Filtro de categorías
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
            .navigationTitle("🔥 @mrsergiogaza")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Buscar frase motivadora...")
        }
    }

    private var headerHeroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MENTALIDAD INQUEBRANTABLE")
                        .font(.caption.weight(.heavy))
                        .foregroundColor(.orange)
                    Text("\(store.phrases.count) audios listos • \(notifications.pendingCount) avisos activos")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                Spacer()
                Image(systemName: "flame.fill")
                    .font(.title2)
                    .foregroundColor(.orange)
            }

            HStack(spacing: 10) {
                Button {
                    if let randomPhrase = store.phrases.randomElement() {
                        player.play(fileName: randomPhrase.audioFile)
                    }
                } label: {
                    Label("Audio Aleatorio", systemImage: "shuffle")
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
                    Label("Probar Aviso (5s)", systemImage: "bell.and.waves.left.and.right.fill")
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

                Text(String(format: "%.1fs", phrase.durationSeconds))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.gray)

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
                        Text(isPlayingThis ? "Detener Audio" : "Escuchar Voz")
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
                        Text("Probar en Bloqueo (5s)")
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

    // MARK: - TAB 2: PROGRAMACIÓN DE NOTIFICACIONES CON VOZ
    private var notificationsTab: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: notifications.isAuthorized ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(notifications.isAuthorized ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(notifications.isAuthorized ? "Notificaciones con Voz Autorizadas" : "Permiso de Notificaciones Pendiente")
                                .font(.subheadline.weight(.semibold))
                            Text("\(notifications.pendingCount) notificaciones en cola en iOS")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if !notifications.isAuthorized {
                            Button("Activar") {
                                notifications.requestAuthorization()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                } header: {
                    Text("Estado del Sistema iOS")
                }

                Section {
                    Toggle("Activar Ráfagas por Intervalo", isOn: $store.intervalConfig.isEnabled)

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

                    Toggle("Usar solo mis frases Favoritas ⭐", isOn: $store.intervalConfig.onlyFavorites)
                } header: {
                    Text("1. Notificaciones por Intervalo")
                } footer: {
                    Text("Cada vez que salte la notificación en tu iPhone (incluso bloqueado), sonará el audio del reel de @mrsergiogaza correspondiente a la frase.")
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
                        Label("Añadir Horario Fijo Diario", systemImage: "plus.circle.fill")
                            .foregroundColor(.orange)
                    }
                } header: {
                    Text("2. Horarios Fijos Diarios")
                }

                Section {
                    Button {
                        store.applyAndScheduleNotifications()
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "bell.badge.waveform.fill")
                            Text("Guardar y Activar Notificaciones con Voz")
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
            .navigationTitle("Programar Avisos")
            .sheet(isPresented: $showingAddAlarmSheet) {
                addFixedAlarmSheet
            }
        }
    }

    private var addFixedAlarmSheet: some View {
        NavigationStack {
            Form {
                DatePicker("Hora de la notificación", selection: $newAlarmDate, displayedComponents: .hourAndMinute)
                TextField("Etiqueta (ej. Entrenar sin excusas)", text: $newAlarmLabel)

                Picker("Audio de @mrsergiogaza", selection: $newAlarmPhraseId) {
                    Text("🎲 Frase y Audio Aleatorio").tag("random")
                    ForEach(store.phrases) { p in
                        Text(p.text).lineLimit(1).tag(p.id)
                    }
                }
            }
            .navigationTitle("Nuevo Horario Fijo")
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

    // MARK: - TAB 3: IMPORTADOR DIRECTO DE REELS EN EL IPHONE
    private var importTab: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Además de todos los reels empaquetados en la app, puedes importar cualquier vídeo (.mp4 / .mov) o audio (.mp3 / .wav / .m4a) descargado de @mrsergiogaza directamente desde tu iPhone. La app extraerá los primeros 28 segundos y lo convertirá en tono de notificación.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Importador Directo en iPhone")
                }

                Section {
                    TextField("Escribe la frase del Reel...", text: $importedQuoteText, axis: .vertical)
                        .lineLimit(3...5)

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
                            Text("Seleccionar Vídeo o Audio del Reel...")
                                .fontWeight(.semibold)
                        }
                    }
                } header: {
                    Text("Datos del Nuevo Reel")
                }

                if !importFeedbackMessage.isEmpty {
                    Section {
                        Text(importFeedbackMessage)
                            .font(.footnote)
                            .foregroundColor(.orange)
                    }
                }
            }
            .navigationTitle("Importar Reel")
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.audio, .movie, .mpeg4Movie, .quickTimeMovie, .mp3, .wav],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let quote = importedQuoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Nuevo audio motivador de @mrsergiogaza (\(url.DeletingPathExtension().lastPathComponent))"
                        : importedQuoteText

                    AudioPlayerManager.shared.importReelOrAudioForNotification(sourceURL: url) { conversion in
                        switch conversion {
                        case .success(let info):
                            store.addImportedPhrase(
                                text: quote,
                                category: importedCategory,
                                audioFile: info.fileName,
                                duration: info.duration
                            )
                            importedQuoteText = ""
                            importFeedbackMessage = "✅ Reel importado (\(String(format: "%.1fs", info.duration))) y listo para sonar en tus notificaciones."
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

private extension URL {
    func DeletingPathExtension() -> URL {
        self.deletingPathExtension()
    }
}
