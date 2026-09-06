"use client";

import { useState } from "react";

export default function DeleteAccountForm() {
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [step, setStep] = useState<"request" | "verify" | "success">("request");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [confirmed, setConfirmed] = useState(false);

  const handleRequestOtp = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setMessage(null);
    setLoading(true);

    try {
      const res = await fetch("/api/account/delete-request", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email }),
      });
      const data = await res.json();
      if (!res.ok) {
        setError(data.error || "Failed to request verification code.");
      } else {
        setMessage(data.message || "A verification code has been sent if an account exists.");
        setStep("verify");
      }
    } catch {
      setError("Network error. Please check your connection and try again.");
    } finally {
      setLoading(false);
    }
  };

  const handleConfirmDelete = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!confirmed) {
      setError("Please check the box confirming you understand this action is permanent.");
      return;
    }
    setError(null);
    setLoading(true);

    try {
      const res = await fetch("/api/account/delete-confirm", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, code }),
      });
      const data = await res.json();
      if (!res.ok) {
        setError(data.error || "Failed to delete account. Please verify your code.");
      } else {
        setStep("success");
      }
    } catch {
      setError("Network error during account deletion. Please try again.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="bg-[#0d1117] border border-rose-900/40 rounded-xl p-6 shadow-inner space-y-4">
      <div className="flex items-center space-x-3">
        <span className="text-rose-400 text-xl font-bold">⚠️</span>
        <h2 className="text-lg font-semibold text-rose-200">
          Web Deletion Request (Immediate Purge)
        </h2>
      </div>
      <p className="text-xs text-gray-400">
        If you have uninstalled the app or lost access to your device, you can delete your account and all associated documents right here.
      </p>

      {error && (
        <div className="p-3 bg-rose-950/60 border border-rose-800/80 rounded-lg text-rose-300 text-sm">
          {error}
        </div>
      )}

      {message && step === "verify" && (
        <div className="p-3 bg-emerald-950/60 border border-emerald-800/80 rounded-lg text-emerald-300 text-sm">
          {message}
        </div>
      )}

      {step === "request" && (
        <form onSubmit={handleRequestOtp} className="space-y-4">
          <div>
            <label className="block text-xs font-semibold text-gray-300 mb-1">
              Registered Account Email Address
            </label>
            <input
              type="email"
              required
              placeholder="you@example.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="w-full bg-[#161b22] border border-gray-700 rounded-lg px-4 py-2 text-sm text-white placeholder-gray-500 focus:outline-none focus:border-rose-500"
            />
          </div>
          <button
            type="submit"
            disabled={loading || !email}
            className="w-full py-2.5 px-4 bg-rose-600 hover:bg-rose-700 disabled:opacity-50 text-white font-semibold text-sm rounded-lg transition"
          >
            {loading ? "Sending verification code..." : "Send Verification Code"}
          </button>
        </form>
      )}

      {step === "verify" && (
        <form onSubmit={handleConfirmDelete} className="space-y-4">
          <div>
            <label className="block text-xs font-semibold text-gray-300 mb-1">
              Verification Code (Sent to {email})
            </label>
            <input
              type="text"
              required
              placeholder="6-digit code"
              value={code}
              onChange={(e) => setCode(e.target.value)}
              className="w-full bg-[#161b22] border border-gray-700 rounded-lg px-4 py-2 text-sm text-white placeholder-gray-500 font-mono tracking-widest text-center focus:outline-none focus:border-rose-500"
            />
          </div>

          <div className="p-3 bg-rose-950/40 border border-rose-800/50 rounded-lg space-y-2">
            <label className="flex items-start space-x-2.5 cursor-pointer">
              <input
                type="checkbox"
                checked={confirmed}
                onChange={(e) => setConfirmed(e.target.checked)}
                className="mt-1 accent-rose-600"
              />
              <span className="text-xs text-gray-300">
                I understand that this action is <strong className="text-rose-400">irreversible</strong>.
                All my vault documents, wallets, credentials, and profile data will be permanently wiped from the servers immediately.
              </span>
            </label>
          </div>

          <div className="flex space-x-3">
            <button
              type="button"
              onClick={() => {
                setStep("request");
                setCode("");
                setError(null);
              }}
              className="w-1/3 py-2 px-3 bg-gray-800 hover:bg-gray-700 text-gray-300 text-xs font-semibold rounded-lg transition"
            >
              Change Email
            </button>
            <button
              type="submit"
              disabled={loading || !code || !confirmed}
              className="w-2/3 py-2.5 px-4 bg-rose-600 hover:bg-rose-700 disabled:opacity-50 text-white font-semibold text-sm rounded-lg transition"
            >
              {loading ? "Purging account..." : "Permanently Delete My Account"}
            </button>
          </div>
        </form>
      )}

      {step === "success" && (
        <div className="p-6 bg-emerald-950/50 border border-emerald-800 rounded-xl text-center space-y-3">
          <div className="w-12 h-12 bg-emerald-900/60 rounded-full flex items-center justify-center mx-auto text-emerald-400 text-2xl">
            ✓
          </div>
          <h3 className="text-lg font-bold text-emerald-300">Account Successfully Purged</h3>
          <p className="text-xs text-gray-300 leading-relaxed max-w-md mx-auto">
            Your INO account, profile records, and all encrypted cloud documents have been completely and permanently deleted from our servers.
          </p>
        </div>
      )}
    </div>
  );
}
