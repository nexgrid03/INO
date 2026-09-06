# INO (Intelligent Network Organizer) - Privacy Policy

**Effective Date:** September 4, 2026  
**Last Updated:** September 4, 2026  

Welcome to **INO (Intelligent Network Organizer)** ("Application", "Service", "we", "us", or "our"). INO is operated by **INO Technologies Private Limited** ("Company"). We are committed to protecting your privacy, securing your personal data, and maintaining full compliance with global and Indian privacy laws, including the **Digital Personal Data Protection Act, 2023 (DPDP Act, India)** and the **General Data Protection Regulation (GDPR, EU)**.

This Privacy Policy describes how we collect, use, store, share, retain, and delete your personal data when you use the INO mobile application, website, and associated Edge services.

---

## 1. App Owner & Data Fiduciary Details

- **Legal Entity:** INO Technologies Private Limited
- **Official Address:** 101 Innovation Towers, HSR Layout, Bengaluru, Karnataka 560102, India
- **Privacy Contact / Data Protection Officer:** `privacy@inoapp.in`
- **Customer Support Email:** `support@inoapp.in`

---

## 2. Age Restriction (18+ Requirement)

INO is intended solely for adult users who are **18 years of age or older**. We do not knowingly collect, process, or solicit personal data from anyone under 18 years of age. If you are under 18, please do not attempt to register an account or transmit any personal information to us. If we discover that personal data has been collected from a person under 18, we will immediately initiate account deletion and purge all associated records.

---

## 3. Information We Collect and Processing Purposes

We collect personal data that you provide directly, as well as metadata generated during your use of the application.

| Data Category | Specific Data Points | Purpose of Processing | Legal Basis |
|---|---|---|---|
| **Account & Authentication** | Full Name, Email Address, Phone Number, Password (hashed), Google OAuth Profile (avatar/email). | Account creation, authentication, multi-factor authentication (MFA), password reset. | Contract Performance |
| **Document Storage & Vaults** | Scanned document images, PDF files, document titles, notes, categories, expiry dates, tax records, property & investment details. | Storage, organization, reminder notifications, and document retrieval. | User Consent & Contract |
| **Document Extraction & OCR** | Identity document numbers (Aadhaar, PAN, Passport, Driving License), Name, DOB, Gender. | Extracted on-device via ML Kit for auto-filling and search. Raw images do not leave the device for OCR. | User Consent |
| **Passwords & Credentials** | Saved logins, passwords, security notes. | End-to-end encrypted locally in Password Store using user-provided master passphrase. | User Consent |
| **Family Vaults & Sharing** | Invited member emails, phone numbers, share permissions, document share links. | Facilitating secure file sharing and family vault management. | User Consent |
| **Device & Push Tokens** | Device Model, OS Version, Firebase FCM Push Token, App Language. | Delivery of exact-time reminder push notifications and security alerts. | Legitimate Interest |
| **Biometric Preference** | Local boolean preference (`biometric_enabled`). Biometric templates (fingerprint/Face ID) remain on-device OS. | Local app unlock protection. INO never receives or transmits biometric raw data. | User Consent |

---

## 4. Third-Party Service Disclosures

We share data with third-party service providers strictly to deliver our services. We do not sell your personal data to third parties.

1. **Supabase Inc.** (Database, Auth, Object Storage & Edge Functions)
   - *Role:* Primary cloud database and encrypted file storage provider.
   - *Data Sent:* Account profile, document attachments, database records.
2. **Google Firebase Cloud Messaging (FCM)** (Push Notifications)
   - *Role:* Delivery pipe for reminder push notifications.
   - *Data Sent:* Data-only payload notifications and device push tokens.
3. **Google Sign-In & Google ML Kit**
   - *Role:* OAuth authentication and on-device machine learning (OCR & Document Scanner).
   - *Data Sent:* Auth tokens during sign-in. ML Kit runs 100% on-device; scan images are never sent to Google servers.
4. **Google Fonts & Vercel**
   - *Role:* Typography delivery and web frontend hosting for share links (`https://share.inoapp.com`).
5. **Swissquote & Frankfurter API**
   - *Role:* Anonymized currency exchange rate queries for net worth calculations (no PII transmitted).
6. **Operating System Speech Services (Android / iOS)**
   - *Role:* Processing user voice navigation commands when explicitly initiated.

---

## 5. Data Security Controls

We enforce industry-standard security controls to protect your data:
- **TLS/HTTPS Encryption in Transit:** All client-to-server traffic is encrypted using TLS 1.3 / HTTPS.
- **Access Controls & Row-Level Security (RLS):** Database tables and cloud storage objects enforce strictly owner-isolated policies (`auth.uid() = owner`).
- **Client-Encrypted Password Vault:** Passwords stored in the password vault are encrypted using AES-256-GCM with PBKDF2 key derivation from your master passphrase.
- **Biometric Gate:** App-lock overlay requires native OS fingerprint or Face ID verification.

---

## 6. Data Retention Policy

- **Active Accounts:** Data is retained for as long as your account remains active.
- **Account Deletion:** When you request account deletion (via in-app Settings → Delete Account or at `https://share.inoapp.com/delete-account`), the server-side `delete_account()` function permanently purges your user profile, storage files, database records, vault memberships, and `auth.users` row.
- **Notification Logs & Audit Logs:** System notification logs (`push_log`) are automatically pruned after 90 days.

---

## 7. Your Data Rights

You possess the following rights regarding your personal data:
- **Right to Access & Export:** You may export your entire document library and data backup directly from Profile → Export My Data.
- **Right to Rectification:** You can edit your profile details and document records directly within the app.
- **Right to Permanent Deletion:** You can delete your account and all associated data at any time.
- **Right to Withdraw Consent:** You can disable biometric lock, revoke camera/mic permissions, or delete your account to withdraw consent.

---

## 8. India DPDP Act 2023 Compliance Notice

For users in India, INO acts as a **Data Fiduciary** under the Digital Personal Data Protection Act, 2023. You have the right to:
- Seek summary of personal data processed.
- Request correction, completion, or updating of your personal data.
- Request erasure of personal data.
- Nominate another individual to exercise your rights in case of death or incapacity.
- Register a grievance with our Data Protection Officer at `privacy@inoapp.in`.

---

## 9. EU GDPR Compliance Notice

For users in the European Economic Area (EEA), you have rights under the General Data Protection Regulation (GDPR):
- Right to restriction of processing.
- Right to data portability.
- Right to object to processing.
- Right to lodge a complaint with your local Data Protection Authority.

---

## 10. Contact Us

If you have questions, feedback, or privacy grievances, contact us at:
- **Email:** `privacy@inoapp.in`
- **Support:** `support@inoapp.in`
- **Address:** INO Technologies Private Limited, 101 Innovation Towers, HSR Layout, Bengaluru 560102, India
