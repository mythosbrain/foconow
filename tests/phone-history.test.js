import test from 'node:test';
import assert from 'node:assert/strict';
import { phonePeriod } from '../dist/phone-history.js';
test('phone periods sum Settings totals independently of partial app lists and deduplicate refreshed days',()=>{
  const reports=[{deviceName:'iPhone',date:'2026-11-04',totalSeconds:773*60,capturedAt:2,apps:[{name:'A',seconds:120}]},{deviceName:'iPhone',date:'2026-11-04',totalSeconds:760*60,capturedAt:1,apps:[]},{deviceName:'iPhone',date:'2026-11-03',totalSeconds:820*60,capturedAt:1,apps:[{name:'A',seconds:60}]},{deviceName:'Mac',date:'2026-11-04',totalSeconds:10000,capturedAt:3,apps:[]}];
  const result=phonePeriod(reports,'iPhone',7,+new Date('2026-11-04T12:00:00'));
  assert.equal(result.totalSeconds,(773+820)*60);assert.equal(result.available,2);assert.equal(result.apps[0].seconds,180);assert.equal(result.days.length,7);
  assert.equal(result.days[0].missing,true);assert.equal(result.days[0].totalSeconds,null);
});
test('monthly phone periods retain recorded zero days and handle calendar boundaries',()=>{
  const result=phonePeriod([{deviceName:'iPhone',date:'2027-01-01',totalSeconds:0,capturedAt:1,apps:[]}],'iPhone',30,+new Date('2027-01-01T12:00:00'));
  assert.equal(result.days[0].date,'2026-12-03');assert.equal(result.days.at(-1).date,'2027-01-01');assert.equal(result.days.at(-1).missing,false);assert.equal(result.available,1);
});
