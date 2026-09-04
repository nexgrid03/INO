import Brand from "@/components/Brand";

export const metadata = {
  title: "Privacy Policy - INO Vault",
  description: "Privacy Policy for INO (Intelligent Network Organizer) mobile application and services.",
};

export default function PrivacyPage() {
  return (
    <div className="min-h-screen bg-[#0d1117] text-gray-100 p-6 md:p-12 max-w-4xl mx-auto font-sans">
      <Brand />
      <div className="mt-8 bg-[#161b22] border border-gray-800 rounded-2xl p-6 md:p-10 shadow-xl space-y-6">
        <h1 className="text-3xl font-bold text-emerald-400">Privacy Policy</h1>
        <p className="text-sm text-gray-400">Effective Date: September 4, 2026 | Last Updated: September 4, 2026</p>

        <section className="space-y-3">
          <h2 className="text-xl font-semibold text-white">1. App Owner & Data Fiduciary Details</h2>
          <p className="text-gray-300 leading-relaxed">
            INO (Intelligent Network Organizer) is operated by <strong>INO Technologies Private Limited</strong> ("Company", "we", "us").
            Address: 101 Innovation Towers, HSR Layout, Bengaluru, Karnataka 560102, India.<br />
            Data Protection Officer Contact: <a href="mailto:privacy@inoapp.in" className="text-emerald-400 underline">privacy@inoapp.in</a> | Support: <a href="mailto:support@inoapp.in" className="text-emerald-400 underline">support@inoapp.in</a>
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl font-semibold text-white">2. Age Restriction (18+ Requirement)</h2>
          <p className="text-gray-300 leading-relaxed">
            INO is intended solely for adult users who are <strong>18 years of age or older</strong>. We do not knowingly collect, process, or solicit personal data from anyone under 18.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl font-semibold text-white">3. Information We Collect</h2>
          <ul className="list-disc pl-5 text-gray-300 space-y-2">
            <li><strong>Account & Auth:</strong> Name, Email, Phone, Password hash, Google OAuth profile.</li>
            <li><strong>Document Storage:</strong> Uploaded document images, PDFs, notes, tax records, property & investment details.</li>
            <li><strong>On-Device Extraction (OCR):</strong> Identity numbers (Aadhaar, PAN, Passport, Driving License) extracted locally via Google ML Kit. Raw images are never sent to external OCR servers.</li>
            <li><strong>Password Store:</strong> Passwords and credentials encrypted locally with AES-256-GCM.</li>
            <li><strong>Device & Tokens:</strong> Device Model, OS Version, Firebase FCM push token.</li>
          </ul>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl font-semibold text-white">4. Third-Party Services & Sub-processors</h2>
          <p className="text-gray-300 leading-relaxed">
            We partner with trusted enterprise service providers to operate INO:
          </p>
          <ul className="list-disc pl-5 text-gray-300 space-y-2">
            <li><strong>Supabase:</strong> Cloud database, authentication, row-level security, and encrypted storage buckets.</li>
            <li><strong>Firebase Cloud Messaging (FCM):</strong> Push notification delivery.</li>
            <li><strong>Google Sign-In:</strong> OAuth authentication with nonce replay protection.</li>
            <li><strong>Google ML Kit:</strong> On-device local Optical Character Recognition (OCR). No document images leave your device for OCR.</li>
            <li><strong>OS Speech Recognition:</strong> Built-in platform speech-to-text for search and voice inputs.</li>
            <li><strong>Vercel:</strong> Web hosting for sharing portal and legal compliance pages.</li>
          </ul>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl font-semibold text-white">5. Data Retention & Deletion Policy</h2>
          <p className="text-gray-300 leading-relaxed">
            Personal data, documents, and credentials are retained only as long as your account remains active. Upon initiating an account deletion request (either in-app or via our web portal), all database rows, storage objects, files, and auth records are permanently and irreversibly purged within a single atomic transaction.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl font-semibold text-white">6. Your Rights & Compliance (DPDP Act & GDPR)</h2>
          <p className="text-gray-300 leading-relaxed">
            In compliance with India's <strong>Digital Personal Data Protection Act, 2023 (DPDP Act)</strong> and the <strong>EU General Data Protection Regulation (GDPR)</strong>, you have the right to:
          </p>
          <ul className="list-disc pl-5 text-gray-300 space-y-1">
            <li>Access and review all personal data and document records associated with your account.</li>
            <li>View and download individual document attachments and files at any time.</li>
            <li>Correct inaccurate, incomplete, or outdated document metadata.</li>
            <li>Withdraw consent for optional services (such as push notifications or sharing).</li>
            <li>Permanently delete your account and all associated data.</li>
          </ul>
        </section>

        <section className="space-y-3 border-t border-gray-800 pt-6">
          <p className="text-gray-400 text-sm">
            For account deletion requests, visit our <a href="/account-deletion" className="text-emerald-400 underline font-medium">Account Deletion Page</a> (or <a href="/delete-account" className="text-emerald-400 underline">/delete-account</a>).
          </p>
        </section>
      </div>
    </div>
  );
}
