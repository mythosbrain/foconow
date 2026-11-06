import test from 'node:test';
import assert from 'node:assert/strict';
import { focusIntervals, focusReport, focusDuration } from '../dist/insights.js';

test('focus includes live and interrupted stretches exactly once, excludes pauses and breaks',()=>{
  const now=+new Date('2026-11-04T12:00:00');
  const timer={focusSpans:[{start:now-3600000,end:now-3000000,taskId:'a',taskTitle:'Write'}],sessions:[{endedAt:now-3000000,seconds:600,tracked:true}],phase:'work',status:'running',focusStartedAt:now-300000,endsAt:now+1200000,remaining:1200};
  const report=focusReport(timer,{},7,now);
  assert.equal(report.seconds,900);
  assert.equal(report.days.at(-1).hours[11],900);
  assert.equal(report.sessions,1);
  assert.equal(focusReport({...timer,phase:'short'}, {},7,now).seconds,600);
  assert.equal(focusReport({...timer,status:'paused'}, {},7,now).seconds,600);
});
test('local midnight splits focus into the right days and hours',()=>{
  const now=+new Date('2026-11-04T12:00:00');
  const report=focusReport({focusSpans:[{start:+new Date('2026-11-03T23:40:00'),end:+new Date('2026-11-04T00:20:00'),taskId:'a'}]}, {},7,now);
  assert.equal(report.days.at(-2).seconds,1200); assert.equal(report.days.at(-1).seconds,1200);
  assert.equal(report.days.at(-2).hours[23],1200); assert.equal(report.days.at(-1).hours[0],1200);
  assert.equal(report.byTask[0].seconds,2400);
});
test('legacy completed sessions remain, new tracked sessions never double count',()=>{
  const now=+new Date('2026-11-04T12:00:00');
  const timer={sessions:[{endedAt:now-3600000,seconds:1500},{endedAt:now,seconds:600,tracked:true}],focusSpans:[{start:now-600000,end:now}]};
  assert.equal(focusReport(timer,{},7,now).seconds,2100);
  assert.equal(focusIntervals(timer,now).filter(s=>s.legacy).length,1);
});
test('30 day report compares equal windows, excludes future time and totals task progress',()=>{
  const now=+new Date('2026-11-04T12:00:00');
  const timer={focusSpans:[{start:now-100000,end:now+100000},{start:now-35*86400000,end:now-35*86400000+600000}]};
  const report=focusReport(timer,{'2026-11-04':{tasks:[{done:true},{done:false}]}},30,now);
  assert.equal(report.days.length,30); assert.equal(report.seconds,100); assert.equal(report.previousSeconds,600);
  assert.equal(report.done,1); assert.equal(report.tasks,2); assert.equal(report.activeDays,1);
  assert.equal(focusDuration(7560),'2h 06m'); assert.equal(focusDuration(12),'<1m'); assert.equal(focusDuration(12,true),'12s');
});
test('daylight saving transitions preserve elapsed seconds in hourly bins',()=>{
  const prior=process.env.TZ;
  process.env.TZ='America/New_York';
  try {
    for (const [start,end] of [['2026-03-08T00:30:00-05:00','2026-03-08T04:30:00-04:00'],['2026-11-01T00:30:00-04:00','2026-11-01T03:30:00-05:00']]) {
      const report=focusReport({focusSpans:[{start:+new Date(start),end:+new Date(end)}]}, {},7,+new Date(end));
      assert.equal(report.seconds,(+new Date(end)-new Date(start))/1000);
      assert.equal(report.days.at(-1).hours.reduce((a,b)=>a+b,0),report.seconds);
    }
  } finally { if(prior===undefined) delete process.env.TZ; else process.env.TZ=prior; }
});
