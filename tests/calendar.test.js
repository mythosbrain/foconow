import test from 'node:test';
import assert from 'node:assert/strict';
import { calendarMonth } from '../dist/model.js';

test('calendar includes leap day, Monday-first padding, and whole weeks', () => {
  const cells = calendarMonth(2024, 1, new Date(2024, 1, 29, 15).getTime());
  assert.equal(cells[0].date, '2024-01-29');
  assert.equal(cells.length % 7, 0);
  assert.equal(cells.filter(c => c.inMonth).length, 29);
  assert.equal(cells.find(c => c.today).date, '2024-02-29');
  assert.equal(cells.find(c => c.date === '2024-03-01').future, true);
});

test('calendar handles year boundaries without duplicate or missing dates', () => {
  const cells = calendarMonth(2026, 11, new Date(2026, 11, 31, 23).getTime());
  assert.equal(cells.find(c => c.inMonth).date, '2026-12-01');
  assert.equal(cells.filter(c => c.inMonth).at(-1).date, '2026-12-31');
  assert.equal(new Set(cells.map(c => c.date)).size, cells.length);
  assert.equal(cells.at(-1).date, '2027-01-03');
});

test('calendar dates remain consecutive across local clock changes', () => {
  const previous = process.env.TZ;
  process.env.TZ = 'America/New_York';
  try {
    const cells = calendarMonth(2026, 2, new Date(2026, 2, 31).getTime());
    assert.equal(cells.filter(c => c.inMonth).length, 31);
    assert.deepEqual(cells.filter(c => c.inMonth).map(c => c.day), Array.from({ length: 31 }, (_, i) => i + 1));
    assert.equal(cells.find(c => c.date === '2026-03-08').future, false);
  } finally {
    if (previous === undefined) delete process.env.TZ; else process.env.TZ = previous;
  }
});
