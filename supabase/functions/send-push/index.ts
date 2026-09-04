// ============================================================================
// INO - Unified push sender (Supabase Edge Function)
// ----------------------------------------------------------------------------
// One sender for everything that is not a reminder. It does two jobs per run:
//
//   1. SCAN for date-based events and enqueue them:
//        • documents whose `expires_at` lands on a lead day (passport, licence,
//          insurance policy, health record — anything with an expiry),
//        • cards whose expiry month is approaching.
//      Both are deduped by `notification_outbox.dedupe_key`, so running twice
//      in a day sends nothing twice.
//
//   2. DRAIN `public.notification_outbox` to FCM. That queue also carries the
//      event-driven notifications nobody can scan for — a sign-in, a password
//      change, a 2FA change, a family-vault invite — which are written by the
//      app and by database triggers (see 20260812000000_notification_outbox.sql).
//
// Why a second function instead of extending send-reminder-push: that one is
// deployed, working, and its whole shape is "scan reminders, stamp
// last_push_sent_on". Documents live in a VIEW over per-wallet tables and can't
// carry a stamp column, cards need month arithmetic, and the event queue is not
// a scan at all. Keeping them apart means a bug here cannot stop reminders.
//
// Secrets: FCM_SERVICE_ACCOUNT (same one send-reminder-push uses).
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are injected by the platform.
//
// SECURITY: same reasoning as send-reminder-push — the anon key is a valid
// project JWT shipped inside the app, so `verify_jwt` alone would leave this
// world-callable. isTrustedCaller() is the real control.
//
// Deploy:  supabase functions deploy send-push
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const FCM_SERVICE_ACCOUNT = Deno.env.get("FCM_SERVICE_ACCOUNT")!;
const CRON_SECRET = Deno.env.get("CRON_SECRET") ?? "";

/// Days before an expiry date to notify. Three touches: a month out (time to
/// act), a week out (time to book an appointment), and the day itself.
const DOC_LEAD_DAYS = [30, 7, 0];

/// Cards get a longer first warning — a replacement card is posted, not issued
/// over the counter, so 30 days is genuinely tight.
const CARD_LEAD_DAYS = [45, 14, 0];

/// How many outbox rows one invocation will attempt. Bounds the run so a
/// backlog cannot time out the function; the next run picks up the rest.
const DRAIN_LIMIT = 500;

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

