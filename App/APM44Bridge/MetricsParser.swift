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

  static let fixtureLine =
    #"{"fill_ms":15.200,"ratio":1.08843537,"ppm":12.00,"underruns":0,"overruns":0,"xruns":0,"estimated_rt_ms":17.700,"target_fill_ms":15.000,"src_quality":"medium"}"#
}
