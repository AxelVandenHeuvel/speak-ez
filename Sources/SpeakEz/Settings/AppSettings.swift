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

    var trigger: TriggerSpec {
        didSet {
            if let data = try? JSONEncoder().encode(trigger) {
                UserDefaults.standard.set(data, forKey: "triggerSpec")
            }
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
        if let data = UserDefaults.standard.data(forKey: "triggerSpec"),
            let spec = try? JSONDecoder().decode(TriggerSpec.self, from: data)
        {
            trigger = spec
        } else {
            // Migrate the pre-customization enum value, if one was saved.
            switch UserDefaults.standard.string(forKey: "triggerKey") {
            case "fn": trigger = .fn
            case "rightCommand": trigger = .rightCommand
            case "rightControl": trigger = .rightControl
            default: trigger = .rightOption
            }
        }
        triggerMode =
            UserDefaults.standard.string(forKey: "triggerMode")
            .flatMap(TriggerInterpreter.Mode.init(rawValue:)) ?? .hold
    }
}
