import Foundation
import Combine

final class PhraseStore: ObservableObject {
    @Published var activeCreatorHandle: String = "@mrsergiogarza"
    @Published var phrases: [MotivationalPhrase] = []
    @Published var creatorProfiles: [CreatorProfile] = []
    @Published var intervalConfig: IntervalNotificationConfig = IntervalNotificationConfig()
    @Published var fixedSchedules: [FixedAlarmSchedule] = [
        FixedAlarmSchedule(hour: 7, minute: 30, isEnabled: true, label: "Alarma Mañana (Audio Completo)"),
        FixedAlarmSchedule(hour: 14, minute: 0, isEnabled: true, label: "Enfoque Medio Día (Audio Completo)"),
        FixedAlarmSchedule(hour: 20, minute: 30, isEnabled: false, label: "Disciplina Nocturna (Audio Completo)")
    ]

    private let activeCreatorStorageKey = "motivacion_active_creator_v2"
    private let profilesStorageKey = "motivacion_creator_profiles_v2"
    private let intervalStorageKey = "motivacion_interval_config_v2"
    private let fixedAlarmsStorageKey = "motivacion_fixed_alarms_v2"

    init() {
        AudioPlayerManager.shared.syncBundledSoundsToLibrary()
        loadAll()
        AudioPlayerManager.shared.setBackgroundAlarmEngine(enabled: intervalConfig.fullAudioAlarmMode)
    }

    func loadAll() {
        // 1. Cargar catálogo base de @mrsergiogarza desde el Bundle (`phrases.json`)
        var bundledPhrases: [MotivationalPhrase] = []
        if let url = Bundle.main.url(forResource: "phrases", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([MotivationalPhrase].self, from: data) {
            bundledPhrases = decoded
        }

        let defaultSergioProfile = CreatorProfile(
            username: "mrsergiogarza",
            phrases: bundledPhrases,
            updatedAt: Date()
        )

        // 2. Cargar perfiles de creadores guardados
        if let profilesData = UserDefaults.standard.data(forKey: profilesStorageKey),
           var savedProfiles = try? JSONDecoder().decode([CreatorProfile].self, from: profilesData),
           !savedProfiles.isEmpty {
            // Asegurar que el perfil base de @mrsergiogarza esté actualizado con los audios completos
            if let idx = savedProfiles.firstIndex(where: { $0.username.lowercased() == "mrsergiogarza" }) {
                if savedProfiles[idx].phrases.isEmpty {
                    savedProfiles[idx] = defaultSergioProfile
                }
            } else {
                savedProfiles.insert(defaultSergioProfile, at: 0)
            }
            self.creatorProfiles = savedProfiles
        } else {
            self.creatorProfiles = [defaultSergioProfile]
        }

        // 3. Cargar creador activo
        let savedActiveHandle = UserDefaults.standard.string(forKey: activeCreatorStorageKey) ?? "@mrsergiogarza"
        if let matchingProfile = creatorProfiles.first(where: { $0.handle.lowercased() == savedActiveHandle.lowercased() }) {
            self.activeCreatorHandle = matchingProfile.handle
            self.phrases = matchingProfile.phrases
        } else if let firstProfile = creatorProfiles.first {
            self.activeCreatorHandle = firstProfile.handle
            self.phrases = firstProfile.phrases
        }

        // 4. Cargar configuración de intervalos y alarmas
        if let intervalData = UserDefaults.standard.data(forKey: intervalStorageKey),
           let decodedInterval = try? JSONDecoder().decode(IntervalNotificationConfig.self, from: intervalData) {
            self.intervalConfig = decodedInterval
        }

        if let alarmsData = UserDefaults.standard.data(forKey: fixedAlarmsStorageKey),
           let decodedAlarms = try? JSONDecoder().decode([FixedAlarmSchedule].self, from: alarmsData) {
            self.fixedSchedules = decodedAlarms
        }
    }

    func saveAll() {
        // Sincronizar las frases actuales dentro del perfil del creador activo
        if let idx = creatorProfiles.firstIndex(where: { $0.handle.lowercased() == activeCreatorHandle.lowercased() }) {
            creatorProfiles[idx].phrases = phrases
            creatorProfiles[idx].updatedAt = Date()
        }

        UserDefaults.standard.set(activeCreatorHandle, forKey: activeCreatorStorageKey)
        if let encodedProfiles = try? JSONEncoder().encode(creatorProfiles) {
            UserDefaults.standard.set(encodedProfiles, forKey: profilesStorageKey)
        }
        if let encodedInterval = try? JSONEncoder().encode(intervalConfig) {
            UserDefaults.standard.set(encodedInterval, forKey: intervalStorageKey)
        }
        if let encodedAlarms = try? JSONEncoder().encode(fixedSchedules) {
            UserDefaults.standard.set(encodedAlarms, forKey: fixedAlarmsStorageKey)
        }
    }

    /// Guarda un nuevo perfil de creador importado por `@username` y transforma toda la app a ese creador.
    func saveAndActivateCreatorProfile(_ profile: CreatorProfile) {
        if let idx = creatorProfiles.firstIndex(where: { $0.username.lowercased() == profile.username.lowercased() }) {
            creatorProfiles[idx] = profile
        } else {
            creatorProfiles.insert(profile, at: 0)
        }
        switchActiveCreator(to: profile)
    }

    /// Cambia toda la aplicación (frases, Soundboard, notificaciones y alarmas) al creador seleccionado.
    func switchActiveCreator(to profile: CreatorProfile) {
        AudioPlayerManager.shared.stop()
        self.activeCreatorHandle = profile.handle
        self.phrases = profile.phrases
        saveAll()
        applyAndScheduleNotifications()
    }

    func toggleFavorite(for phrase: MotivationalPhrase) {
        guard let idx = phrases.firstIndex(where: { $0.id == phrase.id }) else { return }
        phrases[idx].isFavorite.toggle()
        saveAll()
    }

    func toggleNotificationEnabled(for phrase: MotivationalPhrase) {
        guard let idx = phrases.firstIndex(where: { $0.id == phrase.id }) else { return }
        phrases[idx].isEnabledForNotifications.toggle()
        saveAll()
    }

    func addImportedPhrase(
        text: String,
        category: String,
        audioFile: String,
        audioParts: [String],
        duration: Double
    ) {
        let newPhrase = MotivationalPhrase(
            id: "custom_\(Int(Date().timeIntervalSince1970))",
            text: text,
            author: activeCreatorHandle,
            category: category,
            audioFile: audioFile,
            audioParts: audioParts,
            durationSeconds: round(duration * 10) / 10.0,
            sourceReel: "importado_iphone",
            isFavorite: true,
            isEnabledForNotifications: true
        )
        phrases.insert(newPhrase, at: 0)
        saveAll()
        applyAndScheduleNotifications()
    }

    func addFixedAlarm(hour: Int, minute: Int, label: String, specificPhraseId: String?) {
        let alarm = FixedAlarmSchedule(
            hour: hour,
            minute: minute,
            isEnabled: true,
            specificPhraseId: specificPhraseId,
            label: label.isEmpty ? "Alarma Motivadora (Audio Completo)" : label
        )
        fixedSchedules.append(alarm)
        saveAll()
    }

    func removeFixedAlarm(at offsets: IndexSet) {
        fixedSchedules.remove(atOffsets: offsets)
        saveAll()
    }

    func applyAndScheduleNotifications() {
        saveAll()
        NotificationManager.shared.rescheduleAllNotifications(
            phrases: phrases,
            intervalConfig: intervalConfig,
            fixedSchedules: fixedSchedules
        )
    }
}
