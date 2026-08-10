// ============================================================================
// INO - Reminder push notifications (Supabase Edge Function)
// ----------------------------------------------------------------------------
// Runs on a daily cron, finds every reminder that is due at one of the lead
// times below, and pushes it to the owner's devices via Firebase Cloud
// Messaging. Firebase is ONLY the transport - the data never leaves Supabase.
//
//   1. Scan `public.reminders` for active rows whose due_date is today,
//      tomorrow, or a week out (and overdue rows, which nag once a day).
//   2. Join `public.device_tokens` to resolve each owner's devices.
//   3. Send via the FCM HTTP **v1** API, authenticated with a short-lived
//      OAuth2 access token minted from the Firebase service account.
//   4. Prune tokens FCM reports as dead, and stamp `last_push_sent_on` so a
//      second run on the same day is a no-op.
//
// Why v1 and not the one-line `key=AAAA…` call in most tutorials: the FCM
// legacy HTTP API was shut down in 2024. v1 requires a real OAuth2 bearer
// token, which is what mintAccessToken() below produces.
//
// Secrets (supabase secrets set …):
//   FCM_SERVICE_ACCOUNT  - the full service-account JSON, one line. Get it from
//                          Firebase Console → Project settings → Service
//                          accounts → Generate new private key.
//
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are injected by the platform. The
// service role bypasses RLS by design - that is how one run fans out to every
// user - so the caller is authorized in-function by isTrustedCaller() below.
//
// SECURITY: do NOT rely on the platform's `verify_jwt` alone here. The
// publishable anon key is a valid signed project JWT that ships inside the
// mobile app, so "verify_jwt = true" still lets anybody run this job. That was
// a live finding: an anon-key POST returned {"ok":true,"sent":4} and delivered
// four real notifications. The in-function shared-secret check is the control.
//
// Deploy:  supabase functions deploy send-reminder-push        (verify_jwt on)
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const FCM_SERVICE_ACCOUNT = Deno.env.get("FCM_SERVICE_ACCOUNT")!;

/// Optional dedicated secret for the scheduler, so the cron job does not have
/// to carry the service-role key at all:
///   supabase secrets set CRON_SECRET=<random string>
/// then send it as the `x-cron-secret` header. When unset, only the
/// service-role key is accepted (the path PUSH_NOTIFICATIONS.md documents).
const CRON_SECRET = Deno.env.get("CRON_SECRET") ?? "";

/// Must match PushService.channelId in lib/services/push_service.dart and
/// `default_notification_channel_id` in AndroidManifest.xml. Android 8+ drops
/// a notification addressed to a channel that does not exist.
const ANDROID_CHANNEL = "ino_reminders";

/// How many days ahead of a due date to notify. 0 = the day itself.
const LEAD_DAYS = [0, 1, 7];

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
  due_date: string;          // YYYY-MM-DD
  last_push_sent_on: string | null;
}

interface TokenRow {
  token: string;
  auth_user_id: string;
}

// ----------------------------------------------------------------------------
// Google OAuth2: service account → access token
// ----------------------------------------------------------------------------

/// Signs a JWT with the service account's RSA key and exchanges it for a
/// 1-hour access token scoped to FCM.
///
/// Done by hand with WebCrypto rather than google-auth-library: the Node
/// library pulls a large dependency tree into the Deno runtime and measurably
/// slows cold starts, for what amounts to one signature and one fetch.
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

/// Base64url, no padding - what JWS requires.
function base64Url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

/// Strips the PEM armour and decodes to the DER bytes WebCrypto wants.
/// The `\n` replace matters: the private key arrives from the environment as a
/// JSON string with escaped newlines, and importKey rejects it otherwise.
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

/// Whole days from today to [dueDate], both truncated to a date.
function daysUntil(dueDate: string, today: string): number {
  const a = Date.parse(`${dueDate}T00:00:00Z`);
  const b = Date.parse(`${today}T00:00:00Z`);
  return Math.round((a - b) / 86_400_000);
}

/// The human line under the title. Mirrors Reminder.dueLabel in
/// lib/models/reminder_models.dart so the push and the in-app card agree.
function dueLabel(days: number): string {
  if (days < 0) return days === -1 ? "Overdue by 1 day" : `Overdue by ${-days} days`;
  if (days === 0) return "Due today";
  if (days === 1) return "Due tomorrow";
  return `Due in ${days} days`;
}

function buildMessage(reminder: ReminderRow, token: string, days: number) {
  const body = reminder.subtitle
    ? `${dueLabel(days)} · ${reminder.subtitle}`
    : dueLabel(days);

  return {
    message: {
      token,
      notification: { title: reminder.title, body },
      // Mirrored into `data` because a `notification` payload is NOT delivered
      // to Dart when the app is backgrounded - only `data` survives the tap,
      // and PushService reads reminder_id from it to open the right sheet.
      data: {
        reminder_id: reminder.id,
        category: reminder.category,
        priority: reminder.priority,
        due_date: reminder.due_date,
      },
      android: {
        priority: "HIGH",
        notification: { channel_id: ANDROID_CHANNEL, sound: "default" },
      },
      apns: {
        payload: { aps: { sound: "default", badge: 1 } },
      },
    },
  };
}

