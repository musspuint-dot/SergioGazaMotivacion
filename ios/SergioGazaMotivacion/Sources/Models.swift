import Foundation

struct MotivationalPhrase: Identifiable, Codable, Hashable {
    var id: String
    var text: String
    var author: String
    var category: String
    var audioFile: String        // Audio COMPLETO sin cortes del Reel (ej. 77.1s, 89.2s)
    var audioParts: [String]     // Partes consecutivas de 28s para encadenar en UNNotificationSound
    var durationSeconds: Double
    var sourceReel: String
    var isFavorite: Bool = false
    var isEnabledForNotifications: Bool = true

    enum CodingKeys: String, CodingKey {
        case id, text, author, category, audioFile, audioParts, durationSeconds, sourceReel
        case isFavorite, isEnabledForNotifications
    }

    init(
        id: String = UUID().uuidString,
        text: String,
        author: String = "@mrsergiogarza",
        category: String = "Disciplina",
        audioFile: String,
        audioParts: [String]? = nil,
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
        self.audioParts = (audioParts?.isEmpty == false) ? audioParts! : [audioFile]
        self.durationSeconds = durationSeconds
        self.sourceReel = sourceReel
        self.isFavorite = isFavorite
        self.isEnabledForNotifications = isEnabledForNotifications
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? "@mrsergiogarza"
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? "Disciplina"
        audioFile = try container.decode(String.self, forKey: .audioFile)
        let decodedParts = try container.decodeIfPresent([String].self, forKey: .audioParts)
        audioParts = (decodedParts?.isEmpty == false) ? decodedParts! : [audioFile]
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 20.0
        sourceReel = try container.decodeIfPresent(String.self, forKey: .sourceReel) ?? "reel"
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isEnabledForNotifications = try container.decodeIfPresent(Bool.self, forKey: .isEnabledForNotifications) ?? true
    }
}

struct CreatorProfile: Identifiable, Codable, Hashable {
    var id: String { username.lowercased() }
    var username: String          // ej. "mrsergiogarza"
    var handle: String { "@\(username.replacingOccurrences(of: "@", with: ""))" }
    var phrases: [MotivationalPhrase]
    var updatedAt: Date = Date()
}

struct FixedAlarmSchedule: Identifiable, Codable {
    var id: UUID = UUID()
    var hour: Int
    var minute: Int
    var isEnabled: Bool = true
    var specificPhraseId: String? = nil // nil = Reel aleatorio del creador activo
    var label: String = "Alarma Motivadora (Audio Completo)"

    var formattedTime: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

struct IntervalNotificationConfig: Codable {
    var isEnabled: Bool = true
    var intervalMinutes: Int = 120
    var startHour: Int = 8
    var endHour: Int = 22
    var onlyFavorites: Bool = false
    var fullAudioAlarmMode: Bool = true // Reproduce el audio completo sin cortes en segundo plano
}
