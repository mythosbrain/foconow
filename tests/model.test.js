import test from 'node:test';
import assert from 'node:assert/strict';
import { DAY, dayKey, createHabit, initialState, elapsed, stats, checkIn, resetHabit, validateState } from '../dist/model.js';

const now = new Date('2026-11-03T15:00:00Z').getTime();
test('a new habit starts at zero without fabricated history', () => {
  const h = initialState(now).habits[0];
  assert.deepEqual(elapsed(h, now), { total: 0, days: 0, hours: 0, minutes: 0, seconds: 0 });
  assert.equal(h.history.length, 0);
  assert.equal(h.checkins.length, 0);
});
test('counter counts complete days and keeps the remainder accurate', () => {
  const h = createHabit('Scrolling', '', now - DAY * 3 - 3661000, now);
  assert.deepEqual(elapsed(h, now), { total: DAY * 3 + 3661000, days: 3, hours: 1, minutes: 1, seconds: 1 });
  assert.equal(elapsed(h, h.startedAt - 1).total, 0);
});
test('daily check-in is idempotent and uses the local calendar day', () => {
  const h = createHabit('Scrolling', '', now, now);
  const checked = checkIn(h, 'good', '  Went for a walk.  ', now);
  assert.equal(checked.checkins[0].date, dayKey(now));
  assert.equal(checked.checkins[0].note, 'Went for a walk.');
  assert.equal(checkIn(checked, 'great', 'Duplicate', now + 1000).checkins.length, 1);
  assert.equal(checkIn(checked, 'okay', '', now + DAY).checkins.length, 2);
});
test('reset preserves a completed streak, check-ins, and journal entries', () => {
  const h = checkIn(createHabit('Scrolling', '', now - 8 * DAY, now - 8 * DAY), 'good', '', now);
  h.entries.push({ id: 'entry-1', at: now, text: 'Keep going.' });
  const reset = resetHabit(h, 'Stress', '  Try a walk.  ', now);
  assert.equal(reset.startedAt, now);
  assert.equal(reset.history.length, 1);
  assert.equal(reset.history[0].startedAt, now - 8 * DAY);
  assert.equal(reset.history[0].note, 'Try a walk.');
  assert.equal(reset.checkins.length, 1);
  assert.equal(reset.entries.length, 1);
  assert.deepEqual(stats(reset, now + DAY), { bestDays: 8, currentDays: 1, resets: 1, checkins: 1 });
  assert.throws(() => resetHabit(h, '', '', h.startedAt - 1));
});
test('a valid backup survives a JSON round trip', () => {
  const data = initialState(now);
  data.habits[0] = resetHabit(checkIn(data.habits[0], 'okay', 'A note', now), 'Stress', 'Try again', now);
  data.habits[0].goals[dayKey(now)] = [0, 2];
  assert.equal(JSON.stringify(validateState(JSON.parse(JSON.stringify(data)), now)), JSON.stringify(data));
});
test('malformed, future-dated, and duplicate backups are rejected', () => {
  for (const mutate of [
    d => d.habits[0].startedAt = now + DAY,
    d => d.habits[0].name = '',
    d => d.habits[0].history.push({}),
    d => d.habits[0].goals[dayKey(now)] = [0, 5],
    d => d.habits[0].goals['2026-02-31'] = [0],
    d => d.habits.push(d.habits[0]),
    d => d.activeId = 'missing',
    d => d.habits[0].checkins.push({ id: '1', at: now, date: dayKey(now), mood: 'invalid', note: '' }),
  ]) {
    const d = initialState(now); mutate(d); assert.throws(() => validateState(d, now));
  }
});
test('backups cannot inject unrecognized state properties', () => {
  const d = initialState(now); d.extra = true; d.habits[0].extra = true;
  const clean = validateState(d, now);
  assert.equal('extra' in clean, false);
  assert.equal('extra' in clean.habits[0], false);
});
test('recorded local check-in dates survive moving to a different timezone', () => {
  const d = initialState(now);
  d.habits[0] = checkIn(d.habits[0], 'good', '', now);
  d.habits[0].checkins[0].date = '2026-11-02';
  assert.equal(validateState(d, now).habits[0].checkins[0].date, '2026-11-02');
});
