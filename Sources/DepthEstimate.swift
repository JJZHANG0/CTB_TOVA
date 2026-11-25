enum DepthEstimate {
    static func meters(_ samples: [Float]) -> Float? {
        let valid = samples.filter { $0.isFinite && (0.2...5).contains($0) }.sorted()
        guard valid.count >= 5 else { return nil }
        let median = valid[valid.count / 2]
        let agreeing = valid.filter { abs($0 - median) <= max(0.12, median * 0.15) }
        return agreeing.count > valid.count / 2 ? median : nil
    }
}
