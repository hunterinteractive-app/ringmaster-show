import Foundation
let paths = [FileManager.default.currentDirectoryPath]
for path in paths {
    let values = try URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityForOpportunisticUsageKey])
    var result: [String: Any] = ["path": path]
    if let x = values.volumeTotalCapacity { result["total_bytes"] = x }
    if let x = values.volumeAvailableCapacity { result["available_bytes"] = x }
    if let x = values.volumeAvailableCapacityForImportantUsage { result["important_usage_bytes"] = x }
    if let x = values.volumeAvailableCapacityForOpportunisticUsage { result["opportunistic_usage_bytes"] = x }
    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8)!)
}
