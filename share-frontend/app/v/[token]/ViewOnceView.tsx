"use client";

import { useCallback, useEffect, useState } from "react";
import dynamic from "next/dynamic";
import Brand from "@/components/Brand";
import ExpiryPill from "@/components/ExpiryPill";

// pdf.js / zoom libs are heavy - load the renderer client-only, on demand.
const OneTimeDoc = dynamic(() => import("./OneTimeDoc"), {
  ssr: false,
  loading: () => (
    <div className="center" style={{ flex: 1 }}>
      <div className="spinner" />
    </div>
  ),
});

interface Claim {
  accessKey: string;
  name: string;
  type: string;
  kind: "pdf" | "image" | "other";
  mime: string;
}

type Phase = "gate" | "opening" | "open" | "spent";

/**
 * The one-time viewer.
 *
 * Two deliberate phases: a **gate** that warns the recipient and burns nothing,
 * and the **open** document. Only pressing the button claims the token, so the
 * single view is spent by a real human decision rather than by a crawler or a
 * page load.
 *
 * Limitation, stated plainly: a web browser cannot block screenshots. The
 * one-time token is the real guarantee; the INO mobile app additionally sets
 * Android's FLAG_SECURE while the document is on screen.
 */
export default function ViewOnceView({
  token,
  name,
  type,
  expiresAt,
}: {
  token: string;
  name: string;
  type: string;
  expiresAt: string | null;
}) {
  const [phase, setPhase] = useState<Phase>("gate");
  const [claim, setClaim] = useState<Claim | null>(null);
  const [error, setError] = useState<string | null>(null);

  // Deterrents only - honest about what they are. Right-click/save is blocked;
  // a screenshot is not blockable from a web page.
  useEffect(() => {
    const block = (e: Event) => e.preventDefault();
    document.addEventListener("contextmenu", block);
    return () => document.removeEventListener("contextmenu", block);
  }, []);

  // Warn on refresh/close while the document is open: the link is already gone.
  useEffect(() => {
    if (phase !== "open") return;
    const warn = (e: BeforeUnloadEvent) => {
      e.preventDefault();
      e.returnValue = "";
    };
    window.addEventListener("beforeunload", warn);
    return () => window.removeEventListener("beforeunload", warn);
  }, [phase]);

  const open = useCallback(async () => {
    setPhase("opening");
    setError(null);
    try {
      const res = await fetch(`/api/v/${encodeURIComponent(token)}/claim`, {
        method: "POST",
        cache: "no-store",
      });
      const json = await res.json();
      if (!res.ok || json.status !== "claimed") {
        setPhase("spent");
        setError(json.message ?? "This document has already been viewed or has expired.");
        return;
      }
      setClaim({
        accessKey: json.accessKey,
        name: json.name ?? name,
        type: json.type ?? type,
        kind: json.kind ?? "other",
        mime: json.mime ?? "application/octet-stream",
      });
      setPhase("open");
    } catch {
      setPhase("gate");
      setError("Couldn’t open the document. Check your connection and try again.");
    }
  }, [token, name, type]);

  // ── Spent: the claim failed because someone already opened it. ──
  if (phase === "spent") {
    return (
      <>
        <Brand />
        <div className="state">
          <div className="circle" style={{ background: "rgba(239,83,80,0.15)" }}>
            👁️
          </div>
          <h2>This document has already been viewed</h2>
          <p>{error}</p>
        </div>
        <div className="foot">🔒 One-time secure view via INO</div>
      </>
    );
  }

  // ── Open: the token is burned; show the document. ──
  if (phase === "open" && claim) {
    return (
      <div className="single vo-noselect">
        <div className="topstrip">
          <div className="row">
            <div className="logo-sm">I</div>
            <b>INO</b>
            <div className="spacer" />
            <span className="pill">👁️ Viewed once</span>
          </div>
        </div>
        <OneTimeDoc
          src={`/api/v/${encodeURIComponent(token)}/file?k=${encodeURIComponent(claim.accessKey)}`}
          name={claim.name}
          type={claim.type}
          kind={claim.kind}
        />
      </div>
    );
  }

  // ── Gate: warn first, burn nothing until the button is pressed. ──
  return (
    <>
      <Brand />
      <div className="wrap">
        <div className="row">
          <div>
            <div className="title">Someone shared a document with you</div>
            <div className="subtitle">You can open it one time only</div>
          </div>
          <div className="spacer" />
          <ExpiryPill expiresAt={expiresAt} />
        </div>

        <div style={{ height: 16 }} />

        <div className="card">
          <div className="file">
            <div className="ic">👁️</div>
            <div className="meta">
              <b>{name}</b>
              <span>{type} · view once</span>
            </div>
          </div>

          <div className="vo-warn">
            ⚠️ This document can be opened <b>only once</b>. The moment you open it, the link
            expires permanently — make sure you are ready to read it now.
          </div>

          {error && <div className="vo-error">{error}</div>}

          <div className="acts">
            <button
              className="btn primary"
              type="button"
              onClick={open}
              disabled={phase === "opening"}
            >
              {phase === "opening" ? "Opening…" : "Open once"}
            </button>
          </div>
        </div>

        <div className="foot">🔒 One-time secure view via INO · nothing is stored on this device</div>
      </div>
    </>
  );
}
