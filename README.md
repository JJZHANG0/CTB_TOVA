# TOVA
面向视障用户的原生 iPhone 空间感知助手。使用 Xcode 打开 TOVA.xcodeproj，选择 TOVA scheme。在 Signing & Capabilities 中设置自己的开发团队后可运行到 iPhone。Bundle ID 为 com.tova.spatial，最低系统 iOS 17。

开发前先阅读 PRODUCT_SPEC.md、DESIGN_SYSTEM.md、TECHNICAL_ARCHITECTURE.md 和 DEVELOPMENT_LOG.md。产品规格包含长期目标，已验证范围见开发日志。

## 本地逻辑测试
```sh
swiftc Sources/Command.swift Sources/SceneEvidence.swift Sources/DepthEstimate.swift Tests/main.swift -o /tmp/tova-check && /tmp/tova-check
```
