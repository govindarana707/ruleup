export function jsonResponse(body: unknown, status = 200): Response {
  return Response.json(body, {
    status,
    headers: { 'cache-control': 'no-store' },
  });
}

export function errorResponse(
  code: string,
  message: string,
  status: number,
): Response {
  return jsonResponse({ error: { code, message } }, status);
}
