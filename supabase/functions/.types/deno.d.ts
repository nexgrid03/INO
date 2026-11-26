// Ambient type declarations for standard TypeScript language servers (VS Code /
// Antigravity) when the Deno extension (`denoland.vscode-deno`) is not active.
// Supabase Edge Functions run on Deno natively, where `Deno` and URL imports
// resolve directly at runtime and are excluded from this shim via `deno.json`.

declare namespace Deno {
  export const env: {
    get(key: string): string | undefined;
    set(key: string, value: string): void;
    delete(key: string): void;
    toObject(): Record<string, string>;
  };

  export function serve(
    handler: (req: Request) => Response | Promise<Response>,
  ): unknown;
}

declare module "https://esm.sh/*" {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const value: any;
  export default value;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  export function createClient(...args: any[]): any;
}
