import Foundation
import AVFoundation
import Combine

final class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = AudioPlayerManager()

    @Published var currentlyPlayingFile: String? = nil
    @Published var isPlaying: Bool = false
    @Published var isBackgroundAlarmEngineActive: Bool = false

    private var player: AVAudioPlayer?
    private var backgroundKeepAlivePlayer: AVAudioPlayer?

    override private init() {
        super.init()
        configureAudioSession()
    }

    func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .duckOthers])
            try session.setActive(true)
        } catch {
            print("Error configurando AVAudioSession: \(error)")
        }
    }

    /// Carpeta `Library/Sounds` donde iOS busca sonidos de notificación personalizados y audios importados.
    static var librarySoundsDirectory: URL {
        let libURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let soundsURL = libURL.appendingPathComponent("Sounds", isDirectory: true)
        if !FileManager.default.fileExists(atPath: soundsURL.path) {
            try? FileManager.default.createDirectory(at: soundsURL, withIntermediateDirectories: true)
        }
        return soundsURL
    }

    /// Sincroniza todos los audios del Bundle a `Library/Sounds`.
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

    /// Activa el motor de vigilia en segundo plano para que las alarmas y notificaciones
    /// reproduzcan el 100% del audio completo del Reel (incluso si dura 60s o 90s) con la pantalla bloqueada.
    func setBackgroundAlarmEngine(enabled: Bool) {
        if enabled {
            startSilentKeepAliveIfNeeded()
        } else {
            backgroundKeepAlivePlayer?.stop()
            backgroundKeepAlivePlayer = nil
            isBackgroundAlarmEngineActive = false
        }
    }

    private func startSilentKeepAliveIfNeeded() {
        guard backgroundKeepAlivePlayer == nil || backgroundKeepAlivePlayer?.isPlaying == false else {
            isBackgroundAlarmEngineActive = true
            return
        }
        configureAudioSession()
        if let silentData = Self.makeSilentWAVData() {
            do {
                let silentPlayer = try AVAudioPlayer(data: silentData)
                silentPlayer.numberOfLoops = -1
                silentPlayer.volume = 0.001
                silentPlayer.prepareToPlay()
                silentPlayer.play()
                self.backgroundKeepAlivePlayer = silentPlayer
                self.isBackgroundAlarmEngineActive = true
            } catch {
                print("Error iniciando keep-alive de alarma: \(error)")
            }
        }
    }

    private static func makeSilentWAVData() -> Data? {
        let sampleRate: UInt32 = 8000
        let numSamples: UInt32 = 8000 // 1 segundo de silencio
        let dataSize = numSamples * 2
        let fileSize = 36 + dataSize

        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        var chunkSize = fileSize.littleEndian
        data.append(Data(bytes: &chunkSize, count: 4))
        data.append("WAVEfmt ".data(using: .ascii)!)
        var subchunk1Size: UInt32 = 16.littleEndian
        data.append(Data(bytes: &subchunk1Size, count: 4))
        var audioFormat: UInt16 = 1.littleEndian
        data.append(Data(bytes: &audioFormat, count: 2))
        var numChannels: UInt16 = 1.littleEndian
        data.append(Data(bytes: &numChannels, count: 2))
        var sr = sampleRate.littleEndian
        data.append(Data(bytes: &sr, count: 4))
        var byteRate = (sampleRate * 2).littleEndian
        data.append(Data(bytes: &byteRate, count: 4))
        var blockAlign: UInt16 = 2.littleEndian
        data.append(Data(bytes: &blockAlign, count: 2))
        var bitsPerSample: UInt16 = 16.littleEndian
        data.append(Data(bytes: &bitsPerSample, count: 2))
        data.append("data".data(using: .ascii)!)
        var subchunk2Size = dataSize.littleEndian
        data.append(Data(bytes: &subchunk2Size, count: 4))
        data.append(Data(count: Int(dataSize)))
        return data
    }

    func resolveAudioURL(for fileName: String) -> URL? {
        let libSound = Self.librarySoundsDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: libSound.path) {
            return libSound
        }

        let nsName = fileName as NSString
        let base = nsName.deletingPathExtension
        let ext = nsName.pathExtension.isEmpty ? "caf" : nsName.pathExtension

        if let url = Bundle.main.url(forResource: base, withExtension: ext) {
            return url
        }
        if let url = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "Sounds") {
            return url
        }
        return nil
    }

    /// Reproduce el audio COMPLETO de un Reel de principio a fin (sin cortar a los 30s).
    func play(fileName: String, forceStartFromBeginning: Bool = false) {
        if !forceStartFromBeginning && currentlyPlayingFile == fileName && isPlaying {
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
            player?.volume = 1.0
            player?.prepareToPlay()
            player?.play()
            DispatchQueue.main.async {
                self.currentlyPlayingFile = fileName
                self.isPlaying = true
            }
        } catch {
            print("Error reproduciendo \(fileName): \(error)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        DispatchQueue.main.async {
            self.currentlyPlayingFile = nil
            self.isPlaying = false
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.currentlyPlayingFile = nil
            self.isPlaying = false
        }
    }

    /// Importa un vídeo o audio de Reel conservando el 100% de su duración completa (`_full.caf`)
    /// y además genera las partes consecutivas de 28s (`_p1.caf`, `_p2.caf`, ...) para encadenar en notificaciones.
    func importCompleteReelAudio(
        sourceURL: URL,
        prefix: String = "custom_\(Int(Date().timeIntervalSince1970))",
        completion: @escaping (Result<(fullFileName: String, partFileNames: [String], duration: Double, fullURL: URL), Error>) -> Void
    ) {
        let accessGranted = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessGranted { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let asset = AVURLAsset(url: sourceURL)
        Task {
            do {
                let durationCM = try await asset.load(.duration)
                let totalSeconds = max(1.0, CMTimeGetSeconds(durationCM))

                // 1. Exportar el AUDIO COMPLETO SIN CORTES
                let fullFileName = "\(prefix)_full.caf"
                let fullDestURL = Self.librarySoundsDirectory.appendingPathComponent(fullFileName)
                try? FileManager.default.removeItem(at: fullDestURL)

                let fullSuccess = await Self.exportSegmentToCAF(
                    asset: asset,
                    outputURL: fullDestURL,
                    startSeconds: 0,
                    durationSeconds: totalSeconds
                )

                let finalFullFileName: String
                let finalFullURL: URL
                if fullSuccess {
                    finalFullFileName = fullFileName
                    finalFullURL = fullDestURL
                } else {
                    let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
                    finalFullFileName = "\(prefix)_full.\(ext)"
                    finalFullURL = Self.librarySoundsDirectory.appendingPathComponent(finalFullFileName)
                    try? FileManager.default.removeItem(at: finalFullURL)
                    try FileManager.default.copyItem(at: sourceURL, to: finalFullURL)
                }

                // 2. Generar partes consecutivas de 28s para encadenar en UNNotificationSound si dura > 28s
                let partLen = 28.0
                let numParts = max(1, Int(ceil(totalSeconds / partLen)))
                var partNames: [String] = []

                if numParts == 1 {
                    partNames.append(finalFullFileName)
                } else {
                    for p in 0..<numParts {
                        let startT = Double(p) * partLen
                        let durT = min(partLen, max(1.0, totalSeconds - startT))
                        if durT < 0.8 { continue }
                        let pName = "\(prefix)_p\(p + 1).caf"
                        let pURL = Self.librarySoundsDirectory.appendingPathComponent(pName)
                        try? FileManager.default.removeItem(at: pURL)
                        if await Self.exportSegmentToCAF(asset: asset, outputURL: pURL, startSeconds: startT, durationSeconds: durT) {
                            partNames.append(pName)
                        }
                    }
                    if partNames.isEmpty {
                        partNames.append(finalFullFileName)
                    }
                }

                DispatchQueue.main.async {
                    completion(.success((
                        fullFileName: finalFullFileName,
                        partFileNames: partNames,
                        duration: totalSeconds,
                        fullURL: finalFullURL
                    )))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    private static func exportSegmentToCAF(
        asset: AVURLAsset,
        outputURL: URL,
        startSeconds: Double,
        durationSeconds: Double
    ) async -> Bool {
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            return false
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .caf
        exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: startSeconds, preferredTimescale: 600),
            duration: CMTime(seconds: durationSeconds, preferredTimescale: 600)
        )
        await exportSession.export()
        return exportSession.status == .completed && FileManager.default.fileExists(atPath: outputURL.path)
    }
}
