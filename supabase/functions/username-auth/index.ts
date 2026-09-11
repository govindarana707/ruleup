import { createClient } from 'npm:@supabase/supabase-js@2';

const headers = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Content-Type': 'application/json',
};

const reply = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers });

const normalizedUsername = (value: unknown) =>
  typeof value === 'string' ? value.normalize('NFKC').trim().toLowerCase() : '';

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers });
  if (request.method !== 'POST') return reply(405, { error: 'method_not_allowed' });

  try {
    const body = await request.json();
    const action = body?.action;
    const username = normalizedUsername(body?.username);
    const password = body?.password;
    if (!['login', 'signup'].includes(action) ||
        !/^[a-z0-9_]{3,30}$/.test(username) ||
        typeof password !== 'string' || password.length < 12 || password.length > 128) {
      return reply(400, { error: 'invalid_credentials' });
    }

    const url = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!url || !anonKey || !serviceKey) return reply(503, { error: 'not_configured' });
    const admin = createClient(url, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const auth = createClient(url, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    let userId: string;
    let createdByRequest = false;
    if (action === 'signup') {
      const existing = await admin.from('profiles').select('id').eq('username', username).maybeSingle();
      if (existing.error) throw existing.error;
      if (existing.data) return reply(409, { error: 'username_unavailable' });
      userId = crypto.randomUUID();
      const created = await admin.auth.admin.createUser({
        id: userId,
        email: `${userId}@auth.ruleup.invalid`,
        password,
        email_confirm: true,
        user_metadata: { username },
        app_metadata: { identity_source: 'ruleup_supabase' },
      });
      if (created.error) return reply(409, { error: 'username_unavailable' });
      createdByRequest = true;
    } else {
      const profile = await admin.from('profiles').select('id, username').eq('username', username).maybeSingle();
      if (profile.error) throw profile.error;
      if (!profile.data) return reply(401, { error: 'invalid_credentials' });
      userId = profile.data.id;
    }

    const signedIn = await auth.auth.signInWithPassword({
      email: `${userId}@auth.ruleup.invalid`,
      password,
    });
    if (signedIn.error || !signedIn.data.session || signedIn.data.user?.id !== userId) {
      if (createdByRequest) await admin.auth.admin.deleteUser(userId);
      return reply(401, { error: 'invalid_credentials' });
    }
    const session = signedIn.data.session;
    return reply(200, {
      data: {
        user: { id: userId, username },
        supabaseSession: {
          accessToken: session.access_token,
          refreshToken: session.refresh_token,
          expiresAt: session.expires_at,
          userId,
          username,
        },
      },
    });
  } catch (error) {
    console.error('username-auth failed', error instanceof Error ? error.message : 'unknown');
    return reply(500, { error: 'authentication_failed' });
  }
});
