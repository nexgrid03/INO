import Brand from "@/components/Brand";
import { LinkIcon } from "@/components/icons";

// Root landing. Real shares live at /s/<token>; this is just a friendly page
// for anyone who lands on the bare domain.
export default function Home() {
  return (
    <>
      <Brand />
      <div className="state">
        <div className="circle" style={{ background: "rgba(14, 165, 233, 0.12)", color: "#0284c7" }}>
          <LinkIcon />
        </div>
        <h2>Nothing to see here</h2>
        <p>Open a share link (they look like <code>/s/&lt;code&gt;</code>) to view the documents shared with you.</p>
      </div>
    </>
  );
}
