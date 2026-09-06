import Brand from "@/components/Brand";
import StatePage from "@/components/StatePage";
import { peekViewOnce } from "@/lib/config";
import { getVisitorIp } from "@/lib/client-ip";
import { headers } from "next/headers";
import ViewOnceView from "./ViewOnceView";

export const dynamic = "force-dynamic"; // always read fresh one-time state

const TERMINAL: Record<string, { kind: string; message: string }> = {
  viewed: {
    kind: "expired",
    message: "This document has already been viewed or has expired.",
  },
  expired: {
    kind: "expired",
    message: "This document has already been viewed or has expired.",
  },
  revoked: {
    kind: "revoked",
    message: "The sender has turned off access to this document.",
  },
  not_found: {
    kind: "not_found",
    message: "This document has already been viewed or has expired.",
  },
};

/**
 * The recipient page for a view-once link.
 *
 * Rendering this page only PEEKS - it never burns the share. The recipient has
 * to press "Open once" (which POSTs `/api/v/<token>/claim`) before the document
 * is revealed and the link dies. Anything else - a WhatsApp/Slack link-preview
 * crawler, a refresh, a mis-tap on the notification - leaves the share intact.
 */
export default async function ViewOncePage({ params }: { params: { token: string } }) {
  const reqHeaders = headers();
  const clientIp = getVisitorIp(reqHeaders);
  const peek = await peekViewOnce(params.token, clientIp);

  if (peek.status !== "ready") {
    const t = TERMINAL[peek.status];
    return (
      <>
        <Brand />
        <StatePage kind={t?.kind ?? "error"} message={peek.message ?? t?.message} />
      </>
    );
  }

  return (
    <ViewOnceView
      token={params.token}
      name={peek.name}
      type={peek.type}
      expiresAt={peek.expiresAt}
    />
  );
}
