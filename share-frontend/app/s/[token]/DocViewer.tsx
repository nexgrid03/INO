"use client";

import { useEffect, useRef, useState } from "react";
import { Document, Page, pdfjs } from "react-pdf";
// Text/annotation layers are disabled below, so their CSS isn't needed.
import {
  TransformWrapper,
  TransformComponent,
  type ReactZoomPanPinchRef,
} from "react-zoom-pan-pinch";
import type { SharedDoc } from "@/lib/config";

// Load the pdf.js worker from a CDN matching the bundled version.
pdfjs.GlobalWorkerOptions.workerSrc = `https://unpkg.com/pdfjs-dist@${pdfjs.version}/build/pdf.worker.min.mjs`;

const DL_ICON = (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
    <polyline points="7 10 12 15 17 10" />
    <line x1="12" y1="15" x2="12" y2="3" />
  </svg>
);

interface Props {
  token: string;
  doc: SharedDoc;
  onBack?: () => void;
}

export default function DocViewer({ token, doc, onBack }: Props) {
  const view = `/api/s/${token}/file/${doc.id}?mode=view`;
  const download = `/api/s/${token}/file/${doc.id}?mode=download`;
  const inner =
    doc.kind === "image" ? (
      <ImageView src={view} name={doc.name} download={download} onBack={onBack} />
    ) : doc.kind === "pdf" ? (
      <PdfView src={view} name={doc.name} download={download} onBack={onBack} />
    ) : (
      <OtherView name={doc.name} type={doc.type} download={download} onBack={onBack} />
    );
  return inner;
}

/* ---- shared chrome -------------------------------------------------------- */

function Bar(props: {
  name: string;
  download: string;
  onBack?: () => void;
  children?: React.ReactNode; // zoom controls
}) {
  return (
    <div className="viewer-bar">
      {props.onBack && (
        <button className="iconbtn" onClick={props.onBack} aria-label="Back">
          ‹
        </button>
      )}
      <div className="name">{props.name}</div>
      <div className="spacer" />
      {props.children}
      <a className="btn primary" href={props.download} aria-label="Download">
        {DL_ICON}
        <span>Download</span>
      </a>
    </div>
  );
}

/* ---- image (pinch / double-tap zoom) -------------------------------------- */

function ImageView({ src, name, download, onBack }: { src: string; name: string; download: string; onBack?: () => void }) {
  const ref = useRef<ReactZoomPanPinchRef>(null);
  const [loaded, setLoaded] = useState(false);
  const [failed, setFailed] = useState(false);
  return (
    <div className="viewer">
      <Bar name={name} download={download} onBack={onBack}>
        <button className="iconbtn" onClick={() => ref.current?.zoomOut()} aria-label="Zoom out">−</button>
        <button className="iconbtn" onClick={() => ref.current?.zoomIn()} aria-label="Zoom in">+</button>
        <button className="iconbtn" onClick={() => ref.current?.resetTransform()} aria-label="Reset">⤢</button>
      </Bar>
      <div className="stage">
        {failed ? (
          <Fallback download={download} />
        ) : (
          <TransformWrapper ref={ref} doubleClick={{ mode: "toggle", step: 2 }} minScale={1} maxScale={6}>
            <TransformComponent wrapperStyle={{ width: "100%", height: "100%" }}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={src}
                alt={name}
                onLoad={() => setLoaded(true)}
                onError={() => setFailed(true)}
              />
            </TransformComponent>
          </TransformWrapper>
        )}
        {!loaded && !failed && <Loading />}
      </div>
    </div>
  );
}

/* ---- pdf (page render + zoom) --------------------------------------------- */

function PdfView({ src, name, download, onBack }: { src: string; name: string; download: string; onBack?: () => void }) {
  const [numPages, setNumPages] = useState(0);
  const [scale, setScale] = useState(1);
  const [width, setWidth] = useState(800);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    const measure = () => setWidth(Math.min(820, window.innerWidth) - 24);
    measure();
    window.addEventListener("resize", measure);
    return () => window.removeEventListener("resize", measure);
  }, []);

  return (
    <div className="viewer">
      <Bar name={name} download={download} onBack={onBack}>
        <button className="iconbtn" onClick={() => setScale((s) => Math.max(0.5, +(s - 0.25).toFixed(2)))} aria-label="Zoom out">−</button>
        <button className="iconbtn" onClick={() => setScale((s) => Math.min(3, +(s + 0.25).toFixed(2)))} aria-label="Zoom in">+</button>
      </Bar>
      <div className="stage" style={{ display: "block", padding: "0 4px" }}>
        {failed ? (
          <Fallback download={download} />
        ) : (
          <Document
            file={src}
            loading={<Loading />}
            error={<Fallback download={download} />}
            onLoadSuccess={({ numPages }) => setNumPages(numPages)}
            onLoadError={() => setFailed(true)}
          >
            {Array.from({ length: numPages }, (_, i) => (
              <Page
                key={i}
                className="pdf-page"
                pageNumber={i + 1}
                width={Math.round(width * scale)}
                renderAnnotationLayer={false}
                renderTextLayer={false}
              />
            ))}
          </Document>
        )}
      </div>
    </div>
  );
}

/* ---- other (no inline preview) -------------------------------------------- */

function OtherView({ name, type, download, onBack }: { name: string; type: string; download: string; onBack?: () => void }) {
  return (
    <div className="viewer">
      <Bar name={name} download={download} onBack={onBack} />
      <div className="stage">
        <div className="center">
          <div style={{ fontSize: 54 }}>📄</div>
          <div>
            <div style={{ fontWeight: 700, color: "#fff" }}>{name}</div>
            <div style={{ fontSize: 13, marginTop: 4 }}>{type} · preview not available</div>
          </div>
          <a className="btn primary" href={download}>{DL_ICON}<span>Download</span></a>
        </div>
      </div>
    </div>
  );
}

function Loading() {
  return (
    <div className="center">
      <div className="spinner" />
      <div style={{ fontSize: 13 }}>Loading…</div>
    </div>
  );
}

function Fallback({ download }: { download: string }) {
  return (
    <div className="center">
      <div style={{ fontSize: 44 }}>📄</div>
      <div style={{ fontSize: 13 }}>Couldn’t preview this file.</div>
      <a className="btn primary" href={download}>{DL_ICON}<span>Download</span></a>
    </div>
  );
}
