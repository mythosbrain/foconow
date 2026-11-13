export const DAY = 86400000;
export const MILESTONES = [1, 3, 7, 14, 30, 60, 90];
export const DEFAULT_INTENTIONS = ['Move your body for 10 minutes', 'Take a mindful break', 'Step away from a trigger'];
export const uid = () => globalThis.crypto.randomUUID();
export function dayKey(value = Date.now()) {
  const d = new Date(value);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
export function createHabit(name = 'My habit', reason = '', startedAt = Date.now(), now = Date.now()) {
  return { id: uid(), name, reason, startedAt, createdAt: now, history: [], checkins: [], entries: [], goals: {}, intentionLabels: [...DEFAULT_INTENTIONS], targetDays: 30, replacement: '', urges: [] };
}
export function initialState(now = Date.now()) {
  const habit = createHabit('My habit', '', now, now);
  return { version: 1, activeId: habit.id, habits: [habit], planner: {} };
}
export function dayPlan(state, date = dayKey()) {
  return state.planner?.[date] || { focus: '', tasks: [], summary: '', summarySavedAt: 0 };
}
export function updateDayPlan(state, date, patch) {
  return { ...state, planner: { ...(state.planner || {}), [date]: { ...dayPlan(state, date), ...patch } } };
}
export function addDayTask(state, date, title, priority = false, dueDate = '', dueTime = '') {
  if (!validDeadline(dueDate, dueTime)) throw new Error('Choose a valid deadline. A time needs a date.');
  const plan = dayPlan(state, date), text = title.trim();
  if (!text || text.length > 240 || plan.tasks.length >= 100) throw new Error('Add a task of up to 240 characters. Each day holds up to 100 tasks.');
  const id = uid();
  return updateDayPlan(state, date, { tasks: [...plan.tasks, { id, originId: id, title: text, done: false, priority: !!priority, notes: '', estimate: 1, dueDate, dueTime, remindAtDeadline: false }] });
}
export function validDeadline(date = '', time = '') {
  if (typeof date !== 'string' || typeof time !== 'string') return false;
  if (!date) return time === '';
  if (typeof date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(date) || dayKey(new Date(`${date}T12:00:00`)) !== date) return false;
  if (time === '') return true;
  if (typeof time !== 'string' || !/^([01]\d|2[0-3]):[0-5]\d$/.test(time)) return false;
  const local = new Date(`${date}T${time}:00`);
  return dayKey(local) === date && local.getHours() === Number(time.slice(0,2)) && local.getMinutes() === Number(time.slice(3));
}
export function deadlineStatus(task, now = Date.now()) {
  if (!task.dueDate || task.done) return '';
  const today = dayKey(now);
  if (task.dueDate < today || (task.dueTime && new Date(`${task.dueDate}T${task.dueTime}:00`).getTime() < now)) return 'overdue';
  return task.dueDate === today ? 'today' : 'upcoming';
}
export function bringTasksForward(state, source, destination, selectedIds) {
  if (source >= destination) throw new Error('Choose an earlier day to bring tasks from.');
  const plan = dayPlan(state, destination);
  const origins = new Set(plan.tasks.map(t => t.originId));
  const tasks = dayPlan(state, source).tasks.filter(t => !t.done && selectedIds.includes(t.id) && !origins.has(t.originId));
  if (plan.tasks.length + tasks.length > 100) throw new Error('Keep each day to 100 tasks or fewer.');
  return updateDayPlan(state, destination, { tasks: [...plan.tasks, ...tasks.map(t => ({ ...t, id: uid(), done: false }))] });
}
export function elapsed(habit, now = Date.now()) {
  const total = Math.max(0, now - habit.startedAt);
  return { total, days: Math.floor(total / DAY), hours: Math.floor(total / 3600000) % 24, minutes: Math.floor(total / 60000) % 60, seconds: Math.floor(total / 1000) % 60 };
}
export function stats(habit, now = Date.now()) {
  const current = elapsed(habit, now).total;
  const best = Math.max(current, ...habit.history.map(run => run.endedAt - run.startedAt));
  return { bestDays: Math.floor(best / DAY), currentDays: Math.floor(current / DAY), resets: habit.history.length, checkins: habit.checkins.length };
}
export function checkIn(habit, mood, note = '', now = Date.now()) {
  const date = dayKey(now);
  if (habit.checkins.some(c => c.date === date)) return habit;
  return { ...habit, checkins: [...habit.checkins, { id: uid(), date, at: now, mood, note: note.trim() }] };
}
export function resetHabit(habit, trigger = '', note = '', now = Date.now()) {
  if (now < habit.startedAt) throw new Error('Reset time cannot be before the streak start.');
  return { ...habit, startedAt: now, history: [...habit.history, { id: uid(), startedAt: habit.startedAt, endedAt: now, trigger, note: note.trim() }] };
}
export function logUrge(habit, intensity, trigger = '', note = '', outcome = 'noted', now = Date.now()) {
  if (!Number.isInteger(intensity) || intensity < 1 || intensity > 5 || !['noted', 'passed'].includes(outcome)) throw new Error('Choose a valid intensity and outcome.');
  return { ...habit, urges: [...(habit.urges || []), { id: uid(), at: now, intensity, trigger: trigger.trim().slice(0,100), note: note.trim().slice(0,12000), outcome }] };
}
export function weeklyReview(habit, now = Date.now()) {
  const dates = Array.from({ length: 7 }, (_, i) => { const d = new Date(now); d.setDate(d.getDate() - 6 + i); return dayKey(d); });
  const checkins = habit.checkins.filter(c => dates.includes(c.date));
  const urges = (habit.urges || []).filter(u => dates.includes(dayKey(u.at)));
  const intentions = dates.reduce((n, date) => n + (habit.goals[date]?.length || 0), 0);
  return { dates, checkins: checkins.length, urges: urges.length, passed: urges.filter(u => u.outcome === 'passed').length, intentions };
}
// Local calendar dates, built at noon so a daylight-saving change cannot shift a day.
export function calendarMonth(year, month, now = Date.now()) {
  const first = new Date(year, month, 1, 12);
  const offset = (first.getDay() + 6) % 7;
  const count = new Date(year, month + 1, 0, 12).getDate();
  const today = dayKey(now);
  return Array.from({ length: Math.ceil((offset + count) / 7) * 7 }, (_, i) => {
    const date = new Date(year, month, i - offset + 1, 12);
    const key = dayKey(date);
    return { date: key, day: date.getDate(), inMonth: date.getMonth() === month, today: key === today, future: key > today };
  });
}
export function activeHabit(state) {
  return state.habits.find(h => h.id === state.activeId) || state.habits[0];
}
export function replaceHabit(state, habit) {
  return { ...state, habits: state.habits.map(h => h.id === habit.id ? habit : h) };
}
// Parse backups into a new object; only explicitly supported fields reach the app.
export function validateState(raw, now = Date.now()) {
  const fail = () => { throw new Error('This file is not a valid backup.'); };
  const str = (s, max = 12000) => typeof s === 'string' && s.length <= max;
  const stamp = n => Number.isFinite(n) && n >= 0 && n <= now;
  const id = s => str(s, 100) && s.length > 0;
  const date = s => str(s, 10) && /^\d{4}-\d{2}-\d{2}$/.test(s) && dayKey(new Date(`${s}T12:00:00`)) === s;
  const moods = ['great', 'good', 'okay', 'low', 'tough'];
  if (!raw || raw.version !== 1 || !Array.isArray(raw.habits) || !raw.habits.length || raw.habits.length > 50) fail();
  const habits = raw.habits.map(h => {
    if (!h || !id(h.id) || !str(h.name, 60) || !h.name.trim() || !str(h.reason, 500) || !stamp(h.startedAt) || !stamp(h.createdAt) || !Array.isArray(h.history) || !Array.isArray(h.checkins) || !Array.isArray(h.entries) || !h.goals || typeof h.goals !== 'object' || Array.isArray(h.goals)) fail();
    if ([h.history, h.checkins, h.entries].some(list => list.length > 20000)) fail();
    const history = h.history.map(r => {
      if (!r || !id(r.id) || !stamp(r.startedAt) || !stamp(r.endedAt) || r.endedAt < r.startedAt || !str(r.trigger, 100) || !str(r.note)) fail();
      return { id: r.id, startedAt: r.startedAt, endedAt: r.endedAt, trigger: r.trigger, note: r.note };
    });
    const checkins = h.checkins.map(c => {
      if (!c || !id(c.id) || !date(c.date) || !stamp(c.at) || !moods.includes(c.mood) || !str(c.note)) fail();
      return { id: c.id, date: c.date, at: c.at, mood: c.mood, note: c.note };
    });
    if (new Set(checkins.map(c => c.date)).size !== checkins.length) fail();
    const entries = h.entries.map(e => {
      if (!e || !id(e.id) || !stamp(e.at) || !str(e.text) || !e.text.trim()) fail();
      return { id: e.id, at: e.at, text: e.text };
    });
    const goals = Object.create(null);
    for (const [key, value] of Object.entries(h.goals)) {
      if (!date(key) || !Array.isArray(value) || value.length > 3 || value.some(n => !Number.isInteger(n) || n < 0 || n > 2) || new Set(value).size !== value.length) fail();
      goals[key] = [...value];
    }
    const intentionLabels = h.intentionLabels === undefined ? [...DEFAULT_INTENTIONS] : h.intentionLabels;
    const targetDays = h.targetDays === undefined ? 30 : h.targetDays;
    const replacement = h.replacement === undefined ? '' : h.replacement;
    const rawUrges = h.urges === undefined ? [] : h.urges;
    if (!Array.isArray(intentionLabels) || intentionLabels.length !== 3 || intentionLabels.some(s => !str(s, 80) || !s.trim()) || !Number.isInteger(targetDays) || targetDays < 1 || targetDays > 3650 || !str(replacement, 300) || !Array.isArray(rawUrges) || rawUrges.length > 20000) fail();
    const urges = rawUrges.map(u => {
      if (!u || !id(u.id) || !stamp(u.at) || !Number.isInteger(u.intensity) || u.intensity < 1 || u.intensity > 5 || !str(u.trigger, 100) || !str(u.note) || !['noted', 'passed'].includes(u.outcome)) fail();
      return { id: u.id, at: u.at, intensity: u.intensity, trigger: u.trigger, note: u.note, outcome: u.outcome };
    });
    if (new Set(urges.map(u => u.id)).size !== urges.length) fail();
    return { id: h.id, name: h.name.trim(), reason: h.reason, startedAt: h.startedAt, createdAt: h.createdAt, history, checkins, entries, goals, intentionLabels: intentionLabels.map(s => s.trim()), targetDays, replacement, urges };
  });
  if (new Set(habits.map(h => h.id)).size !== habits.length || !habits.some(h => h.id === raw.activeId)) fail();
  const sourcePlanner = raw.planner === undefined ? {} : raw.planner;
  if (!sourcePlanner || typeof sourcePlanner !== 'object' || Array.isArray(sourcePlanner) || Object.keys(sourcePlanner).length > 10000) fail();
  const planner = {};
  for (const [key, plan] of Object.entries(sourcePlanner)) {
    if (!date(key) || !plan || !str(plan.focus, 240) || !str(plan.summary, 20000) || !stamp(plan.summarySavedAt) || (plan.summarySavedAt > 0 && !plan.summary.trim()) || !Array.isArray(plan.tasks) || plan.tasks.length > 100) fail();
    const tasks = plan.tasks.map(t => {
      if (!t || !id(t.id) || !id(t.originId) || !str(t.title, 240) || !t.title.trim() || typeof t.done !== 'boolean' || typeof t.priority !== 'boolean') fail();
      const notes = t.notes === undefined ? '' : t.notes, estimate = t.estimate === undefined ? 1 : t.estimate;
      if (!str(notes, 2000) || !Number.isInteger(estimate) || estimate < 1 || estimate > 12) fail();
      const dueDate = t.dueDate ?? '', dueTime = t.dueTime ?? '', remindAtDeadline = t.remindAtDeadline ?? false;
      if (!validDeadline(dueDate, dueTime) || typeof remindAtDeadline !== 'boolean' || (remindAtDeadline && (!dueDate || !dueTime))) fail();
      return { id: t.id, originId: t.originId, title: t.title.trim(), done: t.done, priority: t.priority, notes, estimate, dueDate, dueTime, remindAtDeadline };
    });
    if (new Set(tasks.map(t => t.id)).size !== tasks.length || new Set(tasks.map(t => t.originId)).size !== tasks.length) fail();
    planner[key] = { focus: plan.focus, tasks, summary: plan.summary, summarySavedAt: plan.summarySavedAt };
  }
  return { version: 1, activeId: raw.activeId, habits, planner };
}
