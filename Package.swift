// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "calc",
    platforms: [
       .macOS(.v13)
    ],
    products: [
        .executable(name: "calc", targets: ["calc"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-server/swift-aws-lambda-runtime.git", from: "1.0.0-alpha"),
    ],
    targets: [
        .executableTarget(
            name: "calc", dependencies: [
                .product(name: "AWSLambdaRuntime", package: "swift-aws-lambda-runtime"),
            ]),
    ]
)
