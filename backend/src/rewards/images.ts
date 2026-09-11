import { authenticate } from '../auth/sessions';
import type { Env } from '../env';
import { errorResponse } from '../http';

const maxBytes = 1024 * 1024;
const allowedTypes = new Set(['image/jpeg', 'image/webp']);

export async function uploadRewardImage(request: Request, env: Env): Promise<Response> {
  const user = await authenticate(request, env);
  if (!user) return errorResponse('unauthorized', 'Authentication is required.', 401);
  const type = request.headers.get('content-type')?.split(';')[0].toLowerCase();
  const length = Number(request.headers.get('content-length') ?? 0);
  if (!type || !allowedTypes.has(type) || !Number.isFinite(length) || length < 1 || length > maxBytes) return errorResponse('invalid_image', 'Use JPEG or WebP up to 1 MB.', 400);
  const body = await request.arrayBuffer();
  if (body.byteLength < 1 || body.byteLength > maxBytes) return errorResponse('invalid_image', 'Use JPEG or WebP up to 1 MB.', 400);
  const key = `rewards/${user.id}/${crypto.randomUUID()}.${type === 'image/webp' ? 'webp' : 'jpg'}`;
  await env.REWARD_IMAGES.put(key, body, { httpMetadata: { contentType: type }, customMetadata: { userId: user.id } });
  return Response.json({ data: { imageKey: key } });
}

export async function serveRewardImage(request: Request, env: Env, key: string): Promise<Response> {
  const user = await authenticate(request, env);
  if (!user) return errorResponse('unauthorized', 'Authentication is required.', 401);
  if (!key.startsWith(`rewards/${user.id}/`)) return errorResponse('not_found', 'Image not found.', 404);
  const object = await env.REWARD_IMAGES.get(key);
  if (!object || object.customMetadata?.userId !== user.id) return errorResponse('not_found', 'Image not found.', 404);
  return new Response(object.body, { headers: { 'content-type': object.httpMetadata?.contentType ?? 'image/jpeg', 'cache-control': 'private, max-age=300' } });
}

export async function removeRewardImage(request: Request, env: Env, key: string): Promise<Response> {
  const user = await authenticate(request, env);
  if (!user) return errorResponse('unauthorized', 'Authentication is required.', 401);
  if (!key.startsWith(`rewards/${user.id}/`)) return errorResponse('not_found', 'Image not found.', 404);
  const object = await env.REWARD_IMAGES.head(key);
  if (object?.customMetadata?.userId === user.id) await env.REWARD_IMAGES.delete(key);
  return new Response(null, { status: 204 });
}
