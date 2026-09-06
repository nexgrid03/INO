import { NextRequest, NextResponse } from "next/server";
import { SUPABASE_URL, SUPABASE_ANON_KEY } from "@/lib/config";
import { getVisitorIp } from "@/lib/client-ip";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

interface RateBucket {
  count: number;
  resetAt: number;
}

const WINDOW_MS = 15 * 60 * 1000; // 15 minutes
const MAX_PER_IP = 5;
const MAX_PER_EMAIL = 3;

const ipRateMap = new Map<string, RateBucket>();
const emailRateMap = new Map<string, RateBucket>();

function checkRateLimit(map: Map<string, RateBucket>, key: string, limit: number): boolean {
  const now = Date.now();
  const bucket = map.get(key);
  if (!bucket || bucket.resetAt <= now) {
    map.set(key, { count: 1, resetAt: now + WINDOW_MS });
    return true;
  }
  if (bucket.count >= limit) {
    return false;
  }
  bucket.count += 1;
  return true;
}

// Periodic cleanup of expired rate-limit records
setInterval(() => {
  const now = Date.now();
  for (const [k, v] of ipRateMap.entries()) {
    if (v.resetAt <= now) ipRateMap.delete(k);
  }
  for (const [k, v] of emailRateMap.entries()) {
    if (v.resetAt <= now) emailRateMap.delete(k);
  }
}, 60000);

export async function POST(req: NextRequest) {
  try {
    const ip = getVisitorIp(req.headers);
    const body = await req.json().catch(() => ({}));
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";

    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return NextResponse.json(
        { error: "Please enter a valid email address." },
        { status: 400 }
      );
    }

    // Rate limit check: IP bucket & Email bucket
    if (!checkRateLimit(ipRateMap, ip, MAX_PER_IP) || !checkRateLimit(emailRateMap, email, MAX_PER_EMAIL)) {
      return NextResponse.json(
        { error: "Too many deletion verification requests. Please try again later." },
        { status: 429, headers: { "Retry-After": "900" } }
      );
    }

    // Strict fail-closed: reject if Supabase credentials are not configured in environment
    if (!SUPABASE_ANON_KEY || SUPABASE_ANON_KEY.trim().length === 0) {
      console.error("[delete-request] SUPABASE_ANON_KEY is not configured (fail-closed).");
      return NextResponse.json(
        { error: "Account deletion service is currently unavailable. Please contact privacy@inoapp.in." },
        { status: 503 }
      );
    }

    // Call Supabase GoTrue OTP endpoint
    // create_user: false ensures OTP is only generated for existing accounts
    await fetch(`${SUPABASE_URL}/auth/v1/otp`, {
      method: "POST",
      headers: {
        "apikey": SUPABASE_ANON_KEY,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        email,
        create_user: false,
      }),
    });

    // Always respond with uniform success to prevent email enumeration
    return NextResponse.json({
      success: true,
      message: "If an account exists with this email, a verification code has been sent to your inbox.",
    });
  } catch (e: any) {
    console.error("[delete-request] Error:", e?.message);
    return NextResponse.json(
      { error: "An unexpected error occurred. Please try again later." },
      { status: 500 }
    );
  }
}
