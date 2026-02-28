# Aura Wallet

AI-powered Bitcoin wallet for iOS. Built entirely in Swift with **zero external dependencies** — all cryptography implemented from scratch using only Apple system frameworks.

## Features

- **AI Chat Interface** — Natural language wallet operations ("send 0.01 BTC to bc1q...")
- **HD Wallet** — BIP39 mnemonic, BIP44/49/84/86 derivation (Legacy, P2SH, SegWit, Taproot)
- **Full Address Discovery** — Gap limit of 20 per address type per chain
- **Transaction Signing** — BIP143 (P2WPKH) and BIP341 (Taproot) with signature verification
- **Real-time Fee Estimation** — Live network fee rates with slow/medium/fast tiers
- **Biometric + Passcode Auth** — Face ID / Touch ID with passcode fallback and lockout
- **Seed Phrase Security** — Screen recording detection, screenshot prevention, clipboard auto-expiry
- **Multi-language** — English, Spanish, Arabic
- **Dark Mode First** — Custom design system with warm tones

## Requirements

- **Xcode 16.0+** (with iOS 17.0+ SDK)
- **iOS 17.0+** deployment target
- **Swift 5.9+**
- macOS for building

## Getting Started

### 1. Clone the repo

```bash
git clone https://github.com/devdasx/Aura-Wallet.git
cd Aura-Wallet
```

### 2. Generate the Xcode project (optional — .xcodeproj is included)

If you have [XcodeGen](https://github.com/yonaskolb/XcodeGen) installed:

```bash
xcodegen generate
```

### 3. Open in Xcode

```bash
open BitcoinAIWallet.xcodeproj
```

### 4. Build and run

Select an iPhone simulator (iPhone 15 Pro or later recommended) and hit **Cmd+R**.

> No CocoaPods, SPM dependencies, or Carthage setup needed. The project compiles with zero external packages.

## Architecture

```
BitcoinAIWallet/
  App/              — App entry point, AppDelegate
  Chat/             — Intent parser, conversation flow, response generator
  Core/
    Security/       — Keychain, biometrics, Secure Enclave
    Transaction/    — ECDSA, Schnorr, transaction builder/signer
    Wallet/         — HD key derivation, BIP39, address generation
  Data/             — SwiftData models, UTXO store, preferences
  Localization/     — en/es/ar string files
  Network/          — Blockbook API, fee estimator, WebSocket, HTTP client
  Theme/            — Colors, typography, spacing, icons
  UI/               — SwiftUI views (Chat, Cards, Onboarding, Settings, Sidebar)
  Utilities/        — Constants, extensions, haptics, logging
```

**Key design decisions:**
- MVVM + Clean Architecture
- All Bitcoin amounts use `Decimal` (never `Double`)
- secp256k1 elliptic curve implemented from scratch
- RIPEMD-160 hash implemented from scratch
- Certificate pinning for API endpoints
- Ephemeral URLSession (no disk cache)

## Cryptography

Everything is built from scratch — no OpenSSL, no libsecp256k1, no BoringSSL:

| Component | Implementation |
|-----------|---------------|
| secp256k1 | Custom finite field + curve arithmetic (EllipticCurve.swift) |
| ECDSA | RFC 6979 deterministic nonce, BIP62 low-S (ECDSASigner.swift) |
| Schnorr | BIP340 (SchnorrSigner.swift) |
| SHA-256 | Apple CryptoKit |
| RIPEMD-160 | Custom implementation (KeyDerivation.swift) |
| HMAC-SHA512 | Apple CryptoKit |
| PBKDF2 | Apple CommonCrypto |
| Bech32/Bech32m | Custom encoder/decoder with checksum validation |
| Base58Check | Custom encoder/decoder with checksum validation |
| BIP39 | 2048-word English wordlist, mnemonic-to-seed |
| BIP32 | Hierarchical deterministic key derivation |
| BIP44/49/84/86 | Multi-account address derivation paths |
| BIP143 | SegWit v0 transaction digest |
| BIP341 | Taproot transaction digest |

## Security

- Seed stored in iOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- Private keys zeroed from memory after signing (`defer { data.resetBytes(...) }`)
- Certificate pinning for Blockbook/Ankr/Coinbase endpoints
- Clipboard auto-expires after 60 seconds (localOnly)
- Screen recording detection blocks seed phrase display
- Passcode lockout after failed attempts (30s cooldown)
- Seed phrase detection in chat messages (warns and redacts)
- Testnet address rejection on mainnet wallet
- Fee rate upper bound validation (max 10,000 sat/vB)
- Signature verification after signing (ECDSA + Schnorr)

## API

The wallet connects to:
- **Blockbook** (via Ankr premium) — Blockchain data, address balances, UTXOs, transaction broadcast
- **Coinbase** — BTC price feeds
- **Trezor Blockbook** — WebSocket for real-time notifications

## License

MIT

## Disclaimer

This is an experimental wallet for educational purposes. Use at your own risk. Always verify transactions before broadcasting. Never store significant amounts of Bitcoin in any software wallet without thorough security review.
