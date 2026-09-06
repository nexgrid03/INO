import { NextRequest, NextResponse } from "next/server";
import { SUPABASE_URL, SUPABASE_ANON_KEY } from "@/lib/config";
import { getVisitorIp } from "@/lib/client-ip";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

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
