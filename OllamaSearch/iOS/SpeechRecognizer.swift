#if os(iOS)
import Speech
import AVFoundation
import SwiftUI

@Observable @MainActor
final class SpeechRecognizer {
    var isRecording = false
    var transcript  = ""
    var error: String? = nil

    private var audioEngine:        AVAudioEngine = AVAudioEngine()
    private var recognitionTask:    SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var silenceTimer:       Timer?
    private var hardStopTimer:      Timer?

    func start() async {
        guard await requestPermissions() else { return }
        do {
            try startRecognition()
        } catch {
            self.error = "Could not start recording: \(error.localizedDescription)"
            stopRecognition()
        }
    }

    func stop() {
        stopRecognition()
    }

    // MARK: — Private

    private func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            error = "Speech recognition is disabled. Enable it in Settings → Privacy & Security → Speech Recognition."
            return false
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            error = "Microphone access is required. Enable it in Settings → Privacy & Security → Microphone."
            return false
        }
        return true
    }

    private func startRecognition() throws {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            error = "Speech recognition is not available right now."
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let inputNode = audioEngine.inputNode
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputNode.outputFormat(forBus: 0)) { [weak self] buf, _ in
            self?.recognitionRequest?.append(buf)
        }
        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true

        hardStopTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stopRecognition() }
        }
        resetSilenceTimer()

        recognitionTask = recognizer.recognitionTask(with: recognitionRequest!) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal { self.stopRecognition() }
                    else              { self.resetSilenceTimer() }
                }
                if error != nil { self.stopRecognition() }
            }
        }
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stopRecognition() }
        }
    }

    private func stopRecognition() {
        silenceTimer?.invalidate();  silenceTimer = nil
        hardStopTimer?.invalidate(); hardStopTimer = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        audioEngine = AVAudioEngine()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRecording = false
    }
}
#endif
