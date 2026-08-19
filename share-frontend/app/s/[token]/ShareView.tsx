"use client";

import { useMemo, useState } from "react";
import dynamic from "next/dynamic";
import Brand from "@/components/Brand";
import ExpiryPill from "@/components/ExpiryPill";
import {
  DownloadIcon,
  EyeIcon,
  FileTextIcon,
  LockIcon,
  ShieldIcon,
} from "@/components/icons";
import type { SharedDoc } from "@/lib/config";

const DocViewer = dynamic(() => import("./DocViewer"), {
  ssr: false,
  loading: () => (
    <div className="center" style={{ flex: 1 }}>
      <div className="spinner" />
    </div>
  ),
});

function typeBadge(doc: SharedDoc): string {
  const raw = (doc.type || doc.mime || doc.kind || "FILE").toString();
  if (raw.includes("/")) {
    const sub = raw.split("/")[1] ?? raw;
    return sub.replace(/[^a-z0-9]/gi, "").slice(0, 5).toUpperCase() || "FILE";
  }
  return raw.replace(/[^a-z0-9]/gi, "").slice(0, 5).toUpperCase() || "FILE";
}

function formatSharedAt(): string {
  try {
    return new Intl.DateTimeFormat(undefined, {
      day: "numeric",
      month: "short",
      year: "numeric",
      hour: "numeric",
      minute: "2-digit",
    }).format(new Date());
  } catch {
    return "";
  }
}

export default function ShareView({
  token,
  documents,
  expiresAt,
  viewOnly = false,
  pwHash,
}: {
  token: string;
  documents: SharedDoc[];
  expiresAt: string | null;
  viewOnly?: boolean;
  pwHash?: string;
}) {
  const [open, setOpen] = useState<SharedDoc | null>(null);
  const when = useMemo(() => formatSharedAt(), []);
  const countLabel = `${documents.length} document${documents.length === 1 ? "" : "s"}`;
  const pwQ = pwHash ? `&pw=${encodeURIComponent(pwHash)}` : "";

  return (
    <>
      <Brand showSecure />
      <div className="wrap">
        <div className="hero">
          <div className="hero-banner">
            <h1>Documents shared with you</h1>
            <p>
              {viewOnly
                ? "These files are view-only. Download is disabled by the sender."
                : "Review, view and download the files below."}
            </p>
          </div>
          <div className="hero-body">
            <div className="hero-count">
              <FileTextIcon />
              {countLabel}
            </div>
            {expiresAt && (
              <div className="hero-expiry">
                <span className="label">Expires in</span>
                <ExpiryPill expiresAt={expiresAt} compact />
              </div>
            )}
            {when && <div className="hero-meta">{when}</div>}
          </div>
        </div>

        <div className="section-label">Shared documents</div>

        {documents.map((d) => (
          <div className="card" key={d.id}>
            <div className="file">
              <div className="ic" aria-hidden>
                {typeBadge(d)}
              </div>
              <div className="meta">
                <b>{d.name}</b>
                <span>{d.type || typeBadge(d)}</span>
              </div>
              <div className="acts">
                <button
                  type="button"
                  className="icon-act view"
                  aria-label={`View ${d.name}`}
                  onClick={() => setOpen(d)}
                >
                  <EyeIcon />
                </button>
                {!viewOnly && (
                  <a
                    className="icon-act download"
                    aria-label={`Download ${d.name}`}
                    href={`/api/s/${token}/file/${d.id}?mode=download${pwQ}`}
                  >
                    <DownloadIcon />
                  </a>
                )}
              </div>
            </div>
          </div>
        ))}

        <div className="foot">
          <LockIcon />
          These documents were shared securely via INO. Do not forward this link
          — it is private and time-limited.
        </div>
      </div>

      {open && (
        <div className="overlay">
          <div className="topstrip">
            <div className="row">
              <div className="logo-sm">
                <ShieldIcon />
              </div>
              <b>INO</b>
              <div className="spacer" />
              <ExpiryPill expiresAt={expiresAt} />
            </div>
          </div>
          <DocViewer
            token={token}
            doc={open}
            onBack={() => setOpen(null)}
            viewOnly={viewOnly}
            pwHash={pwHash}
          />
        </div>
      )}
    </>
  );
}
