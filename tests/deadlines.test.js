import test from 'node:test';
import assert from 'node:assert/strict';
import {initialState,addDayTask,bringTasksForward,dayPlan,validateState,deadlineStatus,validDeadline} from '../dist/model.js';
const now=new Date(2026,10,13,12,0).getTime();
test('deadlines survive backup validation and carrying a task forward',()=>{
 let state=addDayTask(initialState(now),'2026-11-12','Finish a draft',false,'2026-11-13','17:00');
 const first=dayPlan(state,'2026-11-12').tasks[0];first.remindAtDeadline=true;
 state=bringTasksForward(state,'2026-11-12','2026-11-13',[first.id]);
 const task=dayPlan(validateState(JSON.parse(JSON.stringify(state)),now),'2026-11-13').tasks[0];
 assert.equal(task.dueDate,'2026-11-13');assert.equal(task.dueTime,'17:00');assert.equal(task.remindAtDeadline,true);assert.equal(task.originId,first.originId);
});
test('date-only deadlines last through their calendar day; timed deadlines expire at their local time',()=>{
 assert.equal(deadlineStatus({dueDate:'2026-11-13'},now),'today');
 assert.equal(deadlineStatus({dueDate:'2026-11-13',dueTime:'11:59'},now),'overdue');
 assert.equal(deadlineStatus({dueDate:'2026-11-14'},now),'upcoming');
 assert.equal(deadlineStatus({dueDate:'2026-11-12',done:true},now),'');
});
test('legacy tasks get no deadline and corrupt or impossible deadlines are rejected',()=>{
 let state=addDayTask(initialState(now),'2026-11-13','Task');let task=state.planner['2026-11-13'].tasks[0];
 delete task.dueDate;delete task.dueTime;delete task.remindAtDeadline;
 assert.equal(validateState(state,now).planner['2026-11-13'].tasks[0].dueDate,'');
 for(const [date,time] of [['2026-02-30',''],['bad','12:00'],['','12:00'],['2026-11-13','24:00']]){
 assert.equal(validDeadline(date,time),false);assert.throws(()=>validateState({...state,planner:{'2026-11-13':{...state.planner['2026-11-13'],tasks:[{...task,dueDate:date,dueTime:time}]}}},now));
 }
 assert.equal(validDeadline('2028-02-29',''),true);assert.equal(validDeadline('2027-02-29',''),false);
 task.remindAtDeadline=true;assert.throws(()=>validateState(state,now));
});

test('deadline types must be strings',()=>{ assert.equal(validDeadline(0,''),false); assert.equal(validDeadline('',false),false); });
