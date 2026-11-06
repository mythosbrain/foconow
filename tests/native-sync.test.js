import test from 'node:test';
import assert from 'node:assert/strict';
import { initialState, checkIn, resetHabit, dayKey } from '../dist/model.js';
import { createSyncDocument, applyLocalState, mergeSyncDocuments, stateFromSyncDocument, validateSyncDocument } from '../dist/native-sync.js';

const now = new Date('2026-11-03T14:00:00Z').getTime();
const clone = value => JSON.parse(JSON.stringify(value));
function fixture() {
  const state = initialState(now - 86400000);
  return { state, doc: createSyncDocument(state, 'mac', now) };
}

test('sync documents round-trip state while keeping active selection local', () => {
  const { state, doc } = fixture();
  assert.deepEqual(clone(stateFromSyncDocument(doc, state.activeId)), clone(state));
  assert.equal(validateSyncDocument(clone(doc)).version, 1);
  assert.equal(stateFromSyncDocument({ version: 1, habits: {} }), null);
});

test('concurrent habit edits and journal entries merge without overwriting each other', () => {
  const { state, doc } = fixture();
  const a = clone(state), b = clone(state);
  a.habits[0].name = 'Less scrolling';
  a.habits[0].entries.push({ id: 'entry-mac', at: now, text: 'Mac reflection.' });
  b.habits[0].reason = 'More presence.';
  b.habits[0].entries.push({ id: 'entry-phone', at: now, text: 'Phone reflection.' });
  const da = applyLocalState(doc, a, 'mac', now + 1), db = applyLocalState(doc, b, 'phone', now + 1);
  const merged = mergeSyncDocuments(da, db), h = stateFromSyncDocument(merged).habits[0];
  assert.equal(h.name, 'Less scrolling');
  assert.equal(h.reason, 'More presence.');
  assert.deepEqual(h.entries.map(e => e.id).sort(), ['entry-mac', 'entry-phone']);
  assert.deepEqual(merged, mergeSyncDocuments(db, da));
  assert.deepEqual(merged, mergeSyncDocuments(merged, merged));
});

test('merge is associative and deterministically resolves equal-time edits', () => {
  const { state, doc } = fixture();
  const documents = ['alpha', 'bravo', 'charlie'].map(device => {
    const s = clone(state); s.habits[0].name = device;
    return applyLocalState(doc, s, device, now + 10);
  });
  assert.deepEqual(mergeSyncDocuments(mergeSyncDocuments(documents[0], documents[1]), documents[2]), mergeSyncDocuments(documents[0], mergeSyncDocuments(documents[1], documents[2])));
  assert.equal(stateFromSyncDocument(mergeSyncDocuments(documents[0], documents[2])).habits[0].name, 'charlie');
});

test('goals can be unchecked offline and stay unchecked after merging an older device', () => {
  const { state, doc } = fixture();
  const checked = clone(state); checked.habits[0].goals[dayKey(now)] = [1];
  const done = applyLocalState(doc, checked, 'mac', now + 1);
  const undone = stateFromSyncDocument(done); undone.habits[0].goals[dayKey(now)] = [];
  const cleared = applyLocalState(done, undone, 'phone', now + 2);
  assert.deepEqual(stateFromSyncDocument(mergeSyncDocuments(cleared, done)).habits[0].goals[dayKey(now)], []);
});

