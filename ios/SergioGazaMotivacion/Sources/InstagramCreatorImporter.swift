import Foundation
import WebKit
import Speech
import AVFoundation
import Combine

@MainActor
final class InstagramCreatorImporter: NSObject, ObservableObject, WKNavigationDelegate {
    static let shared = InstagramCreatorImporter()

    @Published var isImporting: Bool = false
    @Published var progressText: String = ""
    @Published var progressFraction: Double = 0.0
    @Published var discoveredShortcodes: [String] = []
    @Published var showLoginWebView: Bool = false

    let webView: WKWebView
    private var navigationContinuation: CheckedContinuation<Void, Never>?

    override private init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        self.webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        super.init()
        self.webView.navigationDelegate = self
        self.webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.navigationContinuation?.resume()
            self.navigationContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.navigationContinuation?.resume()
            self.navigationContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.navigationContinuation?.resume()
            self.navigationContinuation = nil
        }
    }

    private func loadURLAndWait(_ url: URL, waitSeconds: Double = 3.5) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.navigationContinuation = continuation
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            self.webView.load(request)

            // Timeout de seguridad por si Instagram mantiene conexiones abiertas
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(8.0 * 1_000_000_000))
                if let cont = self.navigationContinuation {
                    self.navigationContinuation = nil
                    cont.resume()
                }
            }
        }
        try? await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))
    }

    static func cleanUsername(_ rawInput: String) -> String {
        var s = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: s), let host = url.host, host.contains("instagram.com") {
            let parts = url.pathComponents.filter { $0 != "/" && $0 != "reels" && $0 != "reel" }
            if let first = parts.first {
                s = first
            }
        }
        s = s.replacingOccurrences(of: "@", with: "")
        s = s.replacingOccurrences(of: "/", with: "")
        return s.lowercased()
    }

    /// Solicita permiso para el motor de transcripción de voz de Apple (`SFSpeechRecognizer`).
    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Escucha el archivo de audio en el iPhone usando `SFSpeechRecognizer` y devuelve la frase transcrita.
    private func transcribeAudioOnDevice(audioURL: URL, fallbackText: String) async -> String {
        let speechAllowed = await requestSpeechPermission()
        guard speechAllowed else { return fallbackText }

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-MX"))
            ?? SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
            ?? SFSpeechRecognizer()

        guard let recognizer = recognizer, recognizer.isAvailable else {
            return fallbackText
        }

        return await withCheckedContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: audioURL)
            request.shouldReportPartialResults = false

            var didResume = false
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let result = result, result.isFinal {
                    if !didResume {
                        didResume = true
                        let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(returning: text.isEmpty ? fallbackText : text)
                    }
                } else if error != nil {
                    if !didResume {
                        didResume = true
                        continuation.resume(returning: fallbackText)
                    }
                }
            }

            // Timeout máximo de 18s por transcripción local
            Task {
                try? await Task.sleep(nanoseconds: 18 * 1_000_000_000)
                if !didResume {
                    didResume = true
                    task.cancel()
                    continuation.resume(returning: fallbackText)
                }
            }
        }
    }

    /// Extrae todos los Reels de cualquier `@username` de Instagram, los descarga en el iPhone,
    /// escucha y transcribe su voz con IA, genera los audios completos `.caf` y configura toda la app.
    func importCreatorByUsername(
        rawUsername: String,
        maxReels: Int = 10,
        store: PhraseStore
    ) async {
        let username = Self.cleanUsername(rawUsername)
        guard !username.isEmpty else {
            progressText = "⚠️ Escribe un nombre de usuario válido de Instagram."
            return
        }

        // Si el usuario escribe mrsergiogarza o mrsergiogaza y ya tenemos el catálogo empaquetado,
        // activarlo al instante o actualizarlo.
        if username == "mrsergiogarza" || username == "mrsergiogaza" {
            if let existing = store.creatorProfiles.first(where: { $0.username.lowercased() == "mrsergiogarza" }),
               !existing.phrases.isEmpty {
                store.switchActiveCreator(to: existing)
                progressText = "✅ App configurada con los \(existing.phrases.count) Reels completos de @mrsergiogarza."
                progressFraction = 1.0
                return
            }
        }

        isImporting = true
        progressFraction = 0.05
        progressText = "🔍 Buscando Reels en el perfil @\(username)..."

        var shortcodes: [String] = []

        // 1. Recolectar enlaces /reel/ desde el perfil y pestaña /reels/
        for pathSuffix in ["", "reels/"] {
            guard let profileURL = URL(string: "https://www.instagram.com/\(username)/\(pathSuffix)") else { continue }
            await loadURLAndWait(profileURL, waitSeconds: 3.5)

            for scrollStep in 1...3 {
                progressText = "🔍 Explorando @\(username) (paso \(scrollStep)/3)..."
                let jsCollect = """
                (() => {
                    window.scrollBy(0, 1600);
                    const links = Array.from(document.querySelectorAll('a[href*="/reel/"]')).map(a => a.href);
                    const htmlMatches = (document.documentElement.innerHTML.match(/\\/reel\\/([A-Za-z0-9_-]{8,15})/g) || []);
                    return JSON.stringify({links: links, htmlMatches: htmlMatches});
                })()
                """
                if let jsonStr = try? await webView.evaluateJavaScript(jsCollect) as? String,
                   let data = jsonStr.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] {
                    let allCandidates = (parsed["links"] ?? []) + (parsed["htmlMatches"] ?? [])
                    for candidate in allCandidates {
                        if let range = candidate.range(of: #"/reel/([A-Za-z0-9_-]+)"#, options: .regularExpression) {
                            let code = String(candidate[range]).replacingOccurrences(of: "/reel/", with: "").replacingOccurrences(of: "/", with: "")
                            if !code.isEmpty && !shortcodes.contains(code) {
                                shortcodes.append(code)
                            }
                        }
                    }
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }

        discoveredShortcodes = shortcodes
        let targetCodes = Array(shortcodes.prefix(maxReels))

        if targetCodes.isEmpty {
            isImporting = false
            progressFraction = 0.0
            progressText = "⚠️ Instagram requiere iniciar sesión para ver los Reels de @\(username) o la cuenta es privada. Pulsa 'Iniciar sesión en Instagram' abajo y vuelve a intentarlo."
            return
        }

        progressText = "🎬 Encontrados \(targetCodes.count) Reels de @\(username). Descargando y escuchando audios..."
        var importedPhrases: [MotivationalPhrase] = []

        for (index, code) in targetCodes.enumerated() {
            let stepNum = index + 1
            progressFraction = 0.15 + (0.80 * (Double(index) / Double(targetCodes.count)))
            progressText = "🎙️ [\(stepNum)/\(targetCodes.count)] Extrayendo y escuchando Reel \(code) de @\(username)..."

            guard let (mp4URL, captionText) = await extractVideoURLAndCaption(forShortcode: code) else {
                continue
            }

            // Descargar el archivo MP4 temporalmente
            do {
                let (tempDownloadURL, _) = try await URLSession.shared.download(from: mp4URL)
                let tempMP4 = FileManager.default.temporaryDirectory.appendingPathComponent("\(username)_\(code).mp4")
                try? FileManager.default.removeItem(at: tempMP4)
                try FileManager.default.moveItem(at: tempDownloadURL, to: tempMP4)

                // Convertir a Audio Completo (.caf) + Partes de 28s (.caf)
                let prefix = "\(username)_reel_\(String(format: "%03d", stepNum))"
                let audioInfo = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(fullFileName: String, partFileNames: [String], duration: Double, fullURL: URL), Error>) in
                    AudioPlayerManager.shared.importCompleteReelAudio(sourceURL: tempMP4, prefix: prefix) { res in
                        cont.resume(with: res)
                    }
                }

                // Escuchar el audio con SFSpeechRecognizer en el iPhone para transcribir la frase
                let fallbackQuote = captionText.isEmpty
                    ? "Audio motivador completo de @\(username) (Reel #\(stepNum))"
                    : captionText

                let transcribedText = await transcribeAudioOnDevice(
                    audioURL: audioInfo.fullURL,
                    fallbackText: fallbackQuote
                )

                let phrase = MotivationalPhrase(
                    id: "\(username)_\(code)",
                    text: transcribedText,
                    author: "@\(username)",
                    category: Self.categorize(transcribedText),
                    audioFile: audioInfo.fullFileName,
                    audioParts: audioInfo.partFileNames,
                    durationSeconds: round(audioInfo.duration * 10) / 10.0,
                    sourceReel: code,
                    isFavorite: false,
                    isEnabledForNotifications: true
                )
                importedPhrases.append(phrase)
                try? FileManager.default.removeItem(at: tempMP4)
            } catch {
                print("Error descargando/convirtiendo Reel \(code): \(error)")
            }
        }

        if importedPhrases.isEmpty {
            isImporting = false
            progressFraction = 0.0
            progressText = "⚠️ No se pudieron extraer los streams de vídeo sin sesión. Pulsa 'Iniciar sesión en Instagram' abajo e inténtalo de nuevo."
            return
        }

        // Guardar perfil del nuevo creador y configurar toda la aplicación con él
        let newProfile = CreatorProfile(
            username: username,
            phrases: importedPhrases,
            updatedAt: Date()
        )
        store.saveAndActivateCreatorProfile(newProfile)

        progressFraction = 1.0
        isImporting = false
        progressText = "✅ ¡Listo! Toda la app está configurada ahora con @\(username) (\(importedPhrases.count) Reels completos con voz activados en tus notificaciones)."
    }

    private func extractVideoURLAndCaption(forShortcode code: String) async -> (URL, String)? {
        let candidateURLs = [
            "https://www.instagram.com/reel/\(code)/",
            "https://www.instagram.com/p/\(code)/",
            "https://www.instagram.com/reel/\(code)/embed/captioned/"
        ]

        let jsExtract = """
        (() => {
            let videoUrl = "";
            const videoEl = document.querySelector('video');
            if (videoEl && videoEl.src && videoEl.src.startsWith('http') && !videoEl.src.startsWith('blob:')) {
                videoUrl = videoEl.src;
            }
            const rawHtml = document.documentElement.innerHTML
                .replace(/\\\\\\//g, '/')
                .replace(/\\\\u0026/g, '&')
                .replace(/&amp;/g, '&');

            if (!videoUrl) {
                const mp4Matches = rawHtml.match(/https:\\/\\/[^"'\\s\\\\]+\\.mp4[^"'\\s\\\\]*/g);
                if (mp4Matches && mp4Matches.length > 0) {
                    videoUrl = mp4Matches[0];
                }
            }

            let caption = "";
            const ogDesc = document.querySelector('meta[property="og:description"]');
            if (ogDesc && ogDesc.content) {
                caption = ogDesc.content;
            }
            return JSON.stringify({videoUrl: videoUrl, caption: caption});
        })()
        """

        for urlString in candidateURLs {
            guard let url = URL(string: urlString) else { continue }
            await loadURLAndWait(url, waitSeconds: 3.0)

            if let resString = try? await webView.evaluateJavaScript(jsExtract) as? String,
               let data = resString.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               let vUrlStr = dict["videoUrl"],
               !vUrlStr.isEmpty,
               let validURL = URL(string: vUrlStr) {
                let rawCaption = dict["caption"] ?? ""
                let cleanCaption = Self.cleanInstagramMetaCaption(rawCaption)
                return (validURL, cleanCaption)
            }
        }
        return nil
    }

    private static func cleanInstagramMetaCaption(_ raw: String) -> String {
        var text = raw
        if let quoteStart = text.firstIndex(of: "\""), let quoteEnd = text.lastIndex(of: "\""), quoteStart != quoteEnd {
            text = String(text[text.index(after: quoteStart)..<quoteEnd])
        }
        text = text.replacingOccurrences(of: #"#\S+"#, with: "", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func categorize(_ text: String) -> String {
        let t = text.lowercased()
        if t.contains("disciplina") || t.contains("alarma") || t.contains("levántate") || t.contains("regla") {
            return "Disciplina"
        }
        if t.contains("miedo") || t.contains("duda") || t.contains("mentalidad") || t.contains("quejar") {
            return "Mentalidad"
        }
        if t.contains("éxito") || t.contains("ganar") || t.contains("dinero") || t.contains("lograr") {
            return "Éxito"
        }
        if t.contains("enfoque") || t.contains("enfócate") || t.contains("tiempo") || t.contains("distracciones") {
            return "Enfoque"
        }
        return "Disciplina"
    }
}
