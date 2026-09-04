import Brand from "@/components/Brand";

export const metadata = {
  title: "Terms of Service - INO Vault",
  description: "Terms of Service for INO (Intelligent Network Organizer).",
};

export default function TermsPage() {
  return (
    <div className="min-h-screen bg-[#0d1117] text-gray-100 p-6 md:p-12 max-w-4xl mx-auto font-sans">
      <Brand />
      <div className="mt-8 bg-[#161b22] border border-gray-800 rounded-2xl p-6 md:p-10 shadow-xl space-y-6">
        <h1 className="text-3xl font-bold text-sky-400">Terms of Service</h1>
        <p className="text-sm text-gray-400">Effective Date: September 4, 2026 | Last Updated: September 4, 2026</p>

        <section className="space-y-3">
          <h2 className="text-xl font-semibold text-white">1. Eligibility (18+ Age Requirement)</h2>
          <p className="text-gray-300 leading-relaxed">
            <strong>This service is intended only for users aged 18 years and above.</strong> By creating an account or using INO, you represent and warrant that you are at least 18 years old and possess legal capacity to enter into a binding contract.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl font-semibold text-white">2. Acceptable Use & Account Responsibilities</h2>
          <p className="text-gray-300 leading-relaxed">
            You are responsible for maintaining the security of your account and credentials. You agree not to use INO for illegal, fraudulent, or unauthorized purposes, nor upload malicious content.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-xl font-semibold text-white">3. Ownership & Account Deletion</h2>
          <p className="text-gray-300 leading-relaxed">
            You retain full ownership of all documents and files uploaded to INO. You may delete your account and all data at any time via the in-app Profile screen or at <a href="/delete-account" className="text-sky-400 underline">/delete-account</a>.
          </p>
        </section>

        <section className="space-y-3 border-t border-gray-800 pt-6">
          <p className="text-gray-400 text-sm">
            For questions, contact <a href="mailto:support@inoapp.in" className="text-sky-400 underline">support@inoapp.in</a>.
          </p>
        </section>
      </div>
    </div>
  );
}
