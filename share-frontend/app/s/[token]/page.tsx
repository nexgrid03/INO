import Brand from "@/components/Brand";
import StatePage from "@/components/StatePage";
import { fetchShare } from "@/lib/config";
import ShareView from "./ShareView";

export const dynamic = "force-dynamic"; // always fetch fresh share state

export default async function SharePage({ params }: { params: { token: string } }) {
  const data = await fetchShare(params.token);

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
  return <ShareView token={params.token} documents={data.documents} expiresAt={data.expiresAt} />;
}
