import AVFoundation
import Foundation

/// 리허설 낭독 엔진 — AVSpeechSynthesizer를 async/await로 감싸,
/// 대사 하나를 끝까지 말할 때까지 리허설 루프를 기다리게 한다.
@MainActor
final class RehearsalNarrator: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?

    /// 낭독 진행 콜백 — 지금까지 말한 글자 수. 타자기 리빌을 TTS 속도에 동기화한다.
    var onProgress: ((Int) -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// 텍스트 하나를 말하고 끝날 때까지 대기. stop()이 불리면 즉시 돌아온다.
    func speak(_ text: String, voice: AVSpeechSynthesisVoice?, rate: Float) async {
        // 이전 발화가 정리되지 않았다면 먼저 끊는다 (연속 재생 안전장치)
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            continuation = cont
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice
            utterance.rate = rate
            synthesizer.speak(utterance)
        }
    }

    func setPaused(_ paused: Bool) {
        if paused {
            synthesizer.pauseSpeaking(at: .word)
        } else if synthesizer.isPaused {
            synthesizer.continueSpeaking()
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        finish() // didCancel이 안 오는 경로 대비 — 이중 호출은 finish가 무해하게 처리
    }

    private func finish() {
        continuation?.resume()
        continuation = nil
    }

    // MARK: AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        let spoken = characterRange.location + characterRange.length
        Task { @MainActor in self.onProgress?(spoken) }
    }
}

/// 캐스트 → 목소리 배정. 설치된 현재 언어 보이스를 캐스트 순서대로 돌려가며 할당해,
/// 캐릭터마다 다른 목소리가 나게 한다 (보이스가 하나뿐이면 모두 같은 목소리).
enum RehearsalVoiceCasting {
    /// 현재 언어의 설치 보이스 목록 — 캐스트 편집 팝오버의 수동 배정 메뉴용.
    static func availableVoices(languageCode: String) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(languageCode) }
            .sorted { $0.name < $1.name }
    }

    /// identifier → 표시 이름 (미설치면 nil).
    static func voiceName(identifier: String) -> String? {
        AVSpeechSynthesisVoice(identifier: identifier)?.name
    }

    static func voice(languageCode: String, castIndex: Int?) -> AVSpeechSynthesisVoice? {
        let candidates = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(languageCode) }
            .sorted { $0.identifier < $1.identifier }
        guard !candidates.isEmpty else {
            return AVSpeechSynthesisVoice(language: languageCode)
        }
        guard let castIndex else { return candidates[0] }
        return candidates[castIndex % candidates.count]
    }
}
