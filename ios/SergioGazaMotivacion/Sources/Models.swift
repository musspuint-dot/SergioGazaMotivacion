import Foundation

struct MotivationalPhrase: Identifiable, Codable, Hashable {
    var id: String
    var text: String
    var author: String
    var category: String
    var audioFile: String
    var durationSeconds: Double
    var sourceReel: String
    var isFavorite: Bool = false
    var isEnabledForNotifications: Bool = true

    enum CodingKeys: String, CodingKey {
        case id, text, author, category, audioFile, durationSeconds, sourceReel
        case isFavorite, isEnabledForNotifications
    }

    init(
        id: String = UUID().uuidString,
        text: String,
        author: String = "@mrsergiogaza",
        category: String = "Disciplina",
        audioFile: String,
        durationSeconds: Double,
        sourceReel: String = "custom",
        isFavorite: Bool = false,
        isEnabledForNotifications: Bool = true
    ) {
        self.id = id
        self.text = text
        self.author = author
        self.category = category
        self.audioFile = audioFile
        self.durationSeconds = durationSeconds
        self.sourceReel = sourceReel
        self.isFavorite = isFavorite
        self.isEnabledForNotifications = isEnabledForNotifications
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? "@mrsergiogaza"
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "Motivación"
        audioFile = try container.decode(String.self, forKey: .audioFile)
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 10.0
        sourceReel = try container.decodeIfPresent(String.self, forKey: .sourceReel) ?? "reel"
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isEnabledForNotifications = try container.decodeIfPresent(Bool.self, forKey: .isEnabledForNotifications) ?? true
    }
}

struct FixedAlarmSchedule: Identifiable, Codable {
    var id: UUID = UUID()
    var hour: Int
    var minute: Int
    var isEnabled: Bool = true
    var specificPhraseId: String? = nil // nil = Frase aleatoria con audio de @mrsergiogaza
    var label: String = "Dosis de Disciplina"

    var formattedTime: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

struct IntervalNotificationConfig: Codable {
    var isEnabled: Bool = true
    var intervalMinutes: Int = 120 // Cada 2 horas por defecto
    var startHour: Int = 8         // Desde las 08:00
    var endHour: Int = 22          // Hasta las 22:00
    var onlyFavorites: Bool = false
}
