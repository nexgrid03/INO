import { ShieldIcon } from "./icons";

// Presentational, dual-use (server or client). The INO glass header.
export default function Brand() {
  return (
    <header className="brand">
      <div className="brand-in">
        <div className="logo">
          <ShieldIcon />
        </div>
        <div>
          <b>INO</b>
          <span>Secure document share</span>
        </div>
      </div>
    </header>
  );
}
