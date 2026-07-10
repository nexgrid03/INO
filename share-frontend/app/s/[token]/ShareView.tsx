"use client";

import { useState } from "react";
import dynamic from "next/dynamic";
import Brand from "@/components/Brand";
import ExpiryPill from "@/components/ExpiryPill";
import type { SharedDoc } from "@/lib/config";

// The viewer pulls in pdf.js / zoom libs — load it client-only, on demand.
const DocViewer = dynamic(() => import("./DocViewer"), {
  ssr: false,
  loading: () => (
    <div className="center" style={{ flex: 1 }}>
      <div className="spinner" />
    </div>
  ),
});

const ICON: Record<string, string> = { pdf: "📕", image: "🖼️", other: "📄" };

export default function ShareView({
  token,
  documents,
  expiresAt,
}: {
  token: string;
  documents: SharedDoc[];
  expiresAt: string | null;
}) {
  const [open, setOpen] = useState<SharedDoc | null>(null);

  // ── Single document → open it directly (Google-Drive style, no list). ──
  if (documents.length === 1) {
    return (
      <div className="single">
        <div className="topstrip">
          <div className="row">
            <div className="logo-sm">I</div>
            <b>INO</b>
            <div className="spacer" />
            <ExpiryPill expiresAt={expiresAt} />
          </div>
        </div>
        <DocViewer token={token} doc={documents[0]} />
      </div>
    );
  }

  // ── Multiple documents → a shared-folder page. ──
  return (
    <>
      <Brand />
      <div className="wrap">
        <div className="row">
          <div>
            <div className="title">Shared documents</div>
            <div className="subtitle">
              {documents.length} file{documents.length === 1 ? "" : "s"}
            </div>
          </div>
          <div className="spacer" />
          <ExpiryPill expiresAt={expiresAt} />
        </div>

        <div style={{ height: 16 }} />

        {documents.map((d) => (
          <div className="card" key={d.id}>
            <div className="file">
              <div className="ic">{ICON[d.kind] ?? "📄"}</div>
              <div className="meta">
                <b>{d.name}</b>
                <span>{d.type}</span>
              </div>
            </div>
            <div className="acts">
              <button className="btn primary" onClick={() => setOpen(d)}>
                Preview
              </button>
              <a className="btn ghost" href={`/api/s/${token}/file/${d.id}?mode=download`}>
                Download
              </a>
            </div>
          </div>
        ))}

        <div className="foot">🔒 Shared securely via INO · you can only view these documents</div>
      </div>

      {open && (
        <div className="overlay">
          <DocViewer token={token} doc={open} onBack={() => setOpen(null)} />
        </div>
      )}
    </>
  );
}
