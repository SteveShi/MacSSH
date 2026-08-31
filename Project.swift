import ProjectDescription

let project = Project(
    name: "MacSSH",
    packages: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
        .package(url: "https://github.com/SteveShi/MactermKit.git", from: "1.0.20"),
        .package(url: "https://github.com/SteveShi/SSH2Kit.git", from: "1.3.15")
    ],
    settings: .settings(
        base: [
            "MACOSX_DEPLOYMENT_TARGET": "26.0",
            "SWIFT_VERSION": "6.0",
            "PRODUCT_NAME": "MacSSH",
            "MARKETING_VERSION": "2.0.7",
            "CURRENT_PROJECT_VERSION": "20700",
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
            deploymentTargets: .macOS("26.0"),
            sources: ["Targets/**"],
            resources: [
                "Targets/MacSSHApp/App/Assets.xcassets",
                "Targets/MacSSHApp/App/Localizable.xcstrings"
            ],
            dependencies: [
                .package(product: "Sparkle"),
                .package(product: "MactermKit"),
                .package(product: "SSH2Kit")
            ],
            settings: .settings(
                base: [
                    "INFOPLIST_FILE": "Targets/MacSSHApp/App/Info.plist",
                    "PRODUCT_BUNDLE_IDENTIFIER": "com.steveshi.macssh",
                    "MARKETING_VERSION": "$(MARKETING_VERSION)",
                    "CURRENT_PROJECT_VERSION": "$(CURRENT_PROJECT_VERSION)",
                    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                    "SWIFT_EMIT_LOC_STRINGS": "YES",
                    "OTHER_LDFLAGS": "-lc++ -framework Carbon -Xlinker -w",
                    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks"
                ]
            )
        )
    ]
)