// ----------------------------------------------------------------------------
// FCM auth (identical to send-reminder-push — the legacy key API was shut down
// in 2024, so v1 needs a real OAuth2 bearer minted from the service account)
// ----------------------------------------------------------------------------
async function mintAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const encode = (o: unknown) =>
    base64Url(new TextEncoder().encode(JSON.stringify(o)));
  const unsigned = `${encode({ alg: "RS256", typ: "JWT" })}.${
    encode({
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    })
  }`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToBinary(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${unsigned}.${base64Url(new Uint8Array(signature))}`,
    }),
  });
  if (!res.ok) {
    throw new Error(`token exchange failed (${res.status}): ${await res.text()}`);
  }
  return (await res.json()).access_token as string;
}

function base64Url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/// The `\n` replace matters: the key arrives from the environment as a JSON
/// string with escaped newlines, and importKey rejects it otherwise.
function pemToBinary(pem: string): ArrayBuffer {
  const body = pem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const raw = atob(body);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out.buffer;
}

// ----------------------------------------------------------------------------
// Date helpers
// ----------------------------------------------------------------------------
/// "Today" in IST. The cron fires before midnight UTC rolls into the Indian
/// day, so computing this in UTC would notify everyone a day early.
function istToday(): string {
  return new Date(Date.now() + 5.5 * 3600_000).toISOString().slice(0, 10);
}

function daysUntil(date: string, today: string): number {
  return Math.round(
    (Date.parse(`${date}T00:00:00Z`) - Date.parse(`${today}T00:00:00Z`)) /
      86_400_000,
  );
}

function plusDays(today: string, days: number): string {
  return new Date(Date.parse(`${today}T00:00:00Z`) + days * 86_400_000)
    .toISOString().slice(0, 10);
}

/// A card is valid through the END of its printed month, so the real expiry is
/// the last day of it. Day 0 of the next month rolls back to that date.
function cardExpiryDate(month: number, year: number): string {
  return new Date(Date.UTC(year, month, 0)).toISOString().slice(0, 10);
}

function expiryLabel(days: number, noun: string): string {
  if (days < 0) return `${noun} expired`;
  if (days === 0) return `${noun} expires today`;
  if (days === 1) return `${noun} expires tomorrow`;
  return `${noun} expires in ${days} days`;
}

// ----------------------------------------------------------------------------
// Scan 1 - documents with an expiry date
// ----------------------------------------------------------------------------
interface DocRow {
  id: string;
  auth_user_id: string;
  name: string;
  wallet: string;
  expires_at: string;
}

async function enqueueDocumentExpiries(today: string): Promise<number> {
  const windows = DOC_LEAD_DAYS.map((d) => plusDays(today, d));

  // `public.documents` is a VIEW unioning the per-wallet tables, so this one
  // query covers identity, insurance, health, property — every wallet at once.
  const { data, error } = await admin
    .from("documents")
    .select("id, auth_user_id, name, wallet, expires_at")
    .in("expires_at", windows);
  if (error) throw error;

  const rows = (data ?? []) as DocRow[];
  if (rows.length === 0) return 0;

  const pending = rows.map((d) => {
    const days = daysUntil(d.expires_at, today);
    return {
      auth_user_id: d.auth_user_id,
      kind: "doc.expiry",
      title: "Document Expiry Notice",
      body: days === 0
        ? "You have an important document expiring today."
        : `You have an important document expiring in ${days} days.`,
      channel: "ino_reminders",
      // One notification per document PER LEAD DAY, ever.
      dedupe_key: `doc:${d.id}:d${days}`,
      data: {
        kind: "doc.expiry",
        document_id: d.id,
        document_name: d.name,
        wallet: d.wallet,
        expires_at: d.expires_at,
      },
    };
  });

  // Duplicates are swallowed by the partial unique index rather than checked
  // for first — one round trip instead of two, and it stays correct under
  // concurrent runs.
  const { error: insErr } = await admin
    .from("notification_outbox")
    .upsert(pending, { onConflict: "dedupe_key", ignoreDuplicates: true });
  if (insErr) throw insErr;
  return pending.length;
}

// ----------------------------------------------------------------------------
// Scan 2 - cards approaching their expiry month
// ----------------------------------------------------------------------------
interface CardRow {
  id: string;
  auth_user_id: string;
  name: string;
  bank: string | null;
  last4: string | null;
  expiry_month: number | null;
  expiry_year: number | null;
}

async function enqueueCardExpiries(today: string): Promise<number> {
  // Month arithmetic can't be expressed as an `in` filter, so pull the small
  // set of cards that still have an expiry recorded and match in memory.
  const { data, error } = await admin
    .from("w_cards_wallet")
    .select("id, auth_user_id, name, bank, last4, expiry_month, expiry_year")
    .not("expiry_month", "is", null)
    .not("expiry_year", "is", null);
  if (error) throw error;

  const pending: Record<string, unknown>[] = [];
  for (const c of (data ?? []) as CardRow[]) {
    if (!c.expiry_month || !c.expiry_year) continue;
    const expiry = cardExpiryDate(c.expiry_month, c.expiry_year);
    const days = daysUntil(expiry, today);
    if (!CARD_LEAD_DAYS.includes(days)) continue;

    pending.push({
      auth_user_id: c.auth_user_id,
      kind: "card.expiry",
      title: "Card Expiry Notice",
      body: days === 0
        ? "You have a payment card expiring today."
        : `You have a payment card expiring in ${days} days.`,
      channel: "ino_reminders",
      dedupe_key: `card:${c.id}:d${days}`,
      data: {
        kind: "card.expiry",
        card_id: c.id,
        bank: c.bank ?? "",
        last4: c.last4 ?? "",
        expires_at: expiry,
      },
    });
  }

  if (pending.length === 0) return 0;
  const { error: insErr } = await admin
    .from("notification_outbox")
    .upsert(pending, { onConflict: "dedupe_key", ignoreDuplicates: true });
  if (insErr) throw insErr;
  return pending.length;
}

// ----------------------------------------------------------------------------
// Drain the queue
// ----------------------------------------------------------------------------
interface OutboxRow {
  id: string;
  auth_user_id: string;
  kind: string;
  title: string;
  body: string;
  data: Record<string, unknown>;
  channel: string;
  exclude_token: string | null;
  attempts: number;
  created_at: string;
}

function buildMessage(row: OutboxRow, token: string) {
  return {
    message: {
      token,
      notification: { title: row.title, body: row.body },
      // Mirrored into `data`: a `notification` payload is not delivered to Dart
      // when the app is backgrounded, so the tap handler would see nothing.
      data: Object.fromEntries(
        Object.entries({ ...row.data, kind: row.kind }).map((
          [k, v],
        ) => [k, String(v)]),
      ),
      android: {
        priority: "HIGH",
        notification: { channel_id: row.channel, sound: "default" },
      },
      apns: { payload: { aps: { sound: "default", badge: 1 } } },
    },
  };
}

async function drain(endpoint: string, accessToken: string) {
  const { data, error } = await admin
    .from("notification_outbox")
    .select(
      "id, auth_user_id, kind, title, body, data, channel, exclude_token, attempts, created_at",
    )
    .is("sent_at", null)
    .order("created_at", { ascending: true })
    .limit(DRAIN_LIMIT);
  if (error) throw error;

  const rows = (data ?? []) as OutboxRow[];
  if (rows.length === 0) return { sent: 0, delivered: 0, pruned: 0 };

  // One token query for every recipient rather than one per row.
  const userIds = [...new Set(rows.map((r) => r.auth_user_id))];
  const { data: tokenRows } = await admin
    .from("device_tokens")
    .select("token, auth_user_id")
    .in("auth_user_id", userIds);

  const byUser = new Map<string, string[]>();
  for (const t of (tokenRows ?? []) as { token: string; auth_user_id: string }[]) {
    const list = byUser.get(t.auth_user_id) ?? [];
    list.push(t.token);
    byUser.set(t.auth_user_id, list);
  }

  let sent = 0;
  const deadTokens: string[] = [];
  const doneIds: string[] = [];
  const failedIds: string[] = [];
  const auditRows: Record<string, unknown>[] = [];

  for (const row of rows) {
    const tokens = (byUser.get(row.auth_user_id) ?? [])
      .filter((t) => t !== row.exclude_token);

    if (tokens.length === 0) {
      // Nowhere to deliver. Retire it rather than retrying forever — a user
      // with no registered device will not acquire one for THIS event.
      doneIds.push(row.id);
      auditRows.push({
        auth_user_id: row.auth_user_id,
        kind: row.kind,
        title: row.title,
        body: row.body,
        devices_targeted: 0,
        devices_delivered: 0,
        queued_at: row.created_at,
        error: "no registered device",
      });
      continue;
    }

    let delivered = false;
    let deliveredCount = 0;
    let lastError: string | null = null;
    for (const token of tokens) {
      const res = await fetch(endpoint, {
        method: "POST",
        headers: {
          authorization: `Bearer ${accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify(buildMessage(row, token)),
      });
      if (res.ok) {
        sent++;
        deliveredCount++;
        delivered = true;
        continue;
      }
      const body = await res.text();
      lastError = `${res.status}: ${body.slice(0, 200)}`;
      // 404 UNREGISTERED / 400 INVALID_ARGUMENT: app uninstalled or token
      // rotated. Left in place they accumulate and every run wastes a call.
      if (res.status === 404 || res.status === 400) deadTokens.push(token);
      console.error(`send failed (${res.status}) for ${row.id}: ${body}`);
    }

    // Audit row. Written whether or not anything landed — "targeted 3,
    // delivered 0" is exactly the case worth being able to look up later.
    auditRows.push({
      auth_user_id: row.auth_user_id,
      kind: row.kind,
      title: row.title,
      body: row.body,
      devices_targeted: tokens.length,
      devices_delivered: deliveredCount,
      queued_at: row.created_at,
      error: lastError,
    });

    // Only a row that reached at least one device is marked done; the rest are
    // retried next run, up to a cap so a permanently broken row cannot loop.
    if (delivered) doneIds.push(row.id);
    else if (row.attempts >= 4) doneIds.push(row.id);
    else failedIds.push(row.id);
  }

  if (doneIds.length > 0) {
    await admin
      .from("notification_outbox")
      .update({ sent_at: new Date().toISOString() })
      .in("id", doneIds);
  }
  for (const id of failedIds) {
    const row = rows.find((r) => r.id === id)!;
    await admin
      .from("notification_outbox")
      .update({ attempts: row.attempts + 1 })
      .eq("id", id);
  }
  if (deadTokens.length > 0) {
    await admin.from("device_tokens").delete().in("token", deadTokens);
  }
  if (auditRows.length > 0) {
    // Best-effort: an audit failure must never turn a delivered notification
    // into a retried one.
    const { error: logErr } = await admin.from("push_log").insert(auditRows);
    if (logErr) console.error("push_log insert failed:", logErr);
  }

  return { sent, delivered: doneIds.length, pruned: deadTokens.length };
}

