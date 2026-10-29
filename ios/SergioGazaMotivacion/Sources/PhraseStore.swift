import Foundation
import Combine

final class PhraseStore: ObservableObject {
    @Published var phrases: [MotivationalPhrase] = []
    @Published var intervalConfig: IntervalNotificationConfig = IntervalNotificationConfig()
    @Published var fixedSchedules: [FixedAlarmSchedule] = [
        FixedAlarmSchedule(hour: 7, minute: 30, isEnabled: true, label: "Levántate sin Excusas"),
        FixedAlarmSchedule(hour: 14, minute: 0, isEnabled: true, label: "Mantén el Enfoque"),
        FixedAlarmSchedule(hour: 20, minute: 30, isEnabled: false, label: "Revisión de Disciplina")
    ]

    private let phrasesStorageKey = "sergiogaza_saved_phrases_v1"
    private let intervalStorageKey = "sergiogaza_interval_config_v1"
    private let fixedAlarmsStorageKey = "sergiogaza_fixed_alarms_v1"

    init() {
        AudioPlayerManager.shared.syncBundledSoundsToLibrary()
        loadAll()
    }

    func loadAll() {
        // 1. Cargar frases del Bundle (`phrases.json`) generadas por el script de Reels
        var bundledPhrases: [MotivationalPhrase] = []
        if let url = Bundle.main.url(forResource: "phrases", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([MotivationalPhrase].self, from: data) {
            bundledPhrases = decoded
        }

        // 2. Cargar estado guardado del usuario (favoritos, activados y frases importadas en el iPhone)
        if let savedData = UserDefaults.standard.data(forKey: phrasesStorageKey),
           let savedPhrases = try? JSONDecoder().decode([MotivationalPhrase].self, from: savedData) {
            var merged: [MotivationalPhrase] = []
            let savedDict = Dictionary(uniqueKeysWithValues: savedPhrases.map { ($0.id, $0) })

            for var bp in bundledPhrases {
                if let existing = savedDict[bp.id] {
                    bp.isFavorite = existing.isFavorite
                    bp.isEnabledForNotifications = existing.isEnabledForNotifications
                }
                merged.append(bp)
            }

            // Añadir también las frases personalizadas que el usuario haya importado desde su iPhone
            let bundledIds = Set(bundledPhrases.map { $0.id })
            for sp in savedPhrases where !bundledIds.contains(sp.id) {
                merged.append(sp)
            }
            self.phrases = merged
        } else {
            self.phrases = bundledPhrases
        }

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
        if let encodedPhrases = try? JSONEncoder().encode(phrases) {
            UserDefaults.standard.set(encodedPhrases, forKey: phrasesStorageKey)
        }
        if let encodedInterval = try? JSONEncoder().encode(intervalConfig) {
            UserDefaults.standard.set(encodedInterval, forKey: intervalStorageKey)
        }
        if let encodedAlarms = try? JSONEncoder().encode(fixedSchedules) {
            UserDefaults.standard.set(encodedAlarms, forKey: fixedAlarmsStorageKey)
        }
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

    func addImportedPhrase(text: String, category: String, audioFile: String, duration: Double) {
        let newPhrase = MotivationalPhrase(
            id: "custom_\(Int(Date().timeIntervalSince1970))",
            text: text,
            author: "@mrsergiogaza",
            category: category,
            audioFile: audioFile,
            durationSeconds: round(duration * 10) / 10.0,
            sourceReel: "importado_iphone",
            isFavorite: true,
            isEnabledForNotifications: true
        )
        phrases.insert(newPhrase, at: 0)
        saveAll()
    }

    func addFixedAlarm(hour: Int, minute: Int, label: String, specificPhraseId: String?) {
        let alarm = FixedAlarmSchedule(
            hour: hour,
            minute: minute,
            isEnabled: true,
            specificPhraseId: specificPhraseId,
            label: label.isEmpty ? "Dosis de Disciplina" : label
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