// ----------------------------------------------------------------------------
// Entry point
// ----------------------------------------------------------------------------

/// Constant-time string compare. A plain `===` returns early at the first
/// differing byte, which leaks how much of a secret a guess got right.
function secretEquals(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/// True only for a trusted backend caller (the cron job or an operator).
///
/// Platform `verify_jwt` is NOT sufficient on its own, and relying on it was
/// the bug: the publishable anon key is itself a valid, correctly-signed
/// project JWT, and it ships inside every copy of the mobile app. A function
/// that only asks "was there a valid JWT?" is therefore world-callable.
///
/// This job runs with the service role (RLS bypassed) across EVERY user's
/// reminders and sends real push notifications, so the caller has to prove it
/// is the scheduler - not merely that it is authenticated. Checking a shared
/// secret rather than a JWT claim also means the guard holds even if the
/// function is ever deployed with --no-verify-jwt, where any role claim in an
/// unverified token would be forgeable.
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

  // Authorization first: never touch FCM or the reminders table for a caller
  // that has not proved it is the scheduler. Anon key, a normal user's JWT and
  // an invalid token all land here.
  if (!isTrustedCaller(req)) {
    console.warn("send-reminder-push: rejected untrusted caller");
    return json({ ok: false, error: "unauthorized" }, 401);
  }

  try {
    const sa: ServiceAccount = JSON.parse(FCM_SERVICE_ACCOUNT);
    const accessToken = await mintAccessToken(sa);
    const endpoint =
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

    // "Today" in IST, not UTC. The cron fires at 03:30 UTC, which is already
    // the NEXT day in India - computing the date in UTC would silently notify
    // everyone a day early.
    const today = new Date(Date.now() + 5.5 * 3600_000).toISOString().slice(0, 10);
    const targets = LEAD_DAYS.map((d) =>
      new Date(Date.parse(`${today}T00:00:00Z`) + d * 86_400_000)
        .toISOString().slice(0, 10)
    );

    // Active reminders that are due at a lead time OR already overdue. Rows
    // already pushed today are filtered out so a second run is a no-op.
    const { data: reminders, error } = await admin
      .from("reminders")
      .select("id, auth_user_id, title, subtitle, category, priority, due_date, last_push_sent_on")
      .eq("completed", false)
      .lte("due_date", targets[targets.length - 1])
      .or(`last_push_sent_on.is.null,last_push_sent_on.lt.${today}`);
    if (error) throw error;

    const due = (reminders ?? []).filter((r: ReminderRow) => {
      const d = daysUntil(r.due_date, today);
      return d < 0 || LEAD_DAYS.includes(d);
    });

    if (due.length === 0) {
      return json({ ok: true, reminders: 0, sent: 0, message: "nothing due" });
    }

    // One query for every owner's devices, rather than one per reminder.
    const ownerIds = [...new Set(due.map((r: ReminderRow) => r.auth_user_id))];
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
    const pushedReminderIds: string[] = [];

    for (const reminder of due as ReminderRow[]) {
      const tokens = byOwner.get(reminder.auth_user_id) ?? [];
      if (tokens.length === 0) continue;   // owner has no device registered

      const days = daysUntil(reminder.due_date, today);
      let deliveredForThisReminder = false;

      for (const token of tokens) {
        const res = await fetch(endpoint, {
          method: "POST",
          headers: {
            authorization: `Bearer ${accessToken}`,
            "content-type": "application/json",
          },
          body: JSON.stringify(buildMessage(reminder, token, days)),
        });

        if (res.ok) {
          sent++;
          deliveredForThisReminder = true;
          continue;
        }

        const errorBody = await res.text();
        // 404 UNREGISTERED / 400 INVALID_ARGUMENT mean the app was uninstalled
        // or the token rotated. Collect them for deletion: left in place they
        // accumulate forever and every future run wastes a request on each.
        if (res.status === 404 || res.status === 400) {
          deadTokens.push(token);
        }
        console.error(`send failed (${res.status}) for ${reminder.id}: ${errorBody}`);
      }

      if (deliveredForThisReminder) pushedReminderIds.push(reminder.id);
    }

    // Stamp only the reminders that actually reached a device, so one that
    // failed everywhere is retried on the next run instead of being lost.
    if (pushedReminderIds.length > 0) {
      await admin
        .from("reminders")
        .update({ last_push_sent_on: today })
        .in("id", pushedReminderIds);
    }

    if (deadTokens.length > 0) {
      await admin.from("device_tokens").delete().in("token", deadTokens);
    }

    return json({
      ok: true,
      reminders: due.length,
      sent,
      pruned: deadTokens.length,
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
