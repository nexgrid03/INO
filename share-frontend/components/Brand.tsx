import { ShieldIcon } from "./icons";

/** INO glass header — optional Secure share badge (Aqua share landing). */
export default function Brand({ showSecure = false }: { showSecure?: boolean }) {
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
        {showSecure && (
          <div className="secure">
            <ShieldIcon />
            Secure share
          </div>
        )}
      </div>
    </header>
  );
}
