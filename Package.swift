// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VPNWidget",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VPNCore", targets: ["VPNCore"]),
        .library(name: "VPNUI", targets: ["VPNUI"]),
        .executable(name: "vpnd", targets: ["vpnd"]),
        .executable(name: "vpn-preview", targets: ["vpn-preview"]),
        .executable(name: "vpn-icon", targets: ["vpn-icon"]),
        .executable(name: "vpn-gif", targets: ["vpn-gif"]),
    ],
    targets: [
        .target(name: "VPNCore"),
        .target(name: "VPNUI", dependencies: ["VPNCore"]),
        .executableTarget(name: "vpnd", dependencies: ["VPNCore"]),
        // Renders the widget views to PNG, so layout can be checked without Notification Center.
        .executableTarget(name: "vpn-preview", dependencies: ["VPNCore", "VPNUI"]),
        // Draws the app icon, so the artwork is reproducible from code instead of a binary nobody can edit.
        .executableTarget(name: "vpn-icon"),
        // Renders the README animations from synthetic data, so no screen recording (and nothing personal) is involved.
        .executableTarget(name: "vpn-gif", dependencies: ["VPNCore", "VPNUI"]),
        .testTarget(name: "VPNCoreTests", dependencies: ["VPNCore"]),
    ]
)
