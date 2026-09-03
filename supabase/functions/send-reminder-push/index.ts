// ============================================================================
// INO - Reminder push notifications (Supabase Edge Function)
// ----------------------------------------------------------------------------
// Runs on a PER-MINUTE cron and pushes every reminder whose exact due moment
// (`reminders.due_at`) has arrived and that has not been pushed yet. Firebase
// is ONLY the transport - the data never leaves Supabase.
//
//   1. Scan `public.reminders` for active rows with due_at <= now() and
//      notified_at IS NULL (bounded to the last 24h so a backlog never
//      floods anyone).
//   2. Join `public.device_tokens` to resolve each owner's devices.
//   3. Send a DATA-ONLY message via the FCM HTTP **v1** API. The device shows
//      it itself (PushService / the background handler) under the same
//      notification id its local exact-time schedule used, so a phone that
//      already rang at the due moment gets the banner refreshed, never a
//      duplicate. A `notification` payload would be drawn by the OS with its
//      own id and stack a second copy.
//   4. Prune tokens FCM reports as dead, and stamp `notified_at` so the next
//      minute's run is a no-op for these rows.
//
// The device's local schedule is the primary alarm (works offline, to the
// second); this is the backup for reinstalls, phones that lost the schedule,
// and reminders created on another device.
//
// Secrets (supabase secrets set …):
//   FCM_SERVICE_ACCOUNT  - the full service-account JSON, one line.
//   CRON_SECRET          - optional; lets the scheduler call without carrying
//                          the service-role key (x-cron-secret header).
//
// SECURITY: do NOT rely on the platform's `verify_jwt` alone. The publishable
// anon key is a valid signed project JWT that ships inside the mobile app, so
// "verify_jwt = true" still lets anybody run this job. isTrustedCaller() is
// the control.
//
// Deploy:  supabase functions deploy send-reminder-push
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const FCM_SERVICE_ACCOUNT = Deno.env.get("FCM_SERVICE_ACCOUNT")!;
const CRON_SECRET = Deno.env.get("CRON_SECRET") ?? "";

/// Must match PushService.channelId in lib/services/push_service.dart and
/// `default_notification_channel_id` in AndroidManifest.xml.
const ANDROID_CHANNEL = "ino_reminders";

/// A reminder older than this that was somehow never pushed is stamped as
/// notified WITHOUT sending: ringing someone for yesterday's 3 PM at 9 AM
/// today is noise, and the app shows it as overdue anyway.
const MAX_AGE_MS = 24 * 3600_000;

/// Upper bound per run; the next minute picks up any remainder.
const BATCH = 500;

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

interface ReminderRow {
  id: string;
  auth_user_id: string;
  title: string;
  subtitle: string | null;
  category: string;
  priority: string;
  due_date: string | null;
  due_at: string; // ISO timestamptz
}

interface TokenRow {
  token: string;
  auth_user_id: string;
}

// ----------------------------------------------------------------------------
// Google OAuth2: service account → access token
// ----------------------------------------------------------------------------

