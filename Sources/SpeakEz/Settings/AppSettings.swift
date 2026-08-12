import Foundation
import Observation
import SpeakEzKit

/// UserDefaults-backed app settings.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var refinementLevel: RefinementLevel {
        didSet {
            UserDefaults.standard.set(refinementLevel.rawValue, forKey: "refinementLevel")
        }
    }

    var triggerKey: TriggerKey {
        didSet {
            UserDefaults.standard.set(triggerKey.rawValue, forKey: "triggerKey")
        }
    }

    var triggerMode: TriggerInterpreter.Mode {
        didSet {
            UserDefaults.standard.set(triggerMode.rawValue, forKey: "triggerMode")
        }
    }

    private init() {
        refinementLevel =
            UserDefaults.standard.string(forKey: "refinementLevel")
            .flatMap(RefinementLevel.init(rawValue:)) ?? .basic
        triggerKey =
            UserDefaults.standard.string(forKey: "triggerKey")
            .flatMap(TriggerKey.init(rawValue:)) ?? .rightOption
        triggerMode =
            UserDefaults.standard.string(forKey: "triggerMode")
            .flatMap(TriggerInterpreter.Mode.init(rawValue:)) ?? .hold
    }
}
