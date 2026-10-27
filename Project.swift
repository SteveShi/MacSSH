import ProjectDescription

let project = Project(
    name: "MacSSH",
    packages: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
        .package(url: "https://github.com/SteveShi/MactermKit.git", from: "1.0.29"),
        .package(url: "https://github.com/SteveShi/SSH2Kit.git", from: "1.3.29")
    ],
    settings: .settings(
        base: [
            "MACOSX_DEPLOYMENT_TARGET": "26.0",
            "SWIFT_VERSION": "6.0",
            "PRODUCT_NAME": "MacSSH",
            "MARKETING_VERSION": "2.4.0",
            "CURRENT_PROJECT_VERSION": "20400",
            "ARCHS": "arm64",
            "ONLY_ACTIVE_ARCH": "NO"
        ]
    ),
    targets: [
        .target(
            name: "macsshd",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "com.steveshi.macssh.daemon",
            deploymentTargets: .macOS("26.0"),
            sources: [
                "Targets/MacSSHDaemonShared/**",
                "Targets/MacSSHDaemon/**"
            ],
            settings: .settings(
                base: [
                    "PRODUCT_NAME": "macsshd"
                ]
            )
        ),
        .target(
            name: "macssh-cli",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "com.steveshi.macssh.cli",
            deploymentTargets: .macOS("26.0"),
            sources: [
                "Targets/MacSSHDaemonShared/**",
                "Targets/MacSSHCLI/**"
            ],
            settings: .settings(
                base: [
                    "PRODUCT_NAME": "macssh-cli"
                ]
            )
        ),
        .target(
            name: "MacSSH",
            destinations: .macOS,
            product: .app,
            bundleId: "com.steveshi.macssh",
            deploymentTargets: .macOS("26.0"),
            sources: [
                "Targets/MacSSHApp/**",
                "Targets/MacSSHCore/**",
                "Targets/MacSSHTerminal/**",
                "Targets/MacSSHDaemonShared/**"
            ],
            resources: [
                "Targets/MacSSHApp/App/Assets.xcassets",
                "Targets/MacSSHApp/App/Localizable.xcstrings",
                "Targets/MacSSHApp/App/Themes.json"
            ],
            scripts: [
                .post(
                    script: """
                    mkdir -p "$TARGET_BUILD_DIR/$EXECUTABLE_FOLDER_PATH"
                    cp -f "$BUILT_PRODUCTS_DIR/macsshd" "$TARGET_BUILD_DIR/$EXECUTABLE_FOLDER_PATH/macsshd"
                    cp -f "$BUILT_PRODUCTS_DIR/macssh-cli" "$TARGET_BUILD_DIR/$EXECUTABLE_FOLDER_PATH/macssh-cli"
                    chmod 755 "$TARGET_BUILD_DIR/$EXECUTABLE_FOLDER_PATH/macsshd" "$TARGET_BUILD_DIR/$EXECUTABLE_FOLDER_PATH/macssh-cli"
                    """,
                    name: "Embed Helper Executables",
                    basedOnDependencyAnalysis: false
                )
            ],
            dependencies: [
                .target(name: "macsshd"),
                .target(name: "macssh-cli"),
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
