"use client";

import { useState } from "react";
import Brand from "@/components/Brand";
import type { SharedDoc } from "@/lib/config";
import ShareView from "./ShareView";

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export default function ShareUnlock({ token }: { token: string }) {
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [unlocked, setUnlocked] = useState<{
    documents: SharedDoc[];
    expiresAt: string | null;
    viewOnly: boolean;
    pwHash: string;
  } | null>(null);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!password.trim() || busy) return;
    setBusy(true);
    setError(null);
    try {
      const pwHash = await sha256Hex(password.trim());
      const res = await fetch(
        `/api/s/${encodeURIComponent(token)}?pw=${encodeURIComponent(pwHash)}`,
        { cache: "no-store" },
      );
      const json = await res.json();
      if (json.status === "active" && Array.isArray(json.documents)) {
        setUnlocked({
          documents: json.documents,
          expiresAt: json.expiresAt ?? null,
          viewOnly: Boolean(json.viewOnly),
          pwHash,
        });
        return;
      }
      setError(json.message || "Incorrect password.");
    } catch {
      setError("Could not unlock this share. Try again.");
    } finally {
      setBusy(false);
    }
  }

  if (unlocked) {
    return (
      <ShareView
        token={token}
        documents={unlocked.documents}
        expiresAt={unlocked.expiresAt}
        viewOnly={unlocked.viewOnly}
        pwHash={unlocked.pwHash}
      />
    );
  }

  return (
    <>
      <Brand showSecure />
      <div className="wrap">
        <div className="hero">
          <div className="hero-banner">
            <h1>Password required</h1>
            <p>Enter the password the sender shared with you to open these files.</p>
          </div>
        </div>
        <form className="card" onSubmit={onSubmit} style={{ padding: 20 }}>
          {error && (
            <p style={{ color: "#b91c1c", margin: "0 0 12px", fontSize: 14 }}>
              {error}
            </p>
          )}
          <input
            type="password"
            autoComplete="current-password"
            placeholder="Share password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            style={{
              width: "100%",
              padding: "12px 14px",
              borderRadius: 12,
              border: "1px solid #d1d5db",
              fontSize: 16,
              marginBottom: 12,
            }}
          />
          <button
            type="submit"
            className="icon-act view"
            disabled={busy}
            style={{ width: "100%", justifyContent: "center", height: 44 }}
          >
            {busy ? "Unlocking…" : "Unlock"}
          </button>
        </form>
      </div>
    </>
  );
}
