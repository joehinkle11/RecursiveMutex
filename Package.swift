// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RecursiveMutex",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "RecursiveMutex",
            targets: ["RecursiveMutex"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "RecursiveMutex",
            swiftSettings: [
                .enableExperimentalFeature("StaticExclusiveOnly"),
                .unsafeFlags([
                    "-Xfrontend",
                    "-disable-availability-checking", // we should remove this flag once swift 6.4 is out and we can use Ref and MutableRef properly
                ])
            ]
        ),
        .testTarget(
            name: "RecursiveMutexTests",
            dependencies: ["RecursiveMutex"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
