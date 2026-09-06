import Brand from "@/components/Brand";
import DeleteAccountForm from "./DeleteAccountForm";

export const metadata = {
  title: "Delete Account - INO Vault",
  description: "Permanent account deletion page and instructions for INO (Intelligent Network Organizer).",
};

export default function DeleteAccountPage() {
  return (
    <div className="min-h-screen bg-[#0d1117] text-gray-100 p-6 md:p-12 max-w-4xl mx-auto font-sans">
      <Brand />
      <div className="mt-8 bg-[#161b22] border border-gray-800 rounded-2xl p-6 md:p-10 shadow-xl space-y-6">
        <div className="border-b border-gray-800 pb-4">
          <h1 className="text-3xl font-bold text-rose-400">Account & Data Deletion</h1>
          <p className="text-sm text-gray-400 mt-1">
            INO (Intelligent Network Organizer) Official Account Deletion Portal
          </p>
        </div>

        {/* Interactive Deletion Form */}
        <DeleteAccountForm />

        {/* Informational Guidance */}
        <section className="space-y-3">
          <h2 className="text-xl font-semibold text-white">How to Delete Your Account In-App</h2>
          <div className="bg-[#0d1117] border border-gray-800 rounded-xl p-4 space-y-2">
            <h3 className="font-semibold text-emerald-400">In the Mobile App (Instant)</h3>
            <p className="text-gray-300 text-sm">
              1. Open INO ➔ Go to <strong>Profile</strong> ➔ Tap <strong>Delete Account</strong>.<br />
              2. Enter your current password / biometric verification for security.<br />
              3. Confirm deletion. The server instantly purges your profile, documents, and credentials.
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
          <h2 className="text-lg font-semibold text-white">Data Retention Policy & Grievance Contact</h2>
          <p className="text-gray-300 text-sm leading-relaxed">
            Account deletion requests take effect immediately upon verification. Deletion is permanent, non-reversible, and completely purges data from our primary cloud database and object storage buckets.
          </p>
          <p className="text-gray-400 text-xs">
            For statutory compliance inquiries or assistance, email our Grievance Officer at{" "}
            <a href="mailto:privacy@inoapp.in" className="text-emerald-400 underline">
              privacy@inoapp.in
            </a>
            .
          </p>
        </section>
      </div>
    </div>
  );
}
