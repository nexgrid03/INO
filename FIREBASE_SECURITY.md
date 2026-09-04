# Firebase Security & Configuration Audit

## Overview
This document details the security verification and API restrictions applied to the INO Firebase project (`inoapp-b0101`).

## 1. Firebase API Key & Project Restrictions

### Android App Restrictions (`1:205011674878:android:f765ea1cb02cdee19a67af`)
- **Package Restriction**: Enforced to `com.ino.app` (or package name configured in `google-services.json`).
- **SHA-1 Fingerprint**: Registered release & debug SHA-1 signing certificates in Firebase Console.
- **SHA-256 Fingerprint**: Registered release SHA-256 certificate for App Check & OAuth verification.

### iOS App Restrictions (`1:205011674878:ios:ae329a4d4f44ee039a67af`)
- **Bundle ID Restriction**: Enforced to `com.ino.app`.

### Web & Windows Clients
- **HTTP Referrer Restrictions**: Web API keys restricted to official domain origins (`ino.app`, `*.ino.app`).

## 2. API Scope & Feature Deactivation
- **Firebase Cloud Messaging (FCM)**: ACTIVE (Used for push notifications via `firebase_messaging`).
- **Firebase Analytics**: INACTIVE. SDK is not included in `pubspec.yaml`, and auto-collection is explicitly deactivated:
  - **Android**: `<meta-data android:name="firebase_analytics_collection_deactivated" android:value="true" />` in `AndroidManifest.xml`.
  - **iOS**: `<key>FIREBASE_ANALYTICS_COLLECTION_DEACTIVATED</key><true/>` in `Info.plist`.
- **Firebase Crashlytics / Performance Monitoring**: INACTIVE. Unused SDK dependencies omitted.
