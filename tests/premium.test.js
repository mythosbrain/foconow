import test from 'node:test';
import assert from 'node:assert/strict';
import { DAY, DEFAULT_INTENTIONS, initialState, checkIn, resetHabit, logUrge, weeklyReview, validateState, dayKey } from '../dist/model.js';
const now = new Date(2026, 10, 4, 12).getTime();
test('existing version-one backups gain optional features without losing records', () => {
  const data = initialState(now - 4 * DAY);
  data.habits[0] = resetHabit(checkIn(data.habits[0], 'good', 'A legacy note.', now - DAY), 'Stress', 'Start again.', now);
  const h = data.habits[0];
  for (const key of ['intentionLabels','targetDays','replacement','urges']) delete h[key];
  const old = JSON.parse(JSON.stringify(h));
  const restored = validateState(data, now).habits[0];
  for (const key of ['id','startedAt','history','checkins','entries','goals']) assert.deepEqual(JSON.parse(JSON.stringify(restored[key])), old[key]);
  assert.deepEqual(restored.intentionLabels, DEFAULT_INTENTIONS);
  assert.equal(restored.targetDays, 30);
  assert.deepEqual(restored.urges, []);
});
test('an urge is independent of streak resets and survives backup restoration', () => {
  const data = initialState(now - 3 * DAY), start = data.habits[0].startedAt;
  data.habits[0] = logUrge(data.habits[0], 4, 'Stress', '  Took a walk.  ', 'passed', now);
  assert.equal(data.habits[0].startedAt, start);
  assert.equal(data.habits[0].history.length, 0);
  const h = validateState(JSON.parse(JSON.stringify(data)), now).habits[0];
  assert.equal(h.urges[0].note, 'Took a walk.');
  assert.equal(h.urges[0].outcome, 'passed');
  assert.throws(() => logUrge(h, 6));
});
test('custom intentions and plans survive backups and preserve completion indices', () => {
  const data = initialState(now);
  Object.assign(data.habits[0], { intentionLabels: ['Walk outside','Read 10 pages','Put my phone away'], targetDays: 45, replacement: 'Go outside.', goals: {[dayKey(now)]: [0,2]} });
  const h = validateState(JSON.parse(JSON.stringify(data)), now).habits[0];
  assert.equal(h.targetDays, 45); assert.equal(h.replacement, 'Go outside.');
  assert.deepEqual(h.intentionLabels, data.habits[0].intentionLabels);
  assert.deepEqual(h.goals[dayKey(now)], [0,2]);
});
test('weekly review includes only the current seven local calendar days', () => {
  let h = initialState(now - 10 * DAY).habits[0];
  h = checkIn(h, 'good', '', now - 8 * DAY);
  h = checkIn(h, 'good', '', now);
  h = logUrge(h, 3, '', '', 'passed', now);
  h = logUrge(h, 3, '', '', 'noted', now);
  h.goals[dayKey(now)] = [0,1,2];
  h.goals[dayKey(now - 8 * DAY)] = [0,1,2];
  const r = weeklyReview(h, now);
  assert.equal(new Set(r.dates).size, 7);
  assert.equal(r.checkins, 1); assert.equal(r.urges, 2); assert.equal(r.passed, 1); assert.equal(r.intentions, 3);
});
test('new backup fields reject malformed, duplicate, and oversized values', () => {
  for (const mutate of [h=>h.targetDays=0, h=>h.targetDays=1.5, h=>h.intentionLabels=['Only one'], h=>h.intentionLabels=['','a','b'], h=>h.replacement='x'.repeat(301), h=>h.urges=[{id:'1',at:now,intensity:7,trigger:'',note:'',outcome:'passed'}], h=>h.urges=[{id:'1',at:now,intensity:3,trigger:'',note:'',outcome:'passed'},{id:'1',at:now,intensity:3,trigger:'',note:'',outcome:'passed'}]]) {
    const data=initialState(now); mutate(data.habits[0]); assert.throws(()=>validateState(data,now));
  }
});
