import { NextRequest, NextResponse } from "next/server";
import { SUPABASE_URL, SUPABASE_ANON_KEY } from "@/lib/config";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function POST(req: NextRequest) {
  try {
    const body = await req.json().catch(() => ({}));
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    const code = typeof body.code === "string" ? body.code.trim() : "";

    if (!email || !code) {
      return NextResponse.json(
        { error: "Email and verification code are required." },
        { status: 400 }
      );
    }

    // Strict fail-closed: reject if Supabase credentials are not configured in environment
    if (!SUPABASE_ANON_KEY || SUPABASE_ANON_KEY.trim().length === 0) {
      console.error("[delete-confirm] SUPABASE_ANON_KEY is not configured (fail-closed).");
      return NextResponse.json(
        { error: "Account deletion service is currently unavailable. Please contact privacy@inoapp.in." },
        { status: 503 }
      );
    }

    // 1. Verify OTP code with Supabase GoTrue
    const verifyRes = await fetch(`${SUPABASE_URL}/auth/v1/verify`, {
      method: "POST",
      headers: {
        "apikey": SUPABASE_ANON_KEY,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        email,
        token: code,
        type: "email",
      }),
    });

    if (!verifyRes.ok) {
      const errData = await verifyRes.json().catch(() => ({}));
      return NextResponse.json(
        { error: errData.msg || errData.error_description || "Invalid or expired verification code." },
        { status: 400 }
      );
    }

    const sessionData = await verifyRes.json();
    const accessToken = sessionData.access_token;

    if (!accessToken) {
      return NextResponse.json(
        { error: "Failed to establish verified session for deletion." },
        { status: 400 }
      );
    }

    // 2. Invoke the delete_account() RPC with the verified user's authenticated session
    const rpcRes = await fetch(`${SUPABASE_URL}/rest/v1/rpc/delete_account`, {
      method: "POST",
      headers: {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({}),
    });

    if (!rpcRes.ok) {
      const rpcErr = await rpcRes.text().catch(() => "Unknown RPC error");
      console.error("[delete-confirm] delete_account RPC failed:", rpcErr);
      return NextResponse.json(
        { error: "Failed to delete account data. Please contact privacy@inoapp.in for manual assistance." },
        { status: 500 }
      );
    }

    return NextResponse.json({
      success: true,
      message: "Your account and all associated personal data have been permanently deleted.",
    });
  } catch (e: any) {
    console.error("[delete-confirm] Error:", e?.message);
    return NextResponse.json(
      { error: "An unexpected error occurred during account deletion." },
      { status: 500 }
    );
  }
}
