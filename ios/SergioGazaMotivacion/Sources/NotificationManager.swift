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

    /// Permite que la notificación suene con el audio de @mrsergiogaza incluso si la app está abierta en primer plano.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    /// Envía una notificación de prueba en 5 segundos con la voz de @mrsergiogaza para probar con la pantalla bloqueada.
    func sendTestNotification(with phrase: MotivationalPhrase) {
        let scheduleBlock = {
            let content = UNMutableNotificationContent()
            content.title = "🔥 Sergio Gaza (@mrsergiogaza)"
            content.subtitle = phrase.category.uppercased()
            content.body = "\"\(phrase.text)\""
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: phrase.audioFile))
            content.userInfo = ["phraseId": phrase.id, "audioFile": phrase.audioFile]

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            let request = UNNotificationRequest(
                identifier: "test_notification_\(UUID().uuidString)",
                content: content,
                trigger: trigger
            )

            UNUserNotificationCenter.current().add(request) { error in
                DispatchQueue.main.async {
                    if let error = error {
                        self.statusMessage = "Error al programar prueba: \(error.localizedDescription)"
                    } else {
                        self.statusMessage = "¡Bloquea tu iPhone ahora! En 5 segundos sonará la voz de @mrsergiogaza."
                        self.refreshPendingCount()
                    }
                }
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

    /// Reprograma todas las notificaciones (tanto por intervalos como por horarios fijos) con los audios de @mrsergiogaza.
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
                self.statusMessage = "Activa al menos una frase para programar notificaciones."
            }
            return
        }

        let performScheduling = {
            let center = UNUserNotificationCenter.current()
            center.removeAllPendingNotificationRequests()

            var scheduledTotal = 0

            // 1. Programar Horarios Fijos Diarios (máx 16)
            for alarm in fixedSchedules where alarm.isEnabled {
                let chosenPhrase = activePhrases.first(where: { $0.id == alarm.specificPhraseId })
                    ?? activePhrases.randomElement()!

                let content = UNMutableNotificationContent()
                content.title = "⚡ \(alarm.label) • @mrsergiogaza"
                content.subtitle = chosenPhrase.category.uppercased()
                content.body = "\"\(chosenPhrase.text)\""
                content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: chosenPhrase.audioFile))
                content.userInfo = ["phraseId": chosenPhrase.id, "audioFile": chosenPhrase.audioFile]

                var dateComponents = DateComponents()
                dateComponents.hour = alarm.hour
                dateComponents.minute = alarm.minute

                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                let request = UNNotificationRequest(
                    identifier: "fixed_alarm_\(alarm.id.uuidString)",
                    content: content,
                    trigger: trigger
                )
                center.add(request)
                scheduledTotal += 1
            }

            // 2. Programar Intervalos Motivadores (hasta completar 60 notificaciones futuras dentro del límite de 64 de iOS)
            if intervalConfig.isEnabled {
                let maxIntervalNotifications = max(1, 60 - scheduledTotal)
                let stepSeconds = TimeInterval(max(15, intervalConfig.intervalMinutes) * 60)
                let calendar = Calendar.current
                var candidateDate = Date().addingTimeInterval(stepSeconds)
                var addedIntervalCount = 0
                var safetyCounter = 0

                while addedIntervalCount < maxIntervalNotifications && safetyCounter < 500 {
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
                        let phrase = activePhrases[addedIntervalCount % activePhrases.count]
                        let content = UNMutableNotificationContent()
                        content.title = "🔥 @mrsergiogaza"
                        content.subtitle = phrase.category.uppercased()
                        content.body = "\"\(phrase.text)\""
                        content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: phrase.audioFile))
                        content.userInfo = ["phraseId": phrase.id, "audioFile": phrase.audioFile]

                        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: candidateDate)
                        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                        let req = UNNotificationRequest(
                            identifier: "interval_notif_\(addedIntervalCount)",
                            content: content,
                            trigger: trigger
                        )
                        center.add(req)
                        addedIntervalCount += 1
                        scheduledTotal += 1
                    }

                    candidateDate = candidateDate.addingTimeInterval(stepSeconds)
                }
            }

            DispatchQueue.main.async {
                self.statusMessage = "✅ \(scheduledTotal) notificaciones con voz de @mrsergiogaza programadas."
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

    func cancelAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        refreshPendingCount()
        statusMessage = "Todas las notificaciones programadas fueron canceladas."
    }
}
