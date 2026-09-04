import {
  handleLogin,
  handleLogout,
  handleMe,
  handleSignup,
} from './auth/routes';
import type { Env } from './env';
import { errorResponse, jsonResponse } from './http';

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

    return errorResponse('not_found', 'Route not found.', 404);
  },
} satisfies ExportedHandler<Env>;
