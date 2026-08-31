import AVFoundation
import Foundation

struct ValidatedLocalAudio {
    let duration: TimeInterval
    let byteSize: Int64
}

enum LocalAudioValidationError: LocalizedError, Equatable {
    case missing
    case empty
    case unreadable(String)
    case noDuration

    var errorDescription: String? {
        switch self {
        case .missing: "The saved audio file is missing from this iPhone."
        case .empty: "The saved audio file is empty."
        case .unreadable(let detail): "The saved audio file is incomplete or unreadable. \(detail)"
        case .noDuration: "The saved audio file has no usable duration."
        }
    }
}

enum LocalAudioValidator {
    static func validate(url: URL) throws -> ValidatedLocalAudio {
        guard FileManager.default.fileExists(atPath: url.path) else { throw LocalAudioValidationError.missing }
        let byteSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard byteSize > 0 else { throw LocalAudioValidationError.empty }

        do {
            let file = try AVAudioFile(forReading: url)
            let sampleRate = file.fileFormat.sampleRate
            let duration = sampleRate > 0 ? Double(file.length) / sampleRate : 0
            guard duration > 0, duration.isFinite else { throw LocalAudioValidationError.noDuration }
            return ValidatedLocalAudio(duration: duration, byteSize: byteSize)
        } catch let error as LocalAudioValidationError {
            throw error
        } catch {
            throw LocalAudioValidationError.unreadable(error.localizedDescription)
        }
    }
}
