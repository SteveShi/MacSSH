import ProjectDescription

let project = Project(
    name: "MacSSH",
    packages: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
        .package(url: "https://github.com/SteveShi/libghostty-swift.git", from: "1.0.13"),
        .package(url: "https://github.com/SteveShi/libssh2-swift.git", from: "1.3.12")
    ],
    settings: .settings(
        base: [
            "MACOSX_DEPLOYMENT_TARGET": "15.0",
            "SWIFT_VERSION": "6.0",
            "PRODUCT_NAME": "MacSSH",
            "MARKETING_VERSION": "1.9.16",
            "CURRENT_PROJECT_VERSION": "1916",
            "ARCHS": "arm64",
            "ONLY_ACTIVE_ARCH": "NO"
        ]
    ),
    targets: [
        .target(
            name: "MacSSH",
            destinations: .macOS,
            product: .app,
            bundleId: "com.steveshi.macssh",
            deploymentTargets: .macOS("15.0"),
            sources: ["Targets/**"],
            resources: [
                "Targets/MacSSHApp/App/Assets.xcassets",
                "Targets/MacSSHApp/App/Localizable.xcstrings"
            ],
            dependencies: [
                .package(product: "Sparkle"),
                .package(product: "libghostty-swift"),
                .package(product: "libssh2-swift")
            ],
            settings: .settings(
                base: [
                    "INFOPLIST_FILE": "Targets/MacSSHApp/App/Info.plist",
                    "PRODUCT_BUNDLE_IDENTIFIER": "com.steveshi.macssh",
                    "MARKETING_VERSION": "$(MARKETING_VERSION)",
                    "CURRENT_PROJECT_VERSION": "$(CURRENT_PROJECT_VERSION)",
                    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                    "SWIFT_EMIT_LOC_STRINGS": "YES",
                    "OTHER_LDFLAGS": "-lc++ -framework Carbon",
                    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks"
                ]
            )
        )
    ]
)
