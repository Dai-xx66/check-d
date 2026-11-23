import { createAgentHandler } from './core.mjs';
import { defaultKey, serviceHeaders, supportsImages } from './settings.mjs';

const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? '';
const publicKey = Deno.env.get('SUPABASE_ANON_KEY')?.trim() || defaultKey(Deno.env.get('SUPABASE_PUBLISHABLE_KEYS'));
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')?.trim() || defaultKey(Deno.env.get('SUPABASE_SECRET_KEYS'));
const model = Deno.env.get('DEEPSEEK_MODEL') ?? 'deepseek-flash';

// Both credentials stay inside the Edge runtime. Auth verifies the caller with
// the public key; only the gateway can reserve quota with the server key. The
// target user ID always comes from Auth, never from body.userId.
const handler = createAgentHandler({
  config: {
    apiKey: Deno.env.get('DEEPSEEK_API_KEY') ?? '',
    baseUrl: Deno.env.get('DEEPSEEK_BASE_URL') ?? 'https://api.deepseek.com',
    model,
    supportsImages: supportsImages(Deno.env.get('DEEPSEEK_SUPPORTS_IMAGES'), model),
    allowedOrigins: Deno.env.get('AGENT_ALLOWED_ORIGINS') ?? '',
  },
  authenticate: async (request: Request) => {
    const authorization = request.headers.get('authorization') ?? '';
    if (!supabaseUrl || !publicKey || !serviceKey || !/^Bearer\s+\S+$/i.test(authorization)) return null;
    const response = await fetch(supabaseUrl + '/auth/v1/user', {
      headers: { apikey: publicKey, authorization }, signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) return null;
    const user = await response.json();
    if (!user?.id || user.is_anonymous === true) return null;
    return { id: user.id };
  },
  reserveQuota: async (userId: string, _request: Request) => {
    const response = await fetch(supabaseUrl + '/rest/v1/rpc/reserve_checkd_agent_request', {
      method: 'POST',
      headers: serviceHeaders(serviceKey),
      body: JSON.stringify({ p_user_id: userId }), signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) throw new Error('Quota service unavailable');
    return (await response.json()) === true;
  },
});
Deno.serve(handler);
