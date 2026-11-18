import { createBrowserClient } from "@supabase/ssr";

export function createCheckdSupabaseBrowserClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !publishableKey) {
    throw new Error("CheckD sign-in is not configured.");
  }
  return createBrowserClient(url, publishableKey);
}
