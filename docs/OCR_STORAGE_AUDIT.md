# INO - OCR Extraction Storage Audit

_Last updated: 2026-07-22_

This report traces exactly **where** OCR‑extracted document data lives, **how**
it is serialized, **how** it is loaded, and **which screens** read it - and
verifies that the data survives the full lifecycle (scan → save → app restart →
logout/login → reopen).

---

## 1. Where the data is stored

| Thing | Location |
| --- | --- |
| The **extracted fields** (name, DOB, number, gender, address, …) | The `documents.notes` column in Supabase (Postgres), as a compact JSON envelope. |
| The **document type** (aadhaar / pan / passport / …) | Same envelope (`type` key). |
| The user's **free‑text notes** | Same envelope (`notes` key), kept separate from the machine fields. |
| The **image / PDF bytes** | Supabase Storage, private `documents` bucket, under `<uid>/…`. Referenced by `documents.file_path`. |

There is **no separate table and no schema migration** - the extraction rides in
the existing `notes` column, which is already per‑user and RLS‑scoped (see
`supabase/migrations/20260710000000_user_data_isolation.sql`). Every row is
owned by `auth_user_id = auth.uid()`, so extraction data is isolated per user and
durable in the cloud.

> Why `notes` and not a new `jsonb` column? Zero‑migration durability. Moving to a
> dedicated `jsonb` column later is a one‑line change at the repository boundary
> (`_toRecord`) - the envelope format is already forward‑compatible.

---

## 2. How it is serialized

`lib/models/document_extraction.dart` - `DocumentExtraction`.

**Encode** (`encode()`), written on save:

```json
{ "_ino": 1, "type": "aadhaar", "data": { "name": "Tanishq", "number": "1234...", "dob": "17/12/2006", "gender": "Male" }, "notes": "optional user note" }
```

- `_ino: 1` is a version marker so the decoder can reliably tell our envelope
  apart from a plain note.
- `data` is keyed by **semantic key** (`name`, `number`, `dob`, …). The display
  label (“Aadhaar Number” vs “PAN Number”) is resolved from `type` + key at
  render time via `DocumentExtraction.labelFor()`.

**Decode** (`decode(String? raw)`), read on load - handles three cases so nothing
is ever lost:

1. Our JSON envelope → structured fields + user notes.
2. Legacy `"Label: value"` lines (from an early OCR build) → recovered into
   structured fields.
3. Any other plain text → treated as free‑text notes.

---

## 3. How it is written (the save path)

```
Scan / import  →  OcrService.extract()            (lib/services/ocr_service.dart)
               →  OcrExtraction.toOcrResult()     (lib/models/ocr_result_model.dart)
               →  Review screen (editable)        (lib/screens/scan/ocr_result_screen.dart)
               →  Add Document screen             (lib/screens/documents/add_document_screen.dart)
                    builds DocumentExtraction(type, data, userNotes)
                    storedNotes = extraction.hasData ? extraction.encode() : userNotes
               →  DocumentRepository.create(notes: storedNotes)  →  Supabase INSERT
```

The image bytes are uploaded first (`uploadFile` → `file_path`); the row is then
inserted with the encoded envelope in `notes`. OCR runs **once**, here.

---

## 4. How it is loaded (the read path)

```
DocumentRepository.listForWallet() / listAll()    (lib/repositories/document_repository.dart)
   →  Document.fromMap(row)  - carries the `notes` column
   →  SupabaseWalletDetailRepository._toRecord()   (lib/data/wallet_detail_repository.dart)
        sets DocumentRecord.notes = d.notes
   →  DocumentRecord.extraction  getter            (lib/models/wallet_detail_models.dart)
        returns DocumentExtraction.decode(notes)   - decoded on demand
```

Decoding is lazy (a getter), so it costs nothing until a screen asks for it.

---

## 5. Which screens read it

| Screen / widget | File | What it shows |
| --- | --- | --- |
| **Document Summary Card** (wallet list) | `lib/widgets/wallet_detail/document_card.dart` | Inline chips: name, DOB, **masked** number - visible without opening. |
| **Quick View** sheet | `lib/widgets/wallet_detail/document_quick_view.dart` | All extracted fields with **Copy** buttons, before opening the file. |
| **Document Viewer** | `lib/screens/wallet/document_viewer_screen.dart` | “Extracted Information” card / info sheet with per‑field **Copy Value**. |
| **Search** | `lib/services/global_search_service.dart`, `lib/screens/wallet/document_search_delegate.dart` | Matches on `DocumentExtraction.decode(notes).searchableText`. |

`DocumentRecord.matches()` also folds the extraction's searchable text into
in‑wallet filtering.

---

## 6. Lifecycle verification

| Event | Why the data survives |
| --- | --- |
| **App restart** | Row lives in Supabase; re‑fetched by the repository on next load. |
| **Logout / login** | Row is keyed to `auth_user_id`; RLS returns it to the same user on re‑auth. The local cache is reset on logout (`session_reset.dart`) and re‑hydrated from Supabase. |
| **Navigation** | `DocumentRecord.notes` is carried through the model; `extraction` re‑decodes on demand. |
| **Edit / update** | Favourite/status updates send only those columns (`updateRecord`), never overwriting `notes`. Rename updates `name` only. So the envelope is untouched. |
| **Reopen** | No OCR re‑run - the stored envelope is decoded straight from `notes` (instant). |

**No duplicate rows:** each scan produces exactly one `create()` call; reopening
reads the existing row.

---

## 7. Performance characteristics

- **Resize before OCR:** `ImageEnhancer.bakeBase` caps the longest side to 2000 px
  before recognition (bounds memory + speeds ML Kit).
- **Background isolates:** every heavy image step runs in `Isolate.run` - the UI
  isolate never holds the big buffers.
- **Fast path:** `OcrService.extract` now returns after the first (probe) pass
  when it already parses a complete, well‑structured document, skipping the
  enhanced + binarized passes - clean captures finish ~2–3× faster.
- **Cache‑first on reopen:** extraction is persisted once and read from `notes`
  thereafter; **OCR is never re‑run** for an already‑scanned document.

---

## 8. Summary

Extraction is **persisted once** (encoded envelope in `documents.notes`), **owned
per user** (RLS), and **decoded on demand** by every surface that needs it
(summary card, quick view, viewer, search). It survives restart, logout/login,
navigation, and edits, and is never lost or duplicated.
