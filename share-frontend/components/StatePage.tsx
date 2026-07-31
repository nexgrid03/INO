import { AlertIcon, BanIcon, ClockIcon, LockIcon, SearchIcon } from "./icons";

// A professional full-page terminal state (expired / revoked / not found /
// error). Rendered under <Brand/> by the share page.
const MAP: Record<
  string,
  { icon: React.ReactNode; bg: string; color: string; title: string; msg: string }
> = {
  expired: {
    icon: <ClockIcon />,
    bg: "rgba(220, 38, 38, 0.1)",
    color: "#dc2626",
    title: "This link has expired",
    msg: "The documents shared with you are no longer available.",
  },
  revoked: {
    icon: <BanIcon />,
    bg: "rgba(220, 38, 38, 0.1)",
    color: "#dc2626",
    title: "This link has been revoked",
    msg: "The owner has turned off access to these documents.",
  },
  not_found: {
    icon: <SearchIcon />,
    bg: "rgba(100, 116, 139, 0.12)",
    color: "#64748b",
    title: "Link not found",
    msg: "This shared link doesn’t exist or has been removed.",
  },
  error: {
    icon: <AlertIcon />,
    bg: "rgba(217, 119, 6, 0.12)",
    color: "#d97706",
    title: "Something went wrong",
    msg: "Please try opening the link again in a moment.",
  },
};

export default function StatePage({ kind, message }: { kind: string; message?: string }) {
  const s = MAP[kind] ?? MAP.error;
  return (
    <>
      <div className="state">
        <div className="circle" style={{ background: s.bg, color: s.color }}>
          {s.icon}
        </div>
        <h2>{s.title}</h2>
        <p>{message ?? s.msg}</p>
      </div>
      <div className="foot">
        <LockIcon /> Shared securely via INO
      </div>
    </>
  );
}
