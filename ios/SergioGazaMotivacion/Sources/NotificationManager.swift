import Foundation
import UserNotifications
import Combine

final class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    @Published var isAuthorized: Bool = false
    @Published var pendingCount: Int = 0
    @Published var statusMessage: String = ""

    override private init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        checkAuthorizationStatus()
    }

    func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
            }
        }
        refreshPendingCount()
    }

    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Error solicitando permisos de notificación: \(error)")
            }
            DispatchQueue.main.async {
                self.isAuthorized = granted
                completion?(granted)
            }
        }
    }

    func refreshPendingCount() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            DispatchQueue.main.async {
                self.pendingCount = requests.count
            }
        }
    }

    /// Cuando llega la notificación o alarma (en primer plano o con el motor de alarma en segundo plano activo),
    /// dispara el reproductor de AUDIO COMPLETO SIN CORTES (`fullAudioFile`) de principio a fin.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let info = notification.request.content.userInfo
        let partIndex = info["partIndex"] as? Int ?? 0

        if let fullAudioFile = info["fullAudioFile"] as? String {
            if partIndex == 0 {
                // Reproducir el Reel COMPLETO de principio a fin sin corte de 30s
                AudioPlayerManager.shared.play(fileName: fullAudioFile, forceStartFromBeginning: true)
                completionHandler([.banner, .list])
                return
            } else if AudioPlayerManager.shared.isPlaying {
                // El audio completo ya está sonando sin cortes; silenciar partes encadenadas redundantes
                completionHandler([])
                return
            }
        }

        completionHandler([.banner, .list, .sound])
    }

    /// Si el usuario toca la notificación desde la pantalla de bloqueo, asegura que suene el Reel completo.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        if let fullAudioFile = info["fullAudioFile"] as? String, !AudioPlayerManager.shared.isPlaying {
            AudioPlayerManager.shared.play(fileName: fullAudioFile, forceStartFromBeginning: true)
        }
        completionHandler()
    }

    /// Envía una notificación/alarma de prueba en 5 segundos que reproduce el AUDIO COMPLETO del Reel.
    func sendTestNotification(with phrase: MotivationalPhrase) {
        let scheduleBlock = {
            // Activar vigilia de audio completo para garantizar reproducción íntegra en pantalla bloqueada
            AudioPlayerManager.shared.setBackgroundAlarmEngine(enabled: true)

            let parts = phrase.audioParts.isEmpty ? [phrase.audioFile] : phrase.audioParts
            let totalParts = parts.count

            for (idx, partFile) in parts.enumerated() {
                let content = UNMutableNotificationContent()
                let partSuffix = totalParts > 1 ? " (Parte \(idx + 1)/\(totalParts))" : ""
                content.title = "🔥 \(phrase.author)\(partSuffix)"
                content.subtitle = "\(phrase.category.uppercased()) • \(String(format: "%.0fs", phrase.durationSeconds)) COMPLETO"
                content.body = "\"\(phrase.text)\""
                content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: partFile))
                content.userInfo = [
                    "phraseId": phrase.id,
                    "fullAudioFile": phrase.audioFile,
                    "partIndex": idx,
                    "totalParts": totalParts
                ]

                let delaySeconds = 5.0 + (Double(idx) * 28.0)
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delaySeconds, repeats: false)
                let request = UNNotificationRequest(
                    identifier: "test_full_notif_\(phrase.id)_p\(idx)",
                    content: content,
                    trigger: trigger
                )
                UNUserNotificationCenter.current().add(request)
            }

            DispatchQueue.main.async {
                self.statusMessage = "¡Bloquea tu iPhone! En 5s sonará el audio COMPLETO (\(String(format: "%.0fs", phrase.durationSeconds))) de \(phrase.author)."
                self.refreshPendingCount()
            }
        }

        if isAuthorized {
            scheduleBlock()
        } else {
            requestAuthorization { granted in
                if granted { scheduleBlock() }
            }
        }
    }

    /// Reprograma todas las notificaciones y alarmas encadenando todas las partes de cada Reel
    /// y activando el motor de audio completo en segundo plano.
    func rescheduleAllNotifications(
        phrases: [MotivationalPhrase],
        intervalConfig: IntervalNotificationConfig,
        fixedSchedules: [FixedAlarmSchedule]
    ) {
        let activePhrases: [MotivationalPhrase] = {
            let enabled = phrases.filter { $0.isEnabledForNotifications }
            if intervalConfig.onlyFavorites {
                let favs = enabled.filter { $0.isFavorite }
                return favs.isEmpty ? enabled : favs
            }
            return enabled.isEmpty ? phrases : enabled
        }()

        guard !activePhrases.isEmpty else {
            DispatchQueue.main.async {
                self.statusMessage = "Activa al menos un Reel para programar notificaciones."
            }
            return
        }

        AudioPlayerManager.shared.setBackgroundAlarmEngine(enabled: intervalConfig.fullAudioAlarmMode)

        let performScheduling = {
            let center = UNUserNotificationCenter.current()
            center.removeAllPendingNotificationRequests()

            var scheduledRequestsCount = 0
            let maxIOSRequests = 62 // Límite del sistema iOS es 64

            // 1. Programar Alarmas en Horarios Fijos Diarios (con encadenamiento de partes para el Reel completo)
            for alarm in fixedSchedules where alarm.isEnabled {
                let chosenPhrase = activePhrases.first(where: { $0.id == alarm.specificPhraseId })
                    ?? activePhrases.randomElement()!
                let parts = chosenPhrase.audioParts.isEmpty ? [chosenPhrase.audioFile] : chosenPhrase.audioParts

                for (pIdx, partFile) in parts.enumerated() {
                    guard scheduledRequestsCount < maxIOSRequests else { break }

                    let content = UNMutableNotificationContent()
                    let partBadge = parts.count > 1 ? " [\(pIdx + 1)/\(parts.count)]" : ""
                    content.title = "⚡ \(alarm.label) • \(chosenPhrase.author)\(partBadge)"
                    content.subtitle = "AUDIO COMPLETO (\(String(format: "%.0fs", chosenPhrase.durationSeconds)))"
                    content.body = "\"\(chosenPhrase.text)\""
                    content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: partFile))
                    content.userInfo = [
                        "phraseId": chosenPhrase.id,
                        "fullAudioFile": chosenPhrase.audioFile,
                        "partIndex": pIdx,
                        "totalParts": parts.count
                    ]

                    let offsetSeconds = pIdx * 28
                    let totalMinutesOffset = (alarm.minute * 60 + offsetSeconds) / 60
                    let targetHour = (alarm.hour + (totalMinutesOffset / 60)) % 24
                    let targetMinute = totalMinutesOffset % 60
                    let targetSecond = offsetSeconds % 60

                    var dateComponents = DateComponents()
                    dateComponents.hour = targetHour
                    dateComponents.minute = targetMinute
                    dateComponents.second = targetSecond

                    let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                    let request = UNNotificationRequest(
                        identifier: "fixed_alarm_\(alarm.id.uuidString)_p\(pIdx)",
                        content: content,
                        trigger: trigger
                    )
                    center.add(request)
                    scheduledRequestsCount += 1
                }
            }

            // 2. Programar Intervalos Motivadores (con todas las partes de cada Reel completo)
            if intervalConfig.isEnabled {
                let stepSeconds = TimeInterval(max(15, intervalConfig.intervalMinutes) * 60)
                let calendar = Calendar.current
                var candidateDate = Date().addingTimeInterval(stepSeconds)
                var reelCounter = 0
                var safetyCounter = 0

                while scheduledRequestsCount < maxIOSRequests && safetyCounter < 400 {
                    safetyCounter += 1
                    let hour = calendar.component(.hour, from: candidateDate)

                    let isWithinActiveWindow: Bool = {
                        if intervalConfig.startHour <= intervalConfig.endHour {
                            return hour >= intervalConfig.startHour && hour < intervalConfig.endHour
                        } else {
                            return hour >= intervalConfig.startHour || hour < intervalConfig.endHour
                        }
                    }()

                    if isWithinActiveWindow {
                        let phrase = activePhrases[reelCounter % activePhrases.count]
                        let parts = phrase.audioParts.isEmpty ? [phrase.audioFile] : phrase.audioParts

                        for (pIdx, partFile) in parts.enumerated() {
                            guard scheduledRequestsCount < maxIOSRequests else { break }

                            let partDate = candidateDate.addingTimeInterval(Double(pIdx) * 28.0)
                            let content = UNMutableNotificationContent()
                            let partBadge = parts.count > 1 ? " [\(pIdx + 1)/\(parts.count)]" : ""
                            content.title = "🔥 \(phrase.author)\(partBadge)"
                            content.subtitle = "\(phrase.category.uppercased()) • \(String(format: "%.0fs", phrase.durationSeconds))"
                            content.body = "\"\(phrase.text)\""
                            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: partFile))
                            content.userInfo = [
                                "phraseId": phrase.id,
                                "fullAudioFile": phrase.audioFile,
                                "partIndex": pIdx,
                                "totalParts": parts.count
                            ]

                            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: partDate)
                            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                            let req = UNNotificationRequest(
                                identifier: "interval_notif_\(reelCounter)_p\(pIdx)",
                                content: content,
                                trigger: trigger
                            )
                            center.add(req)
                            scheduledRequestsCount += 1
                        }
                        reelCounter += 1
                    }

                    candidateDate = candidateDate.addingTimeInterval(stepSeconds)
                }
            }

            DispatchQueue.main.async {
                let creatorName = activePhrases.first?.author ?? "@mrsergiogarza"
                self.statusMessage = "✅ Notificaciones con AUDIO COMPLETO activadas para \(creatorName)."
                self.refreshPendingCount()
            }
        }

        if isAuthorized {
            performScheduling()
        } else {
            requestAuthorization { granted in
                if granted {
                    performScheduling()
                } else {
                    self.statusMessage = "⚠️ Permiso de notificaciones denegado. Actívalo en Ajustes de iOS."
                }
            }
        }
    }
}
