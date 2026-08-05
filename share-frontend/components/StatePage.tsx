import { AlertIcon, BanIcon, ClockIcon, LockIcon, SearchIcon } from "./icons";

const DASHBOARD_URL = "https://inoapp.in";
const REQUEST_MAIL = "mailto:support@ino.app?subject=Request%20new%20INO%20share%20link";

// Full-page terminal state (expired / revoked / not found / error).
const MAP: Record<
  string,
  {
    icon: React.ReactNode;
    bg: string;
    color: string;
    title: string;
    msg: string;
    struck?: boolean;
  }
> = {
  expired: {
    icon: <ClockIcon />,
    bg: "rgba(220, 38, 38, 0.1)",
    color: "#dc2626",
    title: "Link Expired",
    msg:
      "This secure share link is no longer valid. For your protection, access has been permanently closed.",
    struck: true,
  },
  revoked: {
    icon: <BanIcon />,
    bg: "rgba(220, 38, 38, 0.1)",
    color: "#dc2626",
    title: "Link Revoked",
    msg: "The owner has turned off access to these documents.",
  },
  not_found: {
    icon: <SearchIcon />,
    bg: "rgba(9, 143, 144, 0.12)",
    color: "#098F90",
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
        <div
          className={`circle${s.struck ? " struck" : ""}`}
          style={{ background: s.bg, color: s.color }}
        >
          {s.icon}
        </div>
        <h2>{s.title}</h2>
        <p>{message ?? s.msg}</p>
        <div className="state-actions">
          <a className="btn primary" href={REQUEST_MAIL}>
            Request New Link
          </a>
          <a className="btn ghost" href={DASHBOARD_URL}>
            Return to Dashboard
          </a>
        </div>
      </div>
      <div className="foot">
        <LockIcon /> Shared securely via INO
      </div>
    </>
  );
}
