import { NextResponse } from "next/server";
import { createCheckdSupabaseServerClient } from "./supabaseServer";

/** Mount this handler at app/api/oauth/decision/route.ts in the CheckD web host. */
export async function POST(request: Request) {
  const origin = request.headers.get("origin");
  if (!origin || origin !== new URL(request.url).origin) {
    return noStoreJson({ error: "Request origin rejected." }, 403);
  }

  let form: FormData;
  try {
    form = await request.formData();
  } catch {
    return noStoreJson({ error: "Invalid consent request." }, 400);
  }
  const authorizationId = form.get("authorization_id");
  const decision = form.get("decision");
  if (typeof authorizationId !== "string" || !authorizationId.trim()
      || authorizationId.length > 512
      || (decision !== "approve" && decision !== "deny")) {
    return noStoreJson({ error: "Invalid consent request." }, 400);
  }

  const supabase = await createCheckdSupabaseServerClient();
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) {
    return noStoreJson({ error: "Sign in to CheckD before continuing." }, 401);
  }

  // Re-fetch the pending authorization under this request's user session.
  // Never treat form fields as proof of the requesting client or current user.
  const { data: authorization, error: authorizationError } =
    await supabase.auth.oauth.getAuthorizationDetails(authorizationId);
  if (authorizationError || !authorization || !("authorization_id" in authorization)
      || authorization.authorization_id !== authorizationId) {
    return noStoreJson({ error: "Authorization request is no longer pending." }, 409);
  }

  const result = decision === "approve"
    ? await supabase.auth.oauth.approveAuthorization(authorizationId)
    : await supabase.auth.oauth.denyAuthorization(authorizationId);
  if (result.error || !result.data?.redirect_url) {
    return noStoreJson({ error: "The authorization request could not be completed." }, 400);
  }

  // Only redirect to the URL returned by Supabase Auth; never accept a redirect
  // target from the form or query string.
  const response = NextResponse.redirect(result.data.redirect_url, 303);
  response.headers.set("Cache-Control", "private, no-store");
  return response;
}

function noStoreJson(body: Record<string, string>, status: number) {
  const response = NextResponse.json(body, { status });
  response.headers.set("Cache-Control", "private, no-store");
  return response;
}
