// swift-tools-version: 5.9
// MARK: - Package.swift
// Bitcoin AI Wallet
//
// Swift Package Manager manifest for the Bitcoin AI Wallet project.
// This package defines the project structure with ZERO external dependencies.
// All functionality is built using Apple system frameworks only:
// - CryptoKit (cryptographic operations, key derivation)
// - Security (Keychain access, secure storage)
// - LocalAuthentication (Face ID, Touch ID, Optic ID)
// - CoreData (persistent storage)
// - CoreImage (QR code generation/scanning)
//
// Platform: iOS 17.0+
// Language: Swift 5.9+

import PackageDescription

let package = Package(
    name: "BitcoinAIWallet",

    // MARK: - Platform Requirements

    platforms: [
        .iOS(.v17)
    ],

    // MARK: - Products

    products: [
        // Main application library containing all wallet functionality
        .library(
            name: "BitcoinAIWallet",
            targets: ["BitcoinAIWallet"]
        )
    ],

    // MARK: - Dependencies

    // ZERO external dependencies. All functionality uses system frameworks.
    dependencies: [],

    // MARK: - Targets

    targets: [

        // MARK: Main Application Target

        /// Single unified target containing all modules:
        /// - App: Entry point, AppDelegate, navigation
        /// - Core/Wallet: BIP39/32/84/86 HD wallet, secp256k1, address generation
        /// - Core/Transaction: UTXO selection, TX building, ECDSA/Schnorr signing
        /// - Core/Security: Keychain, Secure Enclave, biometrics, encryption
        /// - Network: Blockbook API, Ankr API, HTTP client, WebSocket, fees
        /// - Chat: Intent parser, response generator, conversation flow, view model
        /// - UI: SwiftUI views for chat, cards, onboarding, settings, main layout
        /// - Theme: Design system (colors, typography, spacing, shadows, icons)
        /// - Localization: L10n strings (English, Arabic, Spanish)
        /// - Data: Core Data stack, caches, user preferences
        /// - Utilities: Extensions, logger, constants, error handler, haptics
        .target(
            name: "BitcoinAIWallet",
            dependencies: [],
            path: "BitcoinAIWallet",
            exclude: [
                "Assets.xcassets",
                "Info.plist",
                "BitcoinAIWallet.entitlements",
                "Package.swift",
                "Localization/en.lproj",
                "Localization/ar.lproj",
                "Localization/es.lproj",
                "Core/Wallet/Wallet.abi.json",
                "Core/Wallet/Wallet.swiftdoc",
                "Core/Wallet/Wallet.swiftmodule",
                "Core/Wallet/Wallet.swiftsourceinfo"
            ],
            sources: [
                "App",
                "Core/Wallet",
                "Core/Transaction",
                "Core/Security",
                "Network",
                "Chat",
                "UI",
                "Theme",
                "Localization",
                "Utilities",
                "Data"
            ],
            resources: [
                .process("Localization/en.lproj"),
                .process("Localization/ar.lproj"),
                .process("Localization/es.lproj")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),

        // MARK: Test Target

        /// Unit and integration tests for the full application.
        .testTarget(
            name: "BitcoinAIWalletTests",
            dependencies: ["BitcoinAIWallet"],
            path: "Tests/BitcoinAIWalletTests",
            swiftSettings: [
                .define("TESTING")
            ]
        )
    ],

    // MARK: - Swift Language Version

    swiftLanguageVersions: [.v5]
)
