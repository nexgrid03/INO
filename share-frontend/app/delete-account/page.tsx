import Brand from "@/components/Brand";

export const metadata = {
  title: "Delete Account - INO Vault",
  description: "Permanent account deletion page and instructions for INO (Intelligent Network Organizer).",
};

export default function DeleteAccountPage() {
  return (
    <div className="min-h-screen bg-[#0d1117] text-gray-100 p-6 md:p-12 max-w-4xl mx-auto font-sans">
      <Brand />
      <div className="mt-8 bg-[#161b22] border border-gray-800 rounded-2xl p-6 md:p-10 shadow-xl space-y-6">
        <h1 className="text-3xl font-bold text-rose-400">Account & Data Deletion</h1>
        <p className="text-sm text-gray-400">INO (Intelligent Network Organizer) Account Deletion Request Portal</p>

        <section className="space-y-3">
          <h2 className="text-xl font-semibold text-white">How to Delete Your Account</h2>
          <div className="bg-[#0d1117] border border-gray-800 rounded-xl p-4 space-y-2">
            <h3 className="font-semibold text-emerald-400">Option 1: In the Mobile App (Instant & Automatic)</h3>
            <p className="text-gray-300 text-sm">
              1. Open INO ➔ Go to <strong>Profile</strong> ➔ Tap <strong>Delete Account</strong>.<br />
              2. Enter your current password for security verification.<br />
              3. Confirm deletion. The server instantly purges your profile, documents, and credentials.
            </p>
          </div>

          <div className="bg-[#0d1117] border border-gray-800 rounded-xl p-4 space-y-2 mt-4">
            <h3 className="font-semibold text-emerald-400">Option 2: Web Deletion Request (If App is Uninstalled)</h3>
            <p className="text-gray-300 text-sm">
              Send an email request from your registered INO email address to:
            </p>
            <p className="text-emerald-400 font-mono text-base">delete-account@inoapp.in</p>
            <p className="text-gray-400 text-xs">
              Or email our Data Protection Officer at <a href="mailto:privacy@inoapp.in" className="underline">privacy@inoapp.in</a> with subject "Account Deletion Request".
            </p>
          </div>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl font-semibold text-white">What Data is Permanently Deleted?</h2>
          <ul className="list-disc pl-5 text-gray-300 space-y-1 text-sm">
            <li>User Profile (Full Name, Email, Phone Number, Password hash, Google OAuth ID).</li>
            <li>All Cloud Storage Attachments (PDFs, document images, backups, avatars).</li>
            <li>Document Metadata & Extracted Text (Aadhaar, PAN, Passport, Driving License records).</li>
            <li>Wallet Records, Password Vault entries, Notes, Reminders, Expenses.</li>
            <li>Family Vault memberships, Shared links, View-Once tokens.</li>
            <li>Device Push Tokens, Notification logs, Outbox records.</li>
          </ul>
        </section>

        <section className="space-y-3 border-t border-gray-800 pt-6">
          <h2 className="text-lg font-semibold text-white">Data Retention Policy</h2>
          <p className="text-gray-300 text-sm leading-relaxed">
            Account deletion requests take effect immediately upon execution. Deletion is permanent, non-reversible, and completely purges data from our primary cloud database and object storage buckets.
          </p>
        </section>
      </div>
    </div>
  );
}
