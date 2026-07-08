"use client";

import { useEffect, useState } from "react";

/** Live "Expires in …" pill; reloads the page when the share lapses so the
 *  server re-renders the expired state. */
export default function ExpiryPill({ expiresAt }: { expiresAt: string | null }) {
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
      if (d > 0) setLabel(`Expires in ${d} day${d > 1 ? "s" : ""}`);
      else if (h > 0) setLabel(`Expires in ${h}h ${m}m`);
      else if (m > 0) setLabel(`Expires in ${m}m ${ss}s`);
      else setLabel(`Expires in ${ss}s`);
    };
    tick();
    const id = setInterval(tick, 1000);
    return () => clearInterval(id);
  }, [expiresAt]);

  if (!expiresAt) return null;
  return <span className="pill">⏳ {label}</span>;
}
