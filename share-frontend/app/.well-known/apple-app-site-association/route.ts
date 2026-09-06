export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const DEFAULT_APPLE_TEAM_ID = "9JA6MVCD82";
const BUNDLE_ID = "com.ino.app";
const TEAM_ID_REGEX = /^[A-Z0-9]{10}$/;

export function getValidatedAppId(): string {
  const teamId = (process.env.APPLE_TEAM_ID || DEFAULT_APPLE_TEAM_ID).trim();

  if (
    teamId.includes("TEAMID") ||
    teamId.includes("YOUR_TEAM_ID") ||
    teamId.includes("PLACEHOLDER") ||
    teamId.includes("<") ||
    teamId.includes(">")
  ) {
    throw new Error(`Invalid Apple Team ID placeholder detected: '${teamId}'`);
  }

  if (!TEAM_ID_REGEX.test(teamId)) {
    throw new Error(
      `Apple Developer Team ID must be exactly 10 alphanumeric uppercase characters. Received: '${teamId}'`
    );
  }

  return `${teamId}.${BUNDLE_ID}`;
}

export async function GET() {
  const appId = getValidatedAppId();
  const payload = {
    applinks: {
      apps: [],
      details: [
        {
          appID: appId,
          components: [
            { "/": "/s/*", comment: "Matches share URLs" },
            { "/": "/v/*", comment: "Matches view-once URLs" },
            { "/": "/share/*", comment: "Matches legacy share URLs" },
          ],
          paths: ["/s/*", "/v/*", "/share/*"],
        },
      ],
    },
    webcredentials: {
      apps: [appId],
    },
  };

  return new Response(JSON.stringify(payload, null, 2), {
    status: 200,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "public, max-age=3600, stale-while-revalidate=86400",
    },
  });
}
