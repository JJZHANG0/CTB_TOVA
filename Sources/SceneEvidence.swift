import Foundation

struct SceneEvidence {
    private var previous = "未知"
    private var consecutive = 0
    mutating func update(labels: [String]) -> String {
        let indoor = Set(["living_room", "bedroom", "kitchen", "corridor", "office", "bathroom", "sofa", "refrigerator"])
        let outdoor = Set(["street", "highway", "sidewalk", "crosswalk", "forest", "beach", "mountain"])
        let words = Set(labels.flatMap { $0.lowercased().components(separatedBy: ", ") })
        let inside = !words.isDisjoint(with: indoor)
        let outside = !words.isDisjoint(with: outdoor)
        let candidate = inside == outside ? "未知" : inside ? "室内" : "室外"
        consecutive = candidate == previous ? consecutive + 1 : 1
        previous = candidate
        return consecutive >= 2 ? candidate : "未知"
    }
}
