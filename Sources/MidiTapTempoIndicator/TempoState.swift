import Combine
import Foundation

final class TempoState: ObservableObject {
    @Published var currentBPM: Double?
}