async function mintAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const encode = (o: unknown) => base64Url(new TextEncoder().encode(JSON.stringify(o)));
  const unsigned = `${encode(header)}.${encode(claims)}`;

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
  const jwt = `${unsigned}.${base64Url(new Uint8Array(signature))}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) {
    throw new Error(`token exchange failed (${res.status}): ${await res.text()}`);
  }
  return (await res.json()).access_token as string;
}

function base64Url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

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
// Message shaping
// ----------------------------------------------------------------------------

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/// "12 Jul · 5:30 PM" in IST - mirrors reminderDateTimeLabel() in
/// lib/models/reminder_models.dart so the push and the in-app card agree.
function whenLabel(dueAtIso: string): string {
  const d = new Date(Date.parse(dueAtIso) + 5.5 * 3600_000); // shift to IST
  const h24 = d.getUTCHours();
  const h12 = h24 % 12 === 0 ? 12 : h24 % 12;
  const mm = String(d.getUTCMinutes()).padStart(2, "0");
  return `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} · ${h12}:${mm} ${h24 < 12 ? "AM" : "PM"}`;
}

function bodyFor(r: ReminderRow): string {
  const when = whenLabel(r.due_at);
  return r.subtitle ? `${when} · ${r.subtitle}` : when;
}

/// DATA-ONLY on purpose (no `notification` block) - see the header.
function buildMessage(r: ReminderRow, token: string) {
  return {
    message: {
      token,
      data: {
        kind: "reminder.due",
        reminder_id: r.id,
        title: r.title,
        body: bodyFor(r),
        category: r.category,
        priority: r.priority,
        due_at: r.due_at,
        due_date: r.due_date ?? "",
      },
      android: {
        priority: "HIGH",
        // Delivered to the background handler even in Doze; the app renders
        // it on the reminders channel.
        ttl: "3600s",
      },
      apns: {
        headers: { "apns-priority": "10", "apns-push-type": "background" },
        payload: { aps: { "content-available": 1 } },
      },
    },
  };
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

function isTrustedCaller(req: Request): boolean {
  const auth = req.headers.get("authorization") ?? "";
  const bearer = auth.slice(0, 7).toLowerCase() === "bearer "
    ? auth.slice(7).trim()
    : "";
  if (bearer && secretEquals(bearer, SERVICE_ROLE_KEY)) return true;

  const cronHeader = req.headers.get("x-cron-secret") ?? "";
  if (CRON_SECRET && cronHeader && secretEquals(cronHeader, CRON_SECRET)) {
    return true;
  }
  return false;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok");

  if (!isTrustedCaller(req)) {
    console.warn("send-reminder-push: rejected untrusted caller");
    return json({ ok: false, error: "unauthorized" }, 401);
  }

  try {
    const nowIso = new Date().toISOString();

    // Everything due and not yet pushed, oldest first.
    const { data: reminders, error } = await admin
      .from("reminders")
      .select("id, auth_user_id, title, subtitle, category, priority, due_date, due_at")
      .eq("completed", false)
      .is("notified_at", null)
      .not("due_at", "is", null)
      .lte("due_at", nowIso)
      .order("due_at", { ascending: true })
      .limit(BATCH);
    if (error) throw error;

    const all = (reminders ?? []) as ReminderRow[];
    if (all.length === 0) {
      return json({ ok: true, reminders: 0, sent: 0, message: "nothing due" });
    }

    // Too old to be worth ringing: stamp and skip.
    const cutoff = Date.now() - MAX_AGE_MS;
    const stale = all.filter((r) => Date.parse(r.due_at) < cutoff);
    const due = all.filter((r) => Date.parse(r.due_at) >= cutoff);
    if (stale.length > 0) {
      await admin
        .from("reminders")
        .update({ notified_at: nowIso })
        .in("id", stale.map((r) => r.id));
    }
    if (due.length === 0) {
      return json({ ok: true, reminders: 0, sent: 0, skippedStale: stale.length });
    }

    const sa: ServiceAccount = JSON.parse(FCM_SERVICE_ACCOUNT);
    const accessToken = await mintAccessToken(sa);
    const endpoint =
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

    // One query for every owner's devices, rather than one per reminder.
    const ownerIds = [...new Set(due.map((r) => r.auth_user_id))];
    const { data: tokenRows } = await admin
      .from("device_tokens")
      .select("token, auth_user_id")
      .in("auth_user_id", ownerIds);

    const byOwner = new Map<string, string[]>();
    for (const row of (tokenRows ?? []) as TokenRow[]) {
      const list = byOwner.get(row.auth_user_id) ?? [];
      list.push(row.token);
      byOwner.set(row.auth_user_id, list);
    }

    let sent = 0;
    const deadTokens: string[] = [];
    const doneIds: string[] = [];
    const auditRows: Record<string, unknown>[] = [];

    for (const reminder of due) {
      const tokens = byOwner.get(reminder.auth_user_id) ?? [];
      if (tokens.length === 0) {
        // No device to reach. Stamp anyway: the phone's own local schedule is
        // the primary alarm, and retrying every minute forever helps nobody.
        doneIds.push(reminder.id);
        continue;
      }

      let deliveredCount = 0;
      let lastError: string | null = null;

      for (const token of tokens) {
        const res = await fetch(endpoint, {
          method: "POST",
          headers: {
            authorization: `Bearer ${accessToken}`,
            "content-type": "application/json",
          },
          body: JSON.stringify(buildMessage(reminder, token)),
        });

        if (res.ok) {
          sent++;
          deliveredCount++;
          continue;
        }

        const errorBody = await res.text();
        lastError = `${res.status}: ${errorBody.slice(0, 200)}`;
        if (res.status === 404 || res.status === 400) deadTokens.push(token);
        console.error(`send failed (${res.status}) for ${reminder.id}: ${errorBody}`);
      }

      // Stamp on delivery to at least one device, OR when every token was
      // dead (there is nothing left to retry against).
      if (deliveredCount > 0 || tokens.every((t) => deadTokens.includes(t))) {
        doneIds.push(reminder.id);
      }

      auditRows.push({
        auth_user_id: reminder.auth_user_id,
        kind: "reminder",
        title: reminder.title,
        body: bodyFor(reminder),
        devices_targeted: tokens.length,
        devices_delivered: deliveredCount,
        queued_at: reminder.due_at,
        error: lastError,
      });
    }

    if (doneIds.length > 0) {
      await admin
        .from("reminders")
        .update({ notified_at: nowIso })
        .in("id", doneIds);
    }

    if (deadTokens.length > 0) {
      await admin.from("device_tokens").delete().in("token", deadTokens);
    }

    if (auditRows.length > 0) {
      const { error: logErr } = await admin.from("push_log").insert(auditRows);
      if (logErr) console.error("push_log insert failed:", logErr);
    }

    return json({
      ok: true,
      reminders: due.length,
      sent,
      pruned: deadTokens.length,
      skippedStale: stale.length,
    });
  } catch (e) {
    console.error("send-reminder-push failed:", e);
    return json({ ok: false, error: String(e) }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
