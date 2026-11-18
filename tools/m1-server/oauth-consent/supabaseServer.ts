import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

/** Use only the public project URL and publishable key in this browser-facing UI. */
export async function createCheckdSupabaseServerClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const publishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if (!url || !publishableKey) {
    throw new Error("Supabase OAuth consent UI is not configured.");
  }

  const cookieStore = await cookies();
  return createServerClient(url, publishableKey, {
    cookies: {
      getAll: () => cookieStore.getAll(),
      setAll: (values) => {
        try {
          values.forEach(({ name, value, options }) =>
            cookieStore.set(name, value, options));
        } catch {
          // Server Components cannot set cookies. proxy.ts refreshes and
          // persists sessions before these routes are rendered.
        }
      },
    },
  });
}
