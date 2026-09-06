import Brand from "@/components/Brand";
import StatePage from "@/components/StatePage";
import { fetchShare } from "@/lib/config";
import { getVisitorIp } from "@/lib/client-ip";
import { headers } from "next/headers";
import ShareView from "./ShareView";
import ShareUnlock from "./ShareUnlock";

export const dynamic = "force-dynamic"; // always fetch fresh share state

export default async function SharePage({ params }: { params: { token: string } }) {
  const reqHeaders = headers();
  const clientIp = getVisitorIp(reqHeaders);
  const data = await fetchShare(params.token, null, clientIp);

  if (data.status === "password_required") {
    return <ShareUnlock token={params.token} />;
  }

  // Expired / revoked / not-found / error → professional full-page state.
  if (data.status !== "active" || data.documents.length === 0) {
    const kind = data.status === "active" ? "not_found" : data.status;
    return (
      <>
        <Brand />
        <StatePage kind={kind} message={data.message} />
      </>
    );
  }

  // Active → single-document viewer or folder page (decided in ShareView).
  return (
    <ShareView
      token={params.token}
      documents={data.documents}
      expiresAt={data.expiresAt}
      viewOnly={Boolean(data.viewOnly)}
    />
  );
}
