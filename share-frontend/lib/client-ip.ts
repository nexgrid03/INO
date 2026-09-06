/**
 * Client IP extraction, validation, and safe upstream proxy header generation.
 *
 * Designed for Vercel edge/serverless reverse-proxy chains and local development.
 * Strictly validates IP format to eliminate header injection and IP spoofing risks.
 */

export const SHARE_PROXY_SECRET =
  process.env.SHARE_PROXY_SECRET || "ino-share-proxy-v1-production-auth";

const IPV4_REGEX =
  /^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$/;

const IPV6_REGEX =
  /^(([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|:([0-9a-fA-F]{1,4}:){1,7}|(([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4})|::(ffff(:0{1,4}){0,1}:){0,1}(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})$/;

export function isValidIp(ip: string | null | undefined): boolean {
  if (!ip) return false;
  const trimmed = ip.trim();
  return IPV4_REGEX.test(trimmed) || IPV6_REGEX.test(trimmed);
}

/**
 * Extracts and validates visitor client IP from incoming Next.js request headers.
 * 1. Checks `x-real-ip` (Vercel edge socket IP, cannot be spoofed by client).
 * 2. Checks first hop of `x-forwarded-for`.
 * 3. Falls back to `127.0.0.1` for local development.
 */
export function getVisitorIp(headers: Headers): string {
  // 1. Vercel edge sets x-real-ip to client TCP socket connection IP
  const realIp = headers.get("x-real-ip")?.trim();
  if (realIp && isValidIp(realIp)) {
    return realIp;
  }

  // 2. x-forwarded-for: client, proxy1, proxy2...
  const forwarded = headers.get("x-forwarded-for");
  if (forwarded) {
    const first = forwarded.split(",")[0]?.trim();
    if (first && isValidIp(first)) {
      return first;
    }
  }

  // 3. Fallback for local development or direct environment
  return "127.0.0.1";
}

/**
 * Builds safe upstream headers to pass the visitor's authenticated IP to the Supabase share function.
 */
export function getProxyHeaders(headers: Headers): Record<string, string> {
  const visitorIp = getVisitorIp(headers);
  return {
    "x-real-ip": visitorIp,
    "x-forwarded-for": visitorIp,
    "x-ino-proxy-token": SHARE_PROXY_SECRET,
  };
}
