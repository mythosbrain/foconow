import test from 'node:test';
import assert from 'node:assert/strict';
import { taskWorkload } from '../dist/insights.js';
const now = 1800000000000;
const tasks = [
  {id:'copy-a',originId:'a',title:'Draft',estimate:2,done:false,priority:false},
  {id:'b',originId:'b',title:'Review',estimate:1,done:false,priority:true},
  {id:'c',originId:'c',title:'Done',estimate:4,done:true,priority:true}
];
test('workload follows carried task origins and removes completed tasks from remaining estimates', () => {
  const timer = {settings:{work:25},focusSpans:[{taskId:'a',start:now-3600000,end:now-3000000}],sessions:[{taskId:'a',endedAt:now-3000000,seconds:600,tracked:true}]};
  const result = taskWorkload(timer,tasks,now);
  assert.equal(result.seconds,3900);
  assert.equal(result.open,2);
  assert.equal(result.priorities,1);
  assert.equal(result.next.id,'b');
  assert.equal(tasks[0].seconds,undefined);
});
test('live focus reduces estimates while pauses and breaks do not add time', () => {
  const timer = {settings:{work:25},phase:'work',status:'running',taskId:'b',focusStartedAt:now-600000,endsAt:now+900000};
  assert.equal(taskWorkload(timer,tasks,now).seconds,3900);
  assert.equal(taskWorkload({...timer,phase:'short'},tasks,now).seconds,4500);
  assert.equal(taskWorkload({...timer,status:'paused'},tasks,now).seconds,4500);
});
test('overruns stay at zero and unfinished tasks remain available, including legacy sessions', () => {
  const timer = {sessions:[{taskId:'b',endedAt:now,seconds:1800}]};
  const result = taskWorkload(timer,tasks,now);
  assert.equal(result.seconds,3000);
  assert.equal(result.overEstimate,1);
  assert.equal(result.next.id,'b');
  assert.equal(taskWorkload(timer,tasks.map(t=>({...t,done:true})),now).next,null);
  assert.equal(taskWorkload(timer,[],now).seconds,0);
});
test('changed session duration changes estimates and ordinary tasks retain their list order', () => {
  const result = taskWorkload({settings:{work:45}},tasks.map(t=>({...t,priority:false})),now);
  assert.equal(result.seconds,8100);
  assert.equal(result.next.id,'copy-a');
});
