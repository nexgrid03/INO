// A professional full-page terminal state (expired / revoked / not found /
// error). Rendered under <Brand/> by the share page.
const MAP: Record<string, { emoji: string; bg: string; title: string; msg: string }> = {
  expired: {
    emoji: "⏳",
    bg: "rgba(245,165,36,0.15)",
    title: "This link has expired",
    msg: "The documents shared with you are no longer available.",
  },
  revoked: {
    emoji: "🚫",
    bg: "rgba(239,83,80,0.15)",
    title: "This link has been revoked",
    msg: "The owner has turned off access to these documents.",
  },
  not_found: {
    emoji: "🔍",
    bg: "rgba(148,163,184,0.18)",
    title: "Link not found",
    msg: "This shared link doesn’t exist or has been removed.",
  },
  error: {
    emoji: "⚠️",
    bg: "rgba(148,163,184,0.18)",
    title: "Something went wrong",
    msg: "Please try opening the link again in a moment.",
  },
};

export default function StatePage({ kind, message }: { kind: string; message?: string }) {
  const s = MAP[kind] ?? MAP.error;
  return (
    <>
      <div className="state">
        <div className="circle" style={{ background: s.bg }}>
          {s.emoji}
        </div>
        <h2>{s.title}</h2>
        <p>{message ?? s.msg}</p>
      </div>
      <div className="foot">🔒 Shared securely via INO</div>
    </>
  );
}
