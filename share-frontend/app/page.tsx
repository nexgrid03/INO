// Root landing. Real shares live at /s/<token>; this is just a friendly page
// for anyone who lands on the bare domain.
export default function Home() {
  return (
    <>
      <header className="brand">
        <div className="brand-in">
          <div className="logo">I</div>
          <div>
            <b>INO</b>
            <span>Secure document share</span>
          </div>
        </div>
      </header>
      <div className="state">
        <div className="circle" style={{ background: "rgba(0,230,118,0.12)" }}>🔗</div>
        <h2>Nothing to see here</h2>
        <p>Open a share link (they look like <code>/s/&lt;code&gt;</code>) to view the documents shared with you.</p>
      </div>
    </>
  );
}