// ----------------------------------------------------------------------------
// Entry point
// ----------------------------------------------------------------------------
function secretEquals(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/// The anon key is a valid, correctly-signed project JWT that ships inside the
/// mobile app, so `verify_jwt` alone would leave this world-callable. The
/// caller has to prove it is the scheduler, not merely that it is authenticated.
function isTrustedCaller(req: Request): boolean {
  const auth = req.headers.get("authorization") ?? "";
  const bearer = auth.slice(0, 7).toLowerCase() === "bearer "
    ? auth.slice(7).trim()
    : "";
  if (bearer && secretEquals(bearer, SERVICE_ROLE_KEY)) return true;
  const cron = req.headers.get("x-cron-secret") ?? "";
  return !!(CRON_SECRET && cron && secretEquals(cron, CRON_SECRET));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok");
  if (!isTrustedCaller(req)) {
    console.warn("send-push: rejected untrusted caller");
    return json({ ok: false, error: "unauthorized" }, 401);
  }

  try {
    const sa: ServiceAccount = JSON.parse(FCM_SERVICE_ACCOUNT);
    const accessToken = await mintAccessToken(sa);
    const endpoint =
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;
    const today = istToday();

    // `scanOnly=false` lets a trigger call this purely to flush the queue
    // without paying for the daily scans.
    const url = new URL(req.url);
    const drainOnly = url.searchParams.get("drainOnly") === "1";

    // `?diag=1` reports whether each source is actually READABLE, separately
    // from whether it had anything due. Without this a broken scan and a quiet
    // day are indistinguishable from the outside: both scans swallow their own
    // errors so a failure cannot stop the queue draining, which is right for
    // production and useless for diagnosis.
    if (url.searchParams.get("diag") === "1") {
      const diag: Record<string, unknown> = { today };
      try {
        const { count, error } = await admin
          .from("documents")
          .select("id", { count: "exact", head: true })
          .not("expires_at", "is", null);
        diag.documentsReadable = !error;
        diag.documentsWithExpiry = error ? error.message : count;
      } catch (e) {
        diag.documentsReadable = false;
        diag.documentsWithExpiry = String(e);
      }
      try {
        const { count, error } = await admin
          .from("w_cards_wallet")
          .select("id", { count: "exact", head: true })
          .not("expiry_month", "is", null);
        diag.cardsReadable = !error;
        diag.cardsWithExpiry = error ? error.message : count;
      } catch (e) {
        diag.cardsReadable = false;
        diag.cardsWithExpiry = String(e);
      }
      try {
        const { count, error } = await admin
          .from("notification_outbox")
          .select("id", { count: "exact", head: true })
          .is("sent_at", null);
        diag.outboxReadable = !error;
        diag.outboxPending = error ? error.message : count;
      } catch (e) {
        diag.outboxReadable = false;
        diag.outboxPending = String(e);
      }
      try {
        const { count } = await admin
          .from("device_tokens")
          .select("token", { count: "exact", head: true });
        diag.registeredDevices = count;
      } catch (e) {
        diag.registeredDevices = String(e);
      }
      diag.docLeadDays = DOC_LEAD_DAYS;
      diag.cardLeadDays = CARD_LEAD_DAYS;
      return json({ ok: true, diag });
    }

    let docs = 0;
    let cards = 0;
    if (!drainOnly) {
      // A failing scan must not stop the queue from draining — a security
      // alert waiting in the outbox matters more than a card reminder.
      try {
        docs = await enqueueDocumentExpiries(today);
      } catch (e) {
        console.error("document scan failed:", e);
      }
      try {
        cards = await enqueueCardExpiries(today);
      } catch (e) {
        console.error("card scan failed:", e);
      }
    }

    const result = await drain(endpoint, accessToken);
    return json({ ok: true, today, queuedDocs: docs, queuedCards: cards, ...result });
  } catch (e) {
    console.error("send-push failed:", e);
    return json({ ok: false, error: String(e) }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
