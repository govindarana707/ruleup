import {
  handleLogin,
  handleLogout,
  handleMe,
  handleSignup,
} from './auth/routes';
import type { Env } from './env';
import { errorResponse, jsonResponse } from './http';
import { handlePull } from './sync/pull';
import { handleSync } from './sync/routes';
import { removeRewardImage, serveRewardImage, uploadRewardImage } from './rewards/images';

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
    if (request.method === 'POST' && pathname === '/reward-images') return uploadRewardImage(request, env);
    const imageMatch = pathname.match(/^\/reward-images\/(.+)$/);
    if (imageMatch) {
      const key = decodeURIComponent(imageMatch[1]);
      if (request.method === 'GET') return serveRewardImage(request, env, key);
      if (request.method === 'DELETE') return removeRewardImage(request, env, key);
      return errorResponse('method_not_allowed', 'Method not allowed.', 405);
    }
    if (request.method === 'GET' && pathname === '/sync/pull') {
      return handlePull(request, env);
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