test('concurrent same-day check-ins show one check-in and preserve the other note', () => {
  const { state, doc } = fixture();
  const a = clone(state), b = clone(state);
  a.habits[0] = checkIn(a.habits[0], 'good', 'Mac note.', now);
  b.habits[0] = checkIn(b.habits[0], 'great', 'Phone note.', now);
  const da = applyLocalState(doc, a, 'mac', now + 1), db = applyLocalState(doc, b, 'phone', now + 2);
  const merged = mergeSyncDocuments(da, db), h = stateFromSyncDocument(merged).habits[0];
  assert.equal(h.checkins.length, 1);
  assert.equal(h.checkins[0].note, 'Phone note.');
  assert.equal(h.entries.length, 1);
  assert.equal(h.entries[0].text, 'Mac note.');
  const next = applyLocalState(merged, stateFromSyncDocument(merged), 'phone', now + 3);
  assert.equal(stateFromSyncDocument(next).habits[0].entries.length, 1);
  assert.equal(Object.values(next.habits[h.id].checkins).filter(c => !c.deleted).length, 2);
});

test('reset history survives another device changing the habit name', () => {
  const { state, doc } = fixture();
  const a = clone(state), b = clone(state);
  a.habits[0] = resetHabit(a.habits[0], 'Stress', 'Walk next time.', now);
  b.habits[0].name = 'Less scrolling';
  const h = stateFromSyncDocument(mergeSyncDocuments(applyLocalState(doc, a, 'phone', now + 2), applyLocalState(doc, b, 'mac', now + 1))).habits[0];
  assert.equal(h.name, 'Less scrolling'); assert.equal(h.startedAt, now); assert.equal(h.history.length, 1);
});

test('backup replacements tombstone removed habits and journal records', () => {
  const { state, doc } = fixture();
  const s = clone(state);
  s.habits[0].entries.push({ id: 'entry-to-remove', at: now, text: 'Old entry.' });
  const withEntry = applyLocalState(doc, s, 'mac', now + 1);
  const replacement = clone(s); replacement.habits[0].entries = [];
  const removed = applyLocalState(withEntry, replacement, 'phone', now + 2);
  assert.equal(stateFromSyncDocument(mergeSyncDocuments(removed, withEntry)).habits[0].entries.length, 0);
  const newState = initialState(now);
  const replaced = applyLocalState(removed, newState, 'phone', now + 3);
  const result = stateFromSyncDocument(mergeSyncDocuments(replaced, withEntry));
  assert.equal(result.habits.length, 1); assert.equal(result.habits[0].id, newState.habits[0].id);
});

test('ordinary offline edits cannot accidentally resurrect a deleted habit', () => {
  const { state, doc } = fixture();
  const replacement = initialState(now);
  const removed = applyLocalState(doc, replacement, 'phone', now + 10);
  const stale = clone(state); stale.habits[0].name = 'Old device edit';
  const edited = applyLocalState(doc, stale, 'mac', now + 20);
  assert.equal(stateFromSyncDocument(mergeSyncDocuments(removed, edited)).habits.length, 1);
});

test('multiple local edits in the same millisecond preserve their order', () => {
  const { state, doc } = fixture();
  const a = clone(state); a.habits[0].name = 'First';
  const first = applyLocalState(doc, a, 'mac', now);
  a.habits[0].name = 'Second';
  const second = applyLocalState(first, a, 'mac', now);
  assert.equal(stateFromSyncDocument(mergeSyncDocuments(first, second)).habits[0].name, 'Second');
});

test('remote validation rejects malformed data, oversized payloads, and poisoned keys', () => {
  const { doc } = fixture(); const id = Object.keys(doc.habits)[0];
  for (const mutate of [
    d => d.version = 9,
    d => d.habits[id].fields.name.value = '',
    d => d.habits[id].fields.reason.revision.time = Date.now() + 86400000,
    d => d.habits[id].goals['2026-02-31:1'] = { value: true, revision: { time: now, device: 'mac' } },
    d => d.habits[id].entries.bad = { value: {}, revision: { time: now, device: 'mac' }, deleted: false },
    d => Object.defineProperty(d.habits, '__proto__', { value: d.habits[id], enumerable: true }),
    d => d.habits[id].fields.reason.value = 'x'.repeat(11 * 1024 * 1024),
  ]) { const d = clone(doc); mutate(d); assert.throws(() => validateSyncDocument(d)); }
});
