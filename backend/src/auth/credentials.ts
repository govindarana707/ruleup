const passwordAlgorithm = 'pbkdf2_sha256';
const passwordIterations = 600_000;
const saltLength = 16;
const hashLengthBits = 256;

const encoder = new TextEncoder();

export interface Credentials {
  username: string;
  password: string;
}

export function normalizeUsername(username: string): string {
  return username.trim().normalize('NFKC').toLowerCase();
}

export function validateCredentials(value: unknown): Credentials | null {
  if (!isRecord(value)) {
    return null;
  }

  const { username, password } = value;
  if (typeof username !== 'string' || typeof password !== 'string') {
    return null;
  }

  const normalizedUsername = normalizeUsername(username);
  const isValidUsername = /^[a-z0-9_]{3,30}$/.test(normalizedUsername);
  const isValidPassword = password.length >= 12 && password.length <= 128;

  if (!isValidUsername || !isValidPassword) {
    return null;
  }

  return { username: normalizedUsername, password };
}

export async function hashPassword(password: string): Promise<string> {
  const salt = crypto.getRandomValues(new Uint8Array(saltLength));
  const hash = await derivePasswordHash(password, salt, passwordIterations);

  return [
    passwordAlgorithm,
    passwordIterations.toString(),
    toBase64Url(salt),
    toBase64Url(hash),
  ].join('$');
}

export async function verifyPassword(
  password: string,
  encodedHash: string,
): Promise<boolean> {
  const [algorithm, iterationsText, saltText, expectedHashText] =
    encodedHash.split('$');
  const iterations = Number(iterationsText);

  if (
    algorithm !== passwordAlgorithm ||
    !Number.isSafeInteger(iterations) ||
    iterations !== passwordIterations ||
    !saltText ||
    !expectedHashText
  ) {
    return false;
  }

  try {
    const salt = fromBase64Url(saltText);
    const expectedHash = fromBase64Url(expectedHashText);
    const actualHash = await derivePasswordHash(password, salt, iterations);
    return constantTimeEqual(actualHash, expectedHash);
  } catch {
    return false;
  }
}

async function derivePasswordHash(
  password: string,
  salt: Uint8Array,
  iterations: number,
): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(password),
    'PBKDF2',
    false,
    ['deriveBits'],
  );
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', hash: 'SHA-256', salt, iterations },
    key,
    hashLengthBits,
  );
  return new Uint8Array(bits);
}

function constantTimeEqual(left: Uint8Array, right: Uint8Array): boolean {
  if (left.length !== right.length) {
    return false;
  }

  let difference = 0;
  for (let index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference === 0;
}

function toBase64Url(value: Uint8Array): string {
  let binary = '';
  for (const byte of value) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replace(/=+$/, '');
}

function fromBase64Url(value: string): Uint8Array {
  const base64 = value.replaceAll('-', '+').replaceAll('_', '/');
  const padded = base64.padEnd(Math.ceil(base64.length / 4) * 4, '=');
  return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0));
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
