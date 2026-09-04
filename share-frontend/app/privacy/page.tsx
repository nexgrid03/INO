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
          <h2 className="text-xl font-semibold text-white">4. Third-Party Services</h2>
          <p className="text-gray-300 leading-relaxed">
            We partner with trusted service providers: Supabase (Auth, DB, Storage), Firebase FCM (Notifications), Google Sign-In & ML Kit (Auth & local OCR), Google Fonts, Vercel (Web hosting), Swissquote & Frankfurter API (Forex rates), OS Speech Recognition.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl font-semibold text-white">5. Your Rights & Compliance</h2>
          <p className="text-gray-300 leading-relaxed">
            We comply with India's <strong>DPDP Act 2023</strong> and the <strong>EU GDPR</strong>. You have rights to access, correct, export your data, withdraw consent, and permanently delete your account at any time.
          </p>
        </section>

        <section className="space-y-3 border-t border-gray-800 pt-6">
          <p className="text-gray-400 text-sm">
            For account deletion requests, visit our <a href="/delete-account" className="text-emerald-400 underline font-medium">Account Deletion Page</a>.
          </p>
        </section>
      </div>
    </div>
  );
}
