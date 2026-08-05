"use client";

import { useEffect, useState } from "react";
import { ClockIcon } from "./icons";

/** Live expiry pill. With [compact], shows only the remaining time (hero row
 *  supplies the "Expires in" label). Reloads when the share lapses. */
export default function ExpiryPill({
  expiresAt,
  compact = false,
}: {
  expiresAt: string | null;
  compact?: boolean;
}) {
  const [label, setLabel] = useState("");

  useEffect(() => {
    if (!expiresAt) return;
    const exp = new Date(expiresAt).getTime();
    const tick = () => {
      const ms = exp - Date.now();
      if (ms <= 0) {
        setLabel("Expired");
        window.location.reload();
        return;
      }
      const s = Math.floor(ms / 1000);
      const d = Math.floor(s / 86400);
      const h = Math.floor((s % 86400) / 3600);
      const m = Math.floor((s % 3600) / 60);
      const ss = s % 60;
      let remaining: string;
      if (d > 0) remaining = `${d} day${d > 1 ? "s" : ""}`;
      else if (h > 0) remaining = `${h}h ${m}m`;
      else if (m > 0) remaining = `${m}m ${ss}s`;
      else remaining = `${ss}s`;
      setLabel(compact ? remaining : `Expires in ${remaining}`);
    };
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, [expiresAt, compact]);

  if (!expiresAt) return null;
  return (
    <span className="pill">
      <ClockIcon /> {label}
    </span>
  );
}
