# INO (Intelligent Network Organizer) - Account Deletion Policy & Web Portal

**Public Deletion Web Page URL:** `https://share.inoapp.com/delete-account`

At **INO Technologies Private Limited**, we respect your right to complete control over your personal data. You can delete your account and all associated personal data at any time — either directly within the INO mobile application or via our public Account Deletion web page.

---

## How to Delete Your Account

### Option 1: Inside the INO Mobile App (Instant & Automatic)
1. Open the **INO** app and log into your account.
2. Go to **Profile** (bottom navigation tab) ➔ tap **Delete Account**.
3. Re-authenticate your current password for security verification.
4. Confirm deletion.
5. The app executes the `delete_account()` server function, purges your account and files, and returns you to the sign-in screen.

### Option 2: Web Account Deletion Request Form
If you no longer have the INO app installed, visit:
👉 **`https://share.inoapp.com/delete-account`**

Submit your registered account email address. You will receive an automated verification code to confirm ownership, after which your account and all data will be permanently deleted.

Alternatively, send a deletion request email from your registered email address to:
📧 **`delete-account@inoapp.in`** or **`privacy@inoapp.in`**

---

## What Data Gets Permanently Deleted?

When your account is deleted, our server-side `delete_account()` RPC executes a transactional purge across all systems:

1. **User Profile & Credentials:** Email, full name, phone number, hashed passwords, and authentication record in `auth.users`.
2. **Cloud Storage Attachments:** All uploaded PDFs, scans, image files, backups, and avatars stored in cloud storage buckets.
3. **Database Records:**
   - Document metadata & extracted text (Aadhaar, PAN, Passport, Driving License, etc.)
   - Wallet records (Property, Investments, Cards, Tax, Vehicles, Identity, Health)
   - Password Vault entries
   - Notes, Reminders, and Expenses
   - Shared Document Links & View-Once share tokens
   - Family Vault memberships and invitations
   - Device tokens, push logs, and notification outbox records
4. **Local Device Data:** The app clears all cached preferences, offline documents, and session keys upon sign-out.

---

## Data Retention & Processing Timelines

- **Immediate Purge:** Account deletion requests via the app or web portal take effect immediately.
- **No Orphaned Data:** Deletion is permanent and non-reversible. We do not retain backup copies of deleted user documents or credentials.
- **Support Inquiries:** Verification and support emails sent regarding deletion are retained for 30 days for audit compliance, then deleted.

---

## Questions & Contact

For assistance with account deletion, contact our Data Protection Team:
- **Email:** `privacy@inoapp.in` / `support@inoapp.in`
- **Address:** INO Technologies Private Limited, 101 Innovation Towers, HSR Layout, Bengaluru 560102, India
