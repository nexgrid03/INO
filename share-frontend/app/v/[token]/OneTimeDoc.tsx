"use client";

import { useEffect, useRef, useState } from "react";
import { Document, Page, pdfjs } from "react-pdf";
import {
  TransformWrapper,
  TransformComponent,
  type ReactZoomPanPinchRef,
} from "react-zoom-pan-pinch";

// Same pdf.js worker pin as the regular share viewer.
pdfjs.GlobalWorkerOptions.workerSrc = `https://unpkg.com/pdfjs-dist@${pdfjs.version}/build/pdf.worker.min.mjs`;

interface Props {
  src: string;
  name: string;
  type: string;
  kind: "pdf" | "image" | "other";
}

/**
 * Renders a claimed one-time document inline.
 *
 * Deliberately has **no Download button** - a view-once document is viewed, not
 * kept, and the Edge Function only ever serves it with an `inline` disposition.
 */
export default function OneTimeDoc({ src, name, type, kind }: Props) {
  if (kind === "image") return <ImageView src={src} name={name} />;
  if (kind === "pdf") return <PdfView src={src} name={name} />;
  return <OtherView name={name} type={type} />;
}

function Bar({ name, children }: { name: string; children?: React.ReactNode }) {
  return (
    <div className="viewer-bar">
      <div className="name">{name}</div>
      <div className="spacer" />
      {children}
    </div>
  );
}

function ImageView({ src, name }: { src: string; name: string }) {
  const ref = useRef<ReactZoomPanPinchRef>(null);
  const [loaded, setLoaded] = useState(false);
  const [failed, setFailed] = useState(false);
  return (
    <div className="viewer">
      <Bar name={name}>
        <button className="iconbtn" onClick={() => ref.current?.zoomOut()} aria-label="Zoom out">−</button>
        <button className="iconbtn" onClick={() => ref.current?.zoomIn()} aria-label="Zoom in">+</button>
        <button className="iconbtn" onClick={() => ref.current?.resetTransform()} aria-label="Reset">⤢</button>
      </Bar>
      <div className="stage">
        {failed ? (
          <Expired />
        ) : (
          <TransformWrapper ref={ref} doubleClick={{ mode: "toggle", step: 2 }} minScale={1} maxScale={6}>
            <TransformComponent wrapperStyle={{ width: "100%", height: "100%" }}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={src}
                alt={name}
                draggable={false}
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

function PdfView({ src, name }: { src: string; name: string }) {
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
      <Bar name={name}>
        <button className="iconbtn" onClick={() => setScale((s) => Math.max(0.5, +(s - 0.25).toFixed(2)))} aria-label="Zoom out">−</button>
        <button className="iconbtn" onClick={() => setScale((s) => Math.min(3, +(s + 0.25).toFixed(2)))} aria-label="Zoom in">+</button>
      </Bar>
      <div className="stage" style={{ display: "block", padding: "0 4px" }}>
        {failed ? (
          <Expired />
        ) : (
          <Document
            file={src}
            loading={<Loading />}
            error={<Expired />}
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

/** A file type no browser can preview. There is no download fallback here - the
 *  view-once contract is "view", so we say so rather than handing over bytes. */
function OtherView({ name, type }: { name: string; type: string }) {
  return (
    <div className="viewer">
      <Bar name={name} />
      <div className="stage">
        <div className="center">
          <div style={{ fontSize: 54 }}>📄</div>
          <div>
            <div style={{ fontWeight: 700, color: "#fff" }}>{name}</div>
            <div style={{ fontSize: 13, marginTop: 4 }}>
              {type} · this file type can’t be previewed in a browser
            </div>
          </div>
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

/** The access key lasts minutes, not hours. If it lapses mid-view, say so. */
function Expired() {
  return (
    <div className="center">
      <div style={{ fontSize: 44 }}>👁️</div>
      <div style={{ fontSize: 13 }}>
        This one-time view has ended. Ask the sender for a new link.
      </div>
    </div>
  );
}
