import { validateState } from './model.js';

// CloudKit transports this document unchanged. It contains no account identifiers.
// Each mutable value has its own revision so changing a habit name on one device
// cannot overwrite a journal entry added offline on another device.
const MAX_BYTES = 10 * 1024 * 1024;
const MAX_HABITS = 1000; // Includes tombstones, which must survive future merges.
const MAX_ITEMS = 20000;
const FIELDS = ['name', 'reason', 'startedAt', 'createdAt'];
const COLLECTIONS = ['history', 'checkins', 'entries'];
const fail = () => { throw new Error('This is not a valid Habit Counter sync document.'); };
const dictionary = () => Object.create(null);
const object = value => value && typeof value === 'object' && !Array.isArray(value);
const identifier = value => typeof value === 'string' && value.length > 0 && value.length <= 100 && !['__proto__', 'constructor', 'prototype'].includes(value);
const text = (value, max = 12000) => typeof value === 'string' && value.length <= max;
const stamp = (value, now) => Number.isSafeInteger(value) && value >= 0 && value <= now;
function validDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T12:00:00Z`);
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value;
}
function stable(value) {
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stable).join(',')}]`;
  return `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${stable(value[key])}`).join(',')}}`;
}
function noteEntryId(id) {
  if (id.length <= 87) return `checkin-note:${id}`;
  let hash = 14695981039346656037n;
  for (const byte of new TextEncoder().encode(id)) hash = BigInt.asUintN(64, (hash ^ BigInt(byte)) * 1099511628211n);
  return `checkin-note:${hash.toString(16)}`;
}
function revision(raw, now) {
  // Allow a small clock difference, but reject remote timestamps that could pin
  // a value far into the future and prevent ordinary edits from taking effect.
  if (!object(raw) || !stamp(raw.time, now + 300000) || !identifier(raw.device)) fail();
  return { time: raw.time, device: raw.device };
}
function compare(a, b) {
  return a.time - b.time || (a.device < b.device ? -1 : a.device > b.device ? 1 : 0);
}
function winner(a, b) {
  if (!a) return b;
  if (!b) return a;
  const order = compare(a.revision, b.revision);
  return order > 0 ? a : order < 0 ? b : stable(a) >= stable(b) ? a : b;
}
function canonicalMap(raw, callback, maximum = MAX_ITEMS) {
  if (!object(raw)) fail();
  const keys = Object.keys(raw).sort();
  if (keys.length > maximum) fail();
  const output = dictionary();
  for (const key of keys) output[key] = callback(raw[key], key);
  return output;
}
function validateItem(value, type, key, now) {
  if (!object(value) || !identifier(value.id) || value.id !== key) fail();
  if (type === 'history') {
    if (!stamp(value.startedAt, now) || !stamp(value.endedAt, now) || value.endedAt < value.startedAt || !text(value.trigger, 100) || !text(value.note)) fail();
    return { id: value.id, startedAt: value.startedAt, endedAt: value.endedAt, trigger: value.trigger, note: value.note };
  }
  if (type === 'checkins') {
    if (!validDate(value.date) || !stamp(value.at, now) || !['great', 'good', 'okay', 'low', 'tough'].includes(value.mood) || !text(value.note)) fail();
    return { id: value.id, date: value.date, at: value.at, mood: value.mood, note: value.note };
  }
  if (!stamp(value.at, now) || !text(value.text) || !value.text.trim()) fail();
  return { id: value.id, at: value.at, text: value.text };
}

export function validateSyncDocument(raw, now = Date.now()) {
  try {
    if (new TextEncoder().encode(JSON.stringify(raw)).byteLength > MAX_BYTES) fail();
  } catch { fail(); }
  if (!object(raw) || raw.version !== 1) fail();
  const habits = canonicalMap(raw.habits, (habit, id) => {
    if (!identifier(id) || !object(habit) || !object(habit.alive) || typeof habit.alive.value !== 'boolean' || !object(habit.fields)) fail();
    const fields = dictionary();
    for (const field of FIELDS) {
      const value = habit.fields[field];
      if (!object(value)) fail();
      if (field === 'name' && (!text(value.value, 60) || !value.value.trim())) fail();
      if (field === 'reason' && !text(value.value, 500)) fail();
      if (['startedAt', 'createdAt'].includes(field) && !stamp(value.value, now)) fail();
      fields[field] = { value: value.value, revision: revision(value.revision, now) };
    }
    const out = { alive: { value: habit.alive.value, revision: revision(habit.alive.revision, now) }, fields };
    for (const type of COLLECTIONS) out[type] = canonicalMap(habit[type], (item, key) => {
      if (!identifier(key) || !object(item) || typeof item.deleted !== 'boolean') fail();
      return { value: validateItem(item.value, type, key, now), revision: revision(item.revision, now), deleted: item.deleted };
    });
    out.goals = canonicalMap(habit.goals, (goal, key) => {
      const parts = key.split(':');
      if (parts.length !== 2 || !validDate(parts[0]) || !['0', '1', '2'].includes(parts[1]) || !object(goal) || typeof goal.value !== 'boolean') fail();
      return { value: goal.value, revision: revision(goal.revision, now) };
    }, MAX_ITEMS * 3);
    return out;
  }, MAX_HABITS);
  return { version: 1, habits };
}

function latestTime(document) {
  let latest = 0;
  for (const h of Object.values(document.habits)) {
    latest = Math.max(latest, h.alive.revision.time);
    for (const type of ['fields', ...COLLECTIONS, 'goals']) for (const item of Object.values(h[type])) latest = Math.max(latest, item.revision.time);
  }
  return latest;
}
function mergeMap(a, b) {
  const output = dictionary();
  for (const key of [...new Set([...Object.keys(a), ...Object.keys(b)])].sort()) output[key] = winner(a[key], b[key]);
  return output;
}

export function mergeSyncDocuments(left, right) {
  const a = validateSyncDocument(left), b = validateSyncDocument(right);
  const habits = dictionary();
  for (const id of [...new Set([...Object.keys(a.habits), ...Object.keys(b.habits)])].sort()) {
    const x = a.habits[id], y = b.habits[id];
    if (!x || !y) { habits[id] = x || y; continue; }
    const merged = { alive: winner(x.alive, y.alive), fields: mergeMap(x.fields, y.fields) };
    for (const type of [...COLLECTIONS, 'goals']) merged[type] = mergeMap(x[type], y[type]);
    habits[id] = merged;
  }
  return validateSyncDocument({ version: 1, habits });
}

export function stateFromSyncDocument(raw, preferredActiveId) {
  const doc = validateSyncDocument(raw);
  const habits = [];
  for (const [id, h] of Object.entries(doc.habits)) {
    if (!h.alive.value) continue;
    const habit = { id, ...Object.fromEntries(FIELDS.map(field => [field, h.fields[field].value])) };
    habit.history = Object.values(h.history).filter(r => !r.deleted).map(r => r.value).sort((a, b) => a.endedAt - b.endedAt || a.id.localeCompare(b.id));
    const checkinsByDate = dictionary();
    for (const item of Object.values(h.checkins).filter(c => !c.deleted)) checkinsByDate[item.value.date] = winner(checkinsByDate[item.value.date], item);
    habit.checkins = Object.values(checkinsByDate).map(c => c.value).sort((a, b) => a.at - b.at || a.id.localeCompare(b.id));
    habit.entries = Object.values(h.entries).filter(e => !e.deleted).map(e => e.value);
    // Two devices can both check in for the same day while offline. Show one
    // check-in, but retain any other note as a reflection so words aren't lost.
    for (const item of Object.values(h.checkins).filter(c => !c.deleted && c.value.note)) {
      if (checkinsByDate[item.value.date].value.id !== item.value.id) {
        const entryId = noteEntryId(item.value.id);
        if (!habit.entries.some(e => e.id === entryId)) habit.entries.push({ id: entryId, at: item.value.at, text: item.value.note });
      }
    }
    habit.entries.sort((a, b) => a.at - b.at || a.id.localeCompare(b.id));
    habit.goals = dictionary();
    for (const [key, item] of Object.entries(h.goals)) {
      const [date, index] = key.split(':');
      if (!habit.goals[date]) habit.goals[date] = [];
      if (item.value) habit.goals[date].push(Number(index));
    }
    for (const goals of Object.values(habit.goals)) goals.sort((a, b) => a - b);
    habits.push(habit);
  }
  habits.sort((a, b) => a.createdAt - b.createdAt || a.id.localeCompare(b.id));
  if (!habits.length) return null;
  if (habits.length > 50) throw new Error('The combined backup has more than 50 habits. Export a backup before resolving this conflict.');
  return validateState({ version: 1, activeId: habits.some(h => h.id === preferredActiveId) ? preferredActiveId : habits[0].id, habits });
}

export function createSyncDocument(state, deviceId, now = Date.now()) {
  return applyLocalState({ version: 1, habits: {} }, state, deviceId, now);
}

export function applyLocalState(rawDocument, rawState, deviceId, now = Date.now()) {
  if (!identifier(deviceId) || !stamp(now, Date.now() + 300000)) fail();
  const document = validateSyncDocument(rawDocument);
  const state = validateState(rawState);
  // Monotonic local revisions avoid losing two edits made in one millisecond.
  const rev = { time: Math.max(now, latestTime(document) + 1), device: deviceId };
  const projected = stateFromSyncDocument(document);
  const previous = new Map((projected?.habits || []).map(h => [h.id, h]));
  const incoming = new Map(state.habits.map(h => [h.id, h]));
  const habits = dictionary();
  for (const id of [...new Set([...Object.keys(document.habits), ...incoming.keys()])].sort()) {
    const old = document.habits[id], next = incoming.get(id), before = previous.get(id);
    if (!next) { habits[id] = old.alive.value ? { ...old, alive: { value: false, revision: rev } } : old; continue; }
    const out = { alive: old?.alive.value ? old.alive : { value: true, revision: rev }, fields: dictionary() };
    for (const field of FIELDS) out.fields[field] = old && old.fields[field].value === next[field] ? old.fields[field] : { value: next[field], revision: rev };
    for (const type of COLLECTIONS) {
      const oldItems = old?.[type] || {};
      const nextItems = new Map(next[type].map(item => [item.id, item]));
      const visibleBefore = new Set((before?.[type] || []).map(item => item.id));
      out[type] = dictionary();
      for (const key of [...new Set([...Object.keys(oldItems), ...nextItems.keys()])].sort()) {
        const item = nextItems.get(key), oldItem = oldItems[key];
        // Do not tombstone the second raw check-in merely because the app's
        // projection intentionally shows a single check-in for that day.
        if (!item) { out[type][key] = oldItem.deleted || !visibleBefore.has(key) ? oldItem : { ...oldItem, deleted: true, revision: rev }; continue; }
        out[type][key] = oldItem && !oldItem.deleted && stable(oldItem.value) === stable(item) ? oldItem : { value: item, deleted: false, revision: rev };
      }
    }
    out.goals = dictionary();
    const keys = new Set(Object.keys(old?.goals || {}));
    for (const date of Object.keys(next.goals)) for (let index = 0; index < 3; index++) keys.add(`${date}:${index}`);
    for (const key of [...keys].sort()) {
      const [date, index] = key.split(':');
      const value = (next.goals[date] || []).includes(Number(index));
      out.goals[key] = old?.goals[key]?.value === value ? old.goals[key] : { value, revision: rev };
    }
    habits[id] = out;
  }
  return validateSyncDocument({ version: 1, habits });
}
