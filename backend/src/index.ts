import {
  handleLogin,
  handleLogout,
  handleMe,
  handleSignup,
} from './auth/routes';
import type { Env } from './env';
import { errorResponse, jsonResponse } from './http';
import { handleSync } from './sync/routes';

export type { Env } from './env';

export default {
  async fetch(request, env): Promise<Response> {
    const { pathname } = new URL(request.url);

    if (request.method === 'GET' && pathname === '/health') {
      return jsonResponse({ status: 'ok' });
    }
    if (request.method === 'POST' && pathname === '/auth/signup') {
      return handleSignup(request, env);
    }
    if (request.method === 'POST' && pathname === '/auth/login') {
      return handleLogin(request, env);
    }
    if (request.method === 'POST' && pathname === '/auth/logout') {
      return handleLogout(request, env);
    }
    if (request.method === 'GET' && pathname === '/auth/me') {
      return handleMe(request, env);
    }
    const syncMatch = pathname.match(/^\/sync\/([a-z_]+)$/);
    if (syncMatch) {
      if (request.method !== 'POST') {
        return errorResponse('method_not_allowed', 'Method not allowed.', 405);
      }
      return handleSync(request, env, syncMatch[1]);
    }

    return errorResponse('not_found', 'Route not found.', 404);
  },
} satisfies ExportedHandler<Env>;
