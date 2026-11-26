import Foundation
let commands: [(String, Command)] = [
    ("执行空间描述", .start), ("请你执行空间描述", .start), ("开启空间描述", .start),
    ("关闭空间描述", .stop), ("退出语音待命", .exit), ("切换简洁描述", .level("简洁")),
    ("切换标准描述", .level("标准")), ("切换详细描述", .level("详细"))
]
for (words, expected) in commands {
    precondition(Command("TOVA，" + words) == expected)
    precondition(Command("托瓦 " + words) == expected)
    precondition(Command(words) == nil)
    precondition(Command("TOVA，" + words + "是什么意思") == nil)
}
var scene = SceneEvidence()
precondition(scene.update(labels: ["bedroom"]) == "未知")
precondition(scene.update(labels: ["bedroom"]) == "室内")
precondition(scene.update(labels: ["street"]) == "未知")
precondition(scene.update(labels: ["street"]) == "室外")
precondition(scene.update(labels: ["street", "bedroom"]) == "未知")
print("37 command and scene assertions passed")
precondition(DepthEstimate.meters([]) == nil)
precondition(DepthEstimate.meters([0, .nan, .infinity, 1, 1]) == nil)
precondition(DepthEstimate.meters([1, 1, 1, 1, 4]) == 1)
precondition(DepthEstimate.meters([1, 2, 3, 4, 5]) == nil)
print("4 depth assertions passed")
for q in ["前方有什么", "左前方有什么", "右侧是什么", "附近有没有台阶", "详细描述一下这个空间", "重复上一条描述"] {
    precondition(Command("TOVA，" + q + "？") == .ask(q))
    precondition(Command(q) == nil)
}
print("12 query assertions passed")
for wake in Command.wakeWords {
    precondition(Command(wake + "，开启空间描述") == .start)
    precondition(Command(wake) == nil)
    precondition(Command("听说" + wake + "开启空间描述") == nil)
}
print("Wake variant checks passed")
