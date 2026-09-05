"use client";

import React, { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { Document, Page, pdfjs } from "react-pdf";
import {
  TransformWrapper,
  TransformComponent,
  type ReactZoomPanPinchRef,
} from "react-zoom-pan-pinch";
import { FileTextIcon } from "@/components/icons";
import type { SharedDoc } from "@/lib/config";

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
  viewOnly?: boolean;
  unlockToken?: string;
}

export default function DocViewer({ token, doc, onBack, viewOnly, unlockToken }: Props) {
  const viewUrl = `/api/s/${token}/file/${doc.id}?mode=view`;

  const handleDownload = async () => {
    if (viewOnly) return;
    try {
      const headers: Record<string, string> = {};
      if (unlockToken) headers["x-share-unlock-token"] = unlockToken;

      const res = await fetch(`/api/s/${token}/file/${doc.id}?mode=download`, { headers });
      if (!res.ok) throw new Error("Download failed");
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = doc.name;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    } catch {
      alert("Download failed.");
    }
  };

  const inner =
    doc.kind === "image" ? (
      <ImageView src={viewUrl} name={doc.name} unlockToken={unlockToken} onDownload={viewOnly ? undefined : handleDownload} onBack={onBack} />
    ) : doc.kind === "pdf" ? (
      <PdfView src={viewUrl} name={doc.name} unlockToken={unlockToken} onDownload={viewOnly ? undefined : handleDownload} onBack={onBack} />
    ) : (
      <OtherView name={doc.name} type={doc.type} onDownload={viewOnly ? undefined : handleDownload} onBack={onBack} />
    );
  return inner;
}

function Bar(props: {
  name: string;
  onDownload?: () => void;
  onBack?: () => void;
  children?: ReactNode;
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
      {props.onDownload && (
        <button className="btn primary" onClick={props.onDownload} aria-label="Download">
          {DL_ICON}
          <span>Download</span>
        </button>
      )}
    </div>
  );
}

function ImageView({ src, name, unlockToken, onDownload, onBack }: { src: string; name: string; unlockToken?: string; onDownload?: () => void; onBack?: () => void }) {
  const ref = useRef<ReactZoomPanPinchRef>(null);
  const [blobUrl, setBlobUrl] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let active = true;
    const headers: Record<string, string> = {};
    if (unlockToken) headers["x-share-unlock-token"] = unlockToken;

    fetch(src, { headers })
      .then((r) => {
        if (!r.ok) throw new Error("Image fetch failed");
        return r.blob();
      })
      .then((b) => {
        if (active) setBlobUrl(URL.createObjectURL(b));
      })
      .catch(() => {
        if (active) setFailed(true);
      });

    return () => {
      active = false;
      if (blobUrl) URL.revokeObjectURL(blobUrl);
    };
  }, [src, unlockToken]);

  return (
    <div className="viewer">
      <Bar name={name} onDownload={onDownload} onBack={onBack}>
        <button className="iconbtn" onClick={() => ref.current?.zoomOut()} aria-label="Zoom out">−</button>
        <button className="iconbtn" onClick={() => ref.current?.zoomIn()} aria-label="Zoom in">+</button>
        <button className="iconbtn" onClick={() => ref.current?.resetTransform()} aria-label="Reset">⤢</button>
      </Bar>
      <div className="stage">
        {failed ? (
          <Fallback onDownload={onDownload} />
        ) : blobUrl ? (
          <TransformWrapper ref={ref} doubleClick={{ mode: "toggle", step: 2 }} minScale={1} maxScale={6}>
            <TransformComponent wrapperStyle={{ width: "100%", height: "100%" }}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={blobUrl} alt={name} />
            </TransformComponent>
          </TransformWrapper>
        ) : (
          <Loading />
        )}
      </div>
    </div>
  );
}

function PdfView({ src, name, unlockToken, onDownload, onBack }: { src: string; name: string; unlockToken?: string; onDownload?: () => void; onBack?: () => void }) {
  const [numPages, setNumPages] = useState(0);
  const [scale, setScale] = useState(1);
  const [width, setWidth] = useState(800);
  const [failed, setFailed] = useState(false);

  const fileProp = useMemo(() => {
    const headers: Record<string, string> = {};
    if (unlockToken) headers["x-share-unlock-token"] = unlockToken;
    return { url: src, httpHeaders: headers };
  }, [src, unlockToken]);

  useEffect(() => {
    const measure = () => setWidth(Math.min(820, window.innerWidth) - 24);
    measure();
    window.addEventListener("resize", measure);
    return () => window.removeEventListener("resize", measure);
  }, []);

  return (
    <div className="viewer">
      <Bar name={name} onDownload={onDownload} onBack={onBack}>
        <button className="iconbtn" onClick={() => setScale((s: number) => Math.max(0.5, +(s - 0.25).toFixed(2)))} aria-label="Zoom out">−</button>
        <button className="iconbtn" onClick={() => setScale((s: number) => Math.min(3, +(s + 0.25).toFixed(2)))} aria-label="Zoom in">+</button>
      </Bar>
      <div className="stage" style={{ display: "block", padding: "0 4px" }}>
        {failed ? (
          <Fallback onDownload={onDownload} />
        ) : (
          <Document
            file={fileProp}
            loading={<Loading />}
            error={<Fallback onDownload={onDownload} />}
            onLoadSuccess={({ numPages }: { numPages: number }) => setNumPages(numPages)}
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

function OtherView({ name, type, onDownload, onBack }: { name: string; type: string; onDownload?: () => void; onBack?: () => void }) {
  return (
    <div className="viewer">
      <Bar name={name} onDownload={onDownload} onBack={onBack} />
      <div className="stage">
        <div className="center">
          <div style={{ width: 54, height: 54, color: "#0284c7" }}>
            <FileTextIcon />
          </div>
          <div>
            <div style={{ fontWeight: 700, color: "#0f172a" }}>{name}</div>
            <div style={{ fontSize: 13, marginTop: 4 }}>{type} · preview not available</div>
          </div>
          {onDownload && (
            <button className="btn primary" onClick={onDownload}>{DL_ICON}<span>Download</span></button>
          )}
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

function Fallback({ onDownload }: { onDownload?: () => void }) {
  return (
    <div className="center">
      <div style={{ width: 44, height: 44, color: "#0284c7" }}>
        <FileTextIcon />
      </div>
      <div style={{ fontSize: 13 }}>Couldn’t preview this file.</div>
      {onDownload && (
        <button className="btn primary" onClick={onDownload}>{DL_ICON}<span>Download</span></button>
      )}
    </div>
  );
}
