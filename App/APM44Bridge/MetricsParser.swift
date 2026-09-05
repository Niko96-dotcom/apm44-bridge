import Foundation

enum MetricsParser {
  private static let decoder = JSONDecoder()

  static func parse(line: String) -> BridgeMetricsSnapshot? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.first == "{" else { return nil }
    guard let data = trimmed.data(using: .utf8) else { return nil }
    do {
      var snapshot = try decoder.decode(BridgeMetricsSnapshot.self, from: data)
      if snapshot.estimatedRtMs <= 0 {
        snapshot.estimatedRtMs = snapshot.fillMs + 2.5
      }
      return snapshot
    } catch {
      return nil
    }
  }
}
