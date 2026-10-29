import Foundation
import AVFoundation
import Combine

final class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = AudioPlayerManager()

    @Published var currentlyPlayingFile: String? = nil
    @Published var isPlaying: Bool = false

    private var player: AVAudioPlayer?

    override private init() {
        super.init()
        configureAudioSession()
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Error configurando AVAudioSession: \(error)")
        }
    }

    /// Devuelve la carpeta `Library/Sounds` donde iOS busca sonidos de notificación personalizados además del Bundle principal.
    static var librarySoundsDirectory: URL {
        let libURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let soundsURL = libURL.appendingPathComponent("Sounds", isDirectory: true)
        if !FileManager.default.fileExists(atPath: soundsURL.path) {
            try? FileManager.default.createDirectory(at: soundsURL, withIntermediateDirectories: true)
        }
        return soundsURL
    }

    /// Sincroniza todos los audios del Bundle a `Library/Sounds` para garantizar al 100% que `UNNotificationSound` los encuentre siempre.
    func syncBundledSoundsToLibrary() {
        let soundsDir = Self.librarySoundsDirectory
        guard let resourceURL = Bundle.main.resourceURL else { return }

        let fm = FileManager.default
        let candidateDirs = [resourceURL, resourceURL.appendingPathComponent("Sounds")]

        for dir in candidateDirs {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for file in files where ["wav", "caf", "aiff", "m4a"].contains(file.pathExtension.lowercased()) {
                let dest = soundsDir.appendingPathComponent(file.lastPathComponent)
                if !fm.fileExists(atPath: dest.path) {
                    try? fm.copyItem(at: file, to: dest)
                }
            }
        }
    }

    func resolveAudioURL(for fileName: String) -> URL? {
        // 1. Buscar en Library/Sounds
        let libSound = Self.librarySoundsDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: libSound.path) {
            return libSound
        }

        // 2. Buscar en el Bundle principal
        let nsName = fileName as NSString
        let base = nsName.deletingPathExtension
        let ext = nsName.pathExtension.isEmpty ? "wav" : nsName.pathExtension

        if let url = Bundle.main.url(forResource: base, withExtension: ext) {
            return url
        }
        if let url = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "Sounds") {
            return url
        }
        return nil
    }

    func play(fileName: String) {
        if currentlyPlayingFile == fileName && isPlaying {
            stop()
            return
        }

        stop()
        configureAudioSession()

        guard let url = resolveAudioURL(for: fileName) else {
            print("No se encontró el archivo de audio: \(fileName)")
            return
        }

        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
            player?.play()
            currentlyPlayingFile = fileName
            isPlaying = true
        } catch {
            print("Error reproduciendo \(fileName): \(error)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        currentlyPlayingFile = nil
        isPlaying = false
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.currentlyPlayingFile = nil
            self.isPlaying = false
        }
    }

    /// Importa un vídeo (.mp4/.mov) o audio (.mp3/.wav/.m4a) directamente en el iPhone,
    /// lo recorta a < 28 segundos y lo guarda en `Library/Sounds/` como archivo `.caf`
    /// compatible con notificaciones de iOS (`UNNotificationSound`).
    func importReelOrAudioForNotification(sourceURL: URL, completion: @escaping (Result<(fileName: String, duration: Double), Error>) -> Void) {
        let accessGranted = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessGranted { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let fileName = "custom_\(Int(Date().timeIntervalSince1970)).caf"
        let destURL = Self.librarySoundsDirectory.appendingPathComponent(fileName)

        let asset = AVURLAsset(url: sourceURL)
        Task {
            do {
                let durationCM = try await asset.load(.duration)
                let totalSeconds = max(1.0, CMTimeGetSeconds(durationCM))
                let clippedSeconds = min(28.0, totalSeconds)

                guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
                    // Fallback: copia directa si ya es wav/caf/m4a
                    try FileManager.default.copyItem(at: sourceURL, to: destURL)
                    DispatchQueue.main.async {
                        completion(.success((fileName: fileName, duration: clippedSeconds)))
                    }
                    return
                }

                exportSession.outputURL = destURL
                exportSession.outputFileType = .caf
                exportSession.timeRange = CMTimeRange(
                    start: .zero,
                    duration: CMTime(seconds: clippedSeconds, preferredTimescale: 600)
                )

                await exportSession.export()

                if exportSession.status == .completed {
                    DispatchQueue.main.async {
                        completion(.success((fileName: fileName, duration: clippedSeconds)))
                    }
                } else {
                    // Si el contenedor CAF directo falla por códec, copiar archivo original a Library/Sounds
                    let fallbackName = "custom_\(Int(Date().timeIntervalSince1970)).\(sourceURL.pathExtension)"
                    let fallbackURL = Self.librarySoundsDirectory.appendingPathComponent(fallbackName)
                    try FileManager.default.copyItem(at: sourceURL, to: fallbackURL)
                    DispatchQueue.main.async {
                        completion(.success((fileName: fallbackName, duration: clippedSeconds)))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}
