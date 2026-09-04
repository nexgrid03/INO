# iOS Export Compliance Audit & Encryption Declaration

## Overview
This document certifies the encryption audit performed on the INO iOS application to ensure full compliance with US Export Administration Regulations (EAR) and Apple App Store Export Compliance submission rules.

## Audit Findings

### 1. Cryptographic Primitives & Usage
- **Local Vault Payload Encryption**: AES-256-GCM (via standard `cryptography` / `VaultCrypto` routines). Used exclusively for encrypting user documents and secret metadata at rest on device.
- **Secure Credential Storage**: Native iOS Keychain (via `flutter_secure_storage`). Used for persisting session refresh tokens and PIN / Biometric master keys.
- **Network Transport Encryption**: Industry-standard TLS 1.2 / TLS 1.3 via HTTPS (App Transport Security compliant).

### 2. Export Regulations & Exemption Status
Under US EAR Category 5, Part 2 (Information Security), encryption hardware/software is exempt from formal export reporting when used strictly for:
- Standard user authentication and access control.
- Protecting user data at rest stored locally on consumer equipment (EAR Category 5 Part 2 Note 4 - Mass Market Exemption).
- Standard client-to-server TLS/HTTPS communications.

### 3. Apple App Store Setting
- **`ITSAppUsesNonExemptEncryption`**: Set to `<false/>` in `ios/Runner/Info.plist`.
- **Justification**: INO does not use non-exempt proprietary or custom encryption algorithms. All cryptographic functionality falls squarely under Category 5 Part 2 Note 4 mass market exemptions.

## Summary for App Store Review
> "The INO application uses standard TLS 1.2+ for network transport, native iOS Keychain services for secure token storage, and standard AES-256-GCM for encrypting local user vault files. All cryptographic usage qualifies for exemption under US EAR Category 5 Part 2 Note 4 and Note 1(b). No specialized or non-exempt encryption functions are included."
