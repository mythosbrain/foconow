import test from 'node:test';
import assert from 'node:assert/strict';
import { initialState, createHabit, dayPlan, updateDayPlan, addDayTask, bringTasksForward, validateState } from '../dist/model.js';
const now = new Date(2026,10,4,18).getTime();
const today = '2026-11-04', yesterday = '2026-11-03';

test('legacy backups gain an empty daily planner without changing habit history', () => {
  const old = initialState(now); delete old.planner;
  const clean = validateState(old,now);
  assert.deepEqual(clean.planner, {});
  assert.deepEqual(JSON.parse(JSON.stringify(clean.habits)), old.habits);
  assert.deepEqual(dayPlan(clean,today), {focus:'',tasks:[],summary:'',summarySavedAt:0});
});
test('daily tasks and summaries are shared across habits and survive backups', () => {
  let state = addDayTask(initialState(now),today,'  Finish my project  ',true);
  state = updateDayPlan(state,today,{focus:'One good thing',summary:'A full day.',summarySavedAt:now});
  const second = createHabit('Another habit','',now,now);
  state = {...state, activeId:second.id, habits:[...state.habits,second]};
  const clean = validateState(JSON.parse(JSON.stringify(state)),now);
  assert.equal(dayPlan(clean,today).tasks[0].title,'Finish my project');
  assert.equal(dayPlan(clean,today).tasks[0].priority,true);
  assert.equal(dayPlan(clean,today).summary,'A full day.');
  assert.equal(dayPlan(clean,today).summarySavedAt,now);
});
test('task completion and summary draft edits preserve other dates', () => {
  let state = addDayTask(initialState(now),yesterday,'Yesterday task');
  state = addDayTask(state,today,'Today task');
  const before = JSON.stringify(dayPlan(state,yesterday));
  const plan = dayPlan(state,today);
  state = updateDayPlan(state,today,{tasks:plan.tasks.map(t=>({...t,done:true})),summary:'A draft',summarySavedAt:0});
  assert.equal(dayPlan(validateState(state,now),today).tasks[0].done,true);
  assert.equal(JSON.stringify(dayPlan(state,yesterday)),before);
});
test('bringing tasks forward retains history, skips completed tasks, and cannot duplicate a chain', () => {
  let state = addDayTask(initialState(now),yesterday,'Keep going');
  state = addDayTask(state,yesterday,'Already done');
  const old = dayPlan(state,yesterday);
  state = updateDayPlan(state,yesterday,{tasks:old.tasks.map((t,i)=>({...t,done:i===1}))});
  state = bringTasksForward(state,yesterday,today,old.tasks.map(t=>t.id));
  const copied = dayPlan(state,today).tasks[0];
  assert.equal(dayPlan(state,today).tasks.length,1);
  assert.notEqual(copied.id,old.tasks[0].id);
  assert.equal(copied.originId,old.tasks[0].originId);
  assert.equal(dayPlan(state,yesterday).tasks.length,2);
  state = bringTasksForward(state,yesterday,today,[old.tasks[0].id]);
  assert.equal(dayPlan(state,today).tasks.length,1);
  assert.throws(()=>bringTasksForward(state,today,yesterday,[copied.id]));
});
test('planner backup validation rejects broken dates, duplicate tasks, oversized text, and invalid review stamps', () => {
  for (const mutate of [
    s=>s.planner['2026-02-31']=dayPlan(s,today),
    s=>s.planner[today].tasks[0].done='yes',
    s=>s.planner[today].tasks[0].priority=1,
    s=>s.planner[today].tasks[0].title='',
    s=>s.planner[today].tasks.push(s.planner[today].tasks[0]),
    s=>s.planner[today].summary='x'.repeat(20001),
    s=>s.planner[today].summarySavedAt=now+1,
    s=>s.planner[today].summarySavedAt=now,
    s=>s.planner[today].focus='x'.repeat(241),
    s=>s.planner=[]
  ]) { const state=addDayTask(initialState(now),today,'Task');mutate(state);assert.throws(()=>validateState(state,now)); }
});
test('task limits apply both when adding and when bringing work forward', () => {
  let state = initialState(now);
  for (let i=0;i<100;i++) state=addDayTask(state,today,`Task ${i}`);
  assert.throws(()=>addDayTask(state,today,'One too many'));
  assert.throws(()=>addDayTask(state,yesterday,' '));
  state=addDayTask(state,yesterday,'Other task');
  assert.throws(()=>bringTasksForward(state,yesterday,today,[dayPlan(state,yesterday).tasks[0].id]));
});
test('planner dates remain recorded dates across time zones and unknown fields are stripped', () => {
  const state=addDayTask(initialState(now),today,'Local task');
  state.planner[today].extra='ignore'; state.planner[today].tasks[0].extra='ignore';
  const clean=validateState(JSON.parse(JSON.stringify(state)),now);
  assert.deepEqual(Object.keys(clean.planner),[today]);
  assert.equal('extra' in clean.planner[today],false);
  assert.equal('extra' in clean.planner[today].tasks[0],false);
});

test('task notes and focus estimates migrate safely and survive carry-forward and backups', () => {
  let state = addDayTask(initialState(now),yesterday,'Prepare the proposal');
  const plan = dayPlan(state,yesterday);
  state = updateDayPlan(state,yesterday,{tasks:plan.tasks.map(t=>({...t,notes:'Draft the outline first.',estimate:3}))});
  state = bringTasksForward(state,yesterday,today,[plan.tasks[0].id]);
  const clean = validateState(JSON.parse(JSON.stringify(state)),now);
  assert.equal(dayPlan(clean,today).tasks[0].notes,'Draft the outline first.');
  assert.equal(dayPlan(clean,today).tasks[0].estimate,3);
  delete state.planner[yesterday].tasks[0].notes; delete state.planner[yesterday].tasks[0].estimate;
  const migrated = validateState(state,now);
  assert.equal(dayPlan(migrated,yesterday).tasks[0].notes,'');
  assert.equal(dayPlan(migrated,yesterday).tasks[0].estimate,1);
  for (const patch of [{estimate:0},{estimate:1.5},{estimate:13},{notes:'x'.repeat(2001)}]) {
    const invalid=structuredClone(state);Object.assign(invalid.planner[today].tasks[0],patch);assert.throws(()=>validateState(invalid,now));
  }
});
