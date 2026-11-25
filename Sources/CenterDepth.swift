import ARKit

extension ARDepthData {
    func centralDistance() -> Float? {
        let depth = depthMap
        guard let confidence = confidenceMap,
              CVPixelBufferGetWidth(confidence) == CVPixelBufferGetWidth(depth),
              CVPixelBufferGetHeight(confidence) == CVPixelBufferGetHeight(depth),
              CVPixelBufferLockBaseAddress(depth, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }
        guard CVPixelBufferLockBaseAddress(confidence, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) }
        guard let distances = CVPixelBufferGetBaseAddress(depth),
              let scores = CVPixelBufferGetBaseAddress(confidence) else { return nil }
        var samples = [Float]()
        for yPercent in [47, 50, 53] {
            let y = CVPixelBufferGetHeight(depth) * yPercent / 100
            let scoreRow = scores.advanced(by: y * CVPixelBufferGetBytesPerRow(confidence)).assumingMemoryBound(to: UInt8.self)
            let depthRow = distances.advanced(by: y * CVPixelBufferGetBytesPerRow(depth)).assumingMemoryBound(to: Float.self)
            for xPercent in [47, 50, 53] {
                let x = CVPixelBufferGetWidth(depth) * xPercent / 100
                if scoreRow[x] >= ARConfidenceLevel.medium.rawValue { samples.append(depthRow[x]) }
            }
        }
        return DepthEstimate.meters(samples)
    }
}
