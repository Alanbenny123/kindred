import { createHash } from 'node:crypto';

export class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export const text = (value, max = 200) => String(value ?? '').trim().replace(/\s+/g, ' ').slice(0, max);

export function ageOf(birthDate, now = new Date()) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(birthDate))) return null;
  const date = new Date(`${birthDate}T00:00:00Z`);
  if (Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== birthDate) return null;
  let age = now.getUTCFullYear() - date.getUTCFullYear();
  if (now < new Date(Date.UTC(now.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()))) age--;
  return age;
}

export function validateProfile(body, existing = null) {
  const result = {
    name: text(body.name, 40),
    city: text(body.city, 60),
    gender: body.gender,
    lookingFor: body.lookingFor,
    intent: body.intent,
    bio: text(body.bio, 500),
    prompt: text(body.prompt, 180),
    interests: Array.isArray(body.interests) ? [...new Set(body.interests.map(x => text(x, 24)).filter(Boolean))].slice(0, 6) : [],
    birthDate: existing?.birthDate ?? body.birthDate,
  };
  if (result.name.length < 2) throw new HttpError(400, 'Enter a name with at least 2 characters.');
  if (result.city.length < 2) throw new HttpError(400, 'Enter your city.');
  if (!['woman', 'man', 'nonbinary'].includes(result.gender)) throw new HttpError(400, 'Choose a gender.');
  if (!['everyone', 'woman', 'man', 'nonbinary'].includes(result.lookingFor)) throw new HttpError(400, 'Choose who you want to meet.');
  if (!['Long-term relationship', 'Open to possibilities', 'Getting to know people'].includes(result.intent)) throw new HttpError(400, 'Choose your dating intention.');
  const age = ageOf(result.birthDate);
  if (age === null || age < 18 || age > 100) throw new HttpError(400, 'You must be at least 18 to use Kindred.');
  return result;
}

export function idFor(prefix, ...parts) {
  return `${prefix}_${createHash('sha256').update(parts.join('\0')).digest('hex').slice(0, 32)}`;
}

export function pairId(a, b) {
  return idFor('m', ...[a, b].sort());
}

export function matchesPreference(gender, lookingFor) {
  return lookingFor === 'everyone' || gender === lookingFor;
}

export function eligible(viewer, target) {
  return target && target.$id !== viewer.$id && target.status === 'active' &&
    target.city.toLowerCase() === viewer.city.toLowerCase() &&
    matchesPreference(target.gender, viewer.lookingFor) &&
    matchesPreference(viewer.gender, target.lookingFor);
}

export function publicProfile(profile) {
  return {
    id: profile.$id,
    name: profile.name,
    age: ageOf(profile.birthDate),
    city: profile.city,
    gender: profile.gender,
    intent: profile.intent,
    bio: profile.bio || '',
    prompt: profile.prompt || '',
    interests: profile.interests || [],
    color: profile.color || 'coral',
    photo: Boolean(profile.photoKey),
    demo: false,
  };
}
