import { DAY, MILESTONES, uid, dayKey, createHabit, initialState, elapsed, stats, checkIn, resetHabit, activeHabit, replaceHabit, validateState, DEFAULT_INTENTIONS, logUrge, weeklyReview, calendarMonth, dayPlan, updateDayPlan, addDayTask, bringTasksForward } from './model.js';
import { focusReport, focusDuration, focusIntervals } from './insights.js';
import { phonePeriod } from './phone-history.js';
import { createPhoneScreenTime } from './phone-ui.js';

const icons = {
  phone: '<rect x="6" y="2" width="12" height="20" rx="3"/><path d="M10 5h4m-3 14h2"/>',
  scope: '<path d="M9 3H5a2 2 0 0 0-2 2v4m12-6h4a2 2 0 0 1 2 2v4M3 15v4a2 2 0 0 0 2 2h4m12-6v4a2 2 0 0 1-2 2h-4"/><circle cx="12" cy="12" r="3"/>',
  circle: '<circle cx="12" cy="12" r="7"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  sprout: '<path d="M12 22V12M12 16C4 17 2 11 3 6c6 0 10 3 9 10ZM12 12C11 5 16 2 22 3c0 6-3 11-10 9Z"/>',
  leaf: '<path d="M20 3C8 2 2 8 5 15s15 5 15-12ZM4 21 16 9M9 16v-5m0 5h5"/>',
  grid: '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
  book: '<path d="M12 5C9 3 5 3 2 4v15c4-1 7-1 10 1 3-2 6-2 10-1V4c-3-1-7-1-10 1Zm0 0v15"/>',
  chart: '<path d="M4 3v17h17M8 14l4-5 4 3 5-7"/>',
  settings: '<path d="m10 3-.6 2.3-2 .9L5 5.5 3 9l1.8 1.8v2.4L3 15l2 3.5 2.4-.7 2 .9L10 21h4l.6-2.3 2-.9 2.4.7 2-3.5-1.8-1.8v-2.4L21 9l-2-3.5-2.4.7-2-.9L14 3Z"/><circle cx="12" cy="12" r="3"/>',
  spark: '<path d="m12 3 2.4 6.6L21 12l-6.6 2.4L12 21l-2.4-6.6L3 12l6.6-2.4ZM20 2v4m-2-2h4"/>',
  lock: '<rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3m-4 5v2"/>',
  wind: '<path d="M3 8h12a3 3 0 1 0-3-3M2 12h17a3 3 0 1 1-3 3M5 16h4a3 3 0 1 1-3 3"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  edit: '<path d="m16 3 5 5L9 20l-6 1 1-6ZM13 6l5 5"/>',
  flame: '<path d="M13 2s1 5-3 8c-2 2-2-2-2-2s-6 5-4 10c3 7 15 6 16-2 1-5-3-8-3-8s0 4-2 4c2-7-2-10-2-10Z"/>',
  reset: '<path d="M3 10a9 9 0 1 1 2 8M3 4v6h6"/>',
  arrow: '<path d="M4 12h16m-6-6 6 6-6 6"/>',
  check: '<path d="m5 12 4 4L19 6"/>',
  close: '<path d="m6 6 12 12M6 18 18 6"/>',
  mountain: '<path d="m2 20 7-12 4 6 3-4 6 10ZM7 11l2 2 2-2"/>',
  shield: '<path d="m12 3 8 3v6c0 5-8 9-8 9s-8-4-8-9V6Z"/><path d="m8 12 3 3 5-6"/>',
  star: '<path d="m12 2 3 7 7 1-5 5 1 7-6-3-6 3 1-7-5-5 7-1Z"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5m11 11L19 19M5 19l1.5-1.5m11-11L19 5"/>',
  flag: '<path d="M5 22V3c5-4 9 4 15 0v11c-6 4-10-4-15 0"/>',
};
const svg = name => `<svg viewBox="0 0 24 24" aria-hidden="true">${icons[name] || icons.spark}</svg>`;
const $ = selector => document.querySelector(selector);
const $$ = selector => [...document.querySelectorAll(selector)];
const escape = value => String(value).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const STORAGE_KEY = 'habit-counter.v1';
const nativeHost = window.__HABIT_NATIVE__ && window.webkit?.messageHandlers?.habitCounter;
const nativeDevice = window.__HABIT_NATIVE__?.platform === 'iOS' ? 'iPhone' : 'Mac';
const isMac = !!nativeHost && nativeDevice === 'Mac';
const phoneScreenTime = isMac ? createPhoneScreenTime({host:nativeHost,escape,svg,dayKey,focusDuration,phonePeriod}) : null;
document.documentElement.dataset.platform = isMac ? 'mac' : 'other';
const appName = isMac ? 'FocoNow' : 'Habit Counter';
if (isMac) {
  document.title = `${appName} — One day at a time`;
  $('#brand-name').textContent = appName;
  $('.brand-mark').dataset.icon = 'scope';
  $('.space-label').textContent = 'YOUR DAILY WORKSPACE';
  $('.sidebar > .nav-label').textContent = 'WORKSPACE';
  $('.brand').setAttribute('aria-label', `${appName} home`);
}
const hasIPhoneFocus = !!nativeHost && nativeDevice === 'iPhone';
const colorSchemeQuery = matchMedia('(prefers-color-scheme: dark)');
let appearance = document.documentElement.dataset.appearance || 'system';
function applyAppearance(preference, persist = false) {
  if (!['system', 'light', 'dark'].includes(preference)) return;
  appearance = preference;
  const theme = preference === 'system' ? (colorSchemeQuery.matches ? 'dark' : 'light') : preference;
  document.documentElement.dataset.appearance = preference;
  document.documentElement.dataset.theme = theme;
  $('meta[name="theme-color"]').setAttribute('content', isMac ? (theme === 'dark' ? '#000000' : '#f5f5f5') : (theme === 'dark' ? '#0f1612' : '#f5f4ef'));
  if (persist) {
    try { localStorage.setItem('habit-counter.appearance', preference); } catch {}
    if (nativeHost) nativeHost.postMessage({ action: 'appearance', preference });
  }
  if ($('#appearance-status')) $('#appearance-status').textContent = appearanceStatus();
  $$('[data-appearance-choice]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.appearanceChoice === preference)));
}
function appearanceStatus() { return appearance === 'system' ? 'Matches your device’s appearance.' : appearance === 'dark' ? 'Dark mode is on.' : 'Light mode is on.'; }
colorSchemeQuery.addEventListener('change', () => { if (appearance === 'system') applyAppearance('system'); });
applyAppearance(appearance);
function keepEditorVisible() {
  const editor = document.activeElement;
  if ($('#modal').open && editor?.matches('textarea,input:not([type=range]):not([type=checkbox])') && $('#modal').contains(editor)) {
    requestAnimationFrame(() => editor.scrollIntoView({ block: 'center', behavior: 'instant' }));
  }
}
function updateVisibleViewport() {
  if (window.visualViewport) document.documentElement.style.setProperty('--visual-height', `${window.visualViewport.height}px`);
  keepEditorVisible();
}
window.visualViewport?.addEventListener('resize', updateVisibleViewport);
document.addEventListener('focusin', keepEditorVisible);
updateVisibleViewport();
let nativeSaveId = 0;
let nativeSavePending = false;
let state;
let storageAvailable = true;
let selectedMood = null;
let currentView = 'overview';
let journalFilter = 'all';
let journalQuery = '';
let reminder = window.__HABIT_NATIVE__?.reminder || { enabled: false, time: '20:00' };
let toastTimer;
let breathingTimer;
let pendingImport;
let renderedDay = dayKey();
let savedDataUnreadable = false;
let plannerDate = dayKey();
let taskFilter = 'all';
let taskQuery = '';
let insightRange = 7;
let insightDay = dayKey();
let lastInsightMinute = '';
let pomodoroError = '';
let pendingPomoSettings = false;
let pomodoro = window.__HABIT_NATIVE__?.pomodoro || {phase:'work',status:'ready',duration:1500,remaining:1500,cycle:0,taskId:'',taskDate:'',taskTitle:'',settings:{work:25,short:5,long:15,every:4,notifications:false},sessions:[]};
let desktopPreferences = window.__HABIT_NATIVE__?.desktop || {};
let permissionStatus = {};
let plannerReminders = window.__HABIT_NATIVE__?.plannerReminders || { enabled: false, morning: '09:00', evening: '21:00' };
let calendarYear = new Date().getFullYear();
let calendarMonthIndex = new Date().getMonth();
try {
  if (nativeHost) {
    if (window.__HABIT_NATIVE__.loadError) throw new Error('Native data needs recovery');
    state = window.__HABIT_NATIVE__.state ? validateState(window.__HABIT_NATIVE__.state) : initialState();
  } else {
    const saved = localStorage.getItem(STORAGE_KEY);
    state = saved ? validateState(JSON.parse(saved)) : initialState();
    if (!saved) localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  }
} catch {
  // Leave an unreadable saved value untouched so it can be recovered or replaced explicitly.
  state = initialState();
  storageAvailable = false;
  if (nativeHost) savedDataUnreadable = true;
  else try { savedDataUnreadable = !!localStorage.getItem(STORAGE_KEY); } catch {}
}

function paintIcons(root = document) { root.querySelectorAll('[data-icon]').forEach(el => el.innerHTML = svg(el.dataset.icon)); }
function habit() { return activeHabit(state); }
function toast(message, error = false) {
  $('#toast').textContent = message;
  $('#toast').className = `toast visible${error ? ' error' : ''}`;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => $('#toast').classList.remove('visible'), 4200);
}
function persistNative(replaceUnreadable = false) {
  nativeSavePending = true;
  nativeHost.postMessage({ action: 'save', state, requestId: ++nativeSaveId, replaceUnreadable });
}
function save(next, message, replaceUnreadable = false, editorOnly = false) {
  state = next;
  try {
    if (savedDataUnreadable) throw new Error('Existing backup needs recovery');
    if (nativeHost) persistNative(replaceUnreadable);
    else localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
    storageAvailable = true;
  } catch { storageAvailable = false; }
  if (editorOnly) { renderStorageStatus(); renderPlanner(); } else render();
  if (!storageAvailable) toast('Couldn’t save on this device. Export a backup in Settings.', true);
  else if (message) toast(message);
}
function updateHabit(next, message) { save(replaceHabit(state, next), message); }
function formatDate(at, options = {}) { return new Date(at).toLocaleDateString(undefined, { month: 'short', day: 'numeric', ...options }); }
function formatFull(at) { return new Date(at).toLocaleString(undefined, { month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit' }); }
function duration(ms) { const hours = Math.floor(ms / 3600000); return hours >= 24 ? `${Math.floor(hours / 24)}d ${hours % 24}h` : hours ? `${hours}h ${Math.floor(ms / 60000) % 60}m` : `${Math.floor(ms / 60000)}m`; }
function localInput(at) { const d = new Date(at); return `${dayKey(at)}T${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`; }
function modal(body, { breathing = false } = {}) {
  stopBreathing();
  window.HabitControls?.close();
  $('#modal-content').innerHTML = `<div class="${breathing ? 'breathe-modal' : 'modal-body'}">${body}</div>`;
  $('#modal').setAttribute('aria-label', $('#modal-content h2')?.textContent || `${appName} dialog`);
  paintIcons($('#modal-content'));
  window.HabitControls?.sync();
  if (!$('#modal').open) $('#modal').showModal();
  $('#modal').scrollTop = 0;
  $('#modal-content').querySelectorAll('[data-close]').forEach(button => button.addEventListener('click', closeModal));
}
function modalHeading(title) { return `<div class="modal-heading"><h2>${title}</h2><button type="button" class="icon-button" data-close aria-label="Close dialog">${svg('close')}</button></div>`; }
function actions(text, danger = false) { return `<div class="modal-error" id="form-error" role="alert"></div><div class="modal-actions"><button type="button" class="button" data-close>Cancel</button><button type="submit" class="button ${danger ? 'danger' : 'primary'}">${text}</button></div>`; }
function closeModal() { $('#modal').close(); stopBreathing(); }
function stopBreathing() { clearInterval(breathingTimer); breathingTimer = undefined; }
$('#modal').addEventListener('close', stopBreathing);
$('#modal').addEventListener('click', event => { if (event.target === $('#modal')) { const r = $('#modal').getBoundingClientRect(); if (event.clientX < r.left || event.clientX > r.right || event.clientY < r.top || event.clientY > r.bottom) closeModal(); } });

function renderCounter() {
  const h = habit();
  const e = elapsed(h);
  $('#streak-days').textContent = e.days;
  for (const part of ['hours', 'minutes', 'seconds']) $(`#streak-${part}`).textContent = String(e[part]).padStart(2, '0');
  const next = MILESTONES.find(n => n > e.days) || Math.ceil((e.days + 1) / 30) * 30;
  const fraction = Math.min(1, e.total / (next * DAY));
  $('#ring-progress').style.strokeDashoffset = 854.514 * (1 - fraction);
  $('#milestone-progress').style.width = `${fraction * 100}%`;
  $('#next-milestone-label').innerHTML = `${next} ${next === 1 ? 'day' : 'days'} <span>↗</span>`;
  $('#milestone-caption').textContent = `${Math.floor(fraction * 100)}% of the way there. Every hour counts.`;
  $('#streak-message').textContent = e.days === 0 ? 'Your next chapter starts now.' : e.days === 1 ? 'One day stronger. Keep going.' : `${e.days} days of choosing yourself. Keep going.`;
  $('#started-label').textContent = `Started ${formatDate(h.startedAt, { year: 'numeric' })}`;
}
function renderCheckin() {
  const today = habit().checkins.find(c => c.date === dayKey());
  $$('.moods button').forEach(button => { button.setAttribute('aria-pressed', String((today?.mood || selectedMood) === button.dataset.mood)); button.disabled = !!today; });
  $('#checkin-button').disabled = !today && !selectedMood;
  $('#quick-checkin span:last-child').textContent = today ? 'My check-in' : 'Check in';
  $('#checkin-heading').textContent = today ? 'You showed up for yourself.' : 'How are you, really?';
  $('#checkin-button').innerHTML = today ? `Edit today’s check-in ${svg('edit')}` : `${selectedMood ? 'Continue check-in' : 'Choose how you feel'} ${svg('arrow')}`;
  $('#checkin-tag').textContent = today ? 'COMPLETE' : 'JUST FOR YOU';
  $('#checkin-status').textContent = today ? `Feeling ${today.mood} · see you tomorrow.` : 'One honest moment is enough.';
}

function renderGoals() {
  const done = habit().goals[dayKey()] || [];
  $('#goal-count').textContent = `${done.length} / 3`;
  $('#goals-list').innerHTML = (habit().intentionLabels || DEFAULT_INTENTIONS).map((text, index) => `<button class="goal-row ${done.includes(index) ? 'done' : ''}" data-goal="${index}" aria-pressed="${done.includes(index)}"><span class="goal-box">${done.includes(index) ? svg('check') : ''}</span><span class="goal-text">${escape(text)}</span><span>${done.includes(index) ? 'Done' : ''}</span></button>`).join('');
  $$('#goals-list button').forEach(button => button.addEventListener('click', () => {
    const h = habit(), index = Number(button.dataset.goal), date = dayKey();
    const completed = h.goals[date] || [];
    const next = completed.includes(index) ? completed.filter(n => n !== index) : [...completed, index];
    updateHabit({ ...h, goals: { ...h.goals, [date]: next } }, next.length > completed.length ? 'One small win. It all adds up.' : undefined);
  }));
}
function renderActivity() {
  const dates = Array.from({ length: 30 }, (_, i) => { const d = new Date(); d.setHours(12, 0, 0, 0); d.setDate(d.getDate() - 29 + i); return d; });
  let count = 0;
  $('#activity-grid').innerHTML = dates.map(date => {
    const checked = habit().checkins.find(c => c.date === dayKey(date));
    if (checked) count++;
    const label = `${formatDate(date)}: ${checked ? `checked in, feeling ${checked.mood}` : 'no check-in'}`;
    return `<div class="activity-day${checked ? ' filled' : ''}${dayKey(date) === dayKey() ? ' today' : ''}" title="${escape(label)}" role="img" aria-label="${escape(label)}"></div>`;
  }).join('');
  const week = dates.slice(-7);
  const weekChecks = week.filter(d => habit().checkins.some(c => c.date === dayKey(d)));
  $('#week-count').textContent = `${weekChecks.length} / 7 check-ins`;
  $('#week-strip').innerHTML = week.map(d => {
    const checked = habit().checkins.some(c => c.date === dayKey(d));
    const current = dayKey(d) === dayKey();
    return `<div class="week-day${current ? ' current' : ''}${checked ? ' checked' : ''}" aria-label="${escape(formatDate(d))}: ${checked ? 'checked in' : 'no check-in'}${current ? ', today' : ''}"><small>${d.toLocaleDateString(undefined, {weekday:'narrow'})}</small><span>${checked ? svg('check') : d.getDate()}</span><i></i></div>`;
  }).join('');
  $('#activity-count').textContent = `${count} check-in${count === 1 ? '' : 's'}`;
  $('#activity-range').textContent = `${formatDate(dates[0])} — ${formatDate(dates[29])}`;
}
function renderMilestones() {
  const days = elapsed(habit()).days;
  const names = ['First step', 'Finding rhythm', 'One week', 'Growing strong', 'A new chapter', 'Rooted', 'Keep rising'];
  const symbols = ['sprout', 'leaf', 'flame', 'mountain', 'shield', 'star', 'sun'];
  $('#milestones').innerHTML = MILESTONES.map((n, i) => `<div class="milestone ${days >= n ? 'unlocked' : ''}" title="${days >= n ? 'Reached on this streak' : `Reach ${n} full days on this streak`}"><span class="milestone-icon">${svg(symbols[i])}</span><strong>${n} ${n === 1 ? 'day' : 'days'}</strong><small>${names[i]}</small></div>`).join('');
  $('#milestone-count').textContent = `${MILESTONES.filter(n => days >= n).length} unlocked`;
}
function journalItems() {
  const h = habit();
  return [
    ...(isMac ? Object.entries(state.planner || {}).filter(([,p]) => p.summary.trim()).map(([date,p]) => ({ id: `summary:${date}`, at: p.summarySavedAt || new Date(`${date}T23:59:00`).getTime(), date, text: p.summary, kind: 'Daily summary', type: `Daily summary${p.summarySavedAt ? '' : ' · draft'}`, plannerDate: date })) : []),
    ...h.entries.map(e => ({ ...e, type: 'Reflection', kind: 'Reflection', editable: true })),
    ...h.checkins.map(c => ({ id: c.id, at: c.at, date: c.date, text: c.note || `I checked in today. Feeling ${c.mood}.`, kind: 'Check-in', type: `Check-in · ${c.mood}` })),
    ...h.history.map(r => ({ id: r.id, at: r.endedAt, text: [r.trigger && `What came up: ${r.trigger}`, r.note || 'A new start. My progress still counts.'].filter(Boolean).join('\n'), kind: 'Fresh start', type: 'Fresh start' })),
    ...(h.urges || []).map(u => ({ id: u.id, at: u.at, kind: 'Urge', type: `Urge · ${u.intensity}/5${u.outcome === 'passed' ? ' · passed' : ''}`, text: [u.trigger && `Trigger: ${u.trigger}`, u.note || 'I paused and noticed the moment.'].filter(Boolean).join('\n') })),
  ].sort((a, b) => (b.date || dayKey(b.at)).localeCompare(a.date || dayKey(a.at)) || b.at - a.at);
}
function renderJournal() {
  const all = journalItems();
  const entries = all.filter(e => (journalFilter === 'all' || e.kind === journalFilter) && `${e.text} ${e.type}`.toLocaleLowerCase().includes(journalQuery.toLocaleLowerCase()));
  $$('[data-journal-filter]').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.journalFilter === journalFilter)));
  let lastDate = '';
  $('#journal-list').innerHTML = entries.length ? entries.map(e => {
    const key = e.date || dayKey(e.at), newDate = key !== lastDate;
    lastDate = key;
    const label = key === dayKey() ? 'Today' : formatDate(new Date(`${key}T12:00:00`), { weekday: 'long', year: 'numeric' });
    return `${newDate ? `<h3 class="journal-date">${escape(label)}</h3>` : ''}<article class="card journal-entry"><div class="entry-meta"><span>${e.plannerDate ? 'Your day' : escape(new Date(e.at).toLocaleTimeString(undefined, {hour:'numeric',minute:'2-digit'}))}</span><span class="entry-tag">${escape(e.type)}</span>${e.plannerDate ? `<button class="icon-button edit-daily-summary" data-summary-date="${e.plannerDate}" aria-label="Edit daily summary">${svg('edit')}</button>` : ''}${e.editable ? `<button class="icon-button edit-entry" data-entry="${escape(e.id)}" aria-label="Edit reflection">${svg('edit')}</button>` : ''}</div><p class="entry-text">${escape(e.text)}</p></article>`;
  }).join('') : `<div class="empty-state">${svg('book')}<h3>${all.length ? 'No matching moments.' : 'Every story starts somewhere.'}</h3><p>${all.length ? 'Try another word or choose a different filter.' : 'A thought, a check-in, a small win. Keep the moments that matter.'}</p>${all.length ? '' : '<button class="button primary" id="empty-new-entry">Write your first entry</button>'}</div>`;
  $('#empty-new-entry')?.addEventListener('click', () => entryModal());
  $$('.edit-daily-summary').forEach(button => button.addEventListener('click', () => { openPlanner(button.dataset.summaryDate); $('#day-summary').focus(); }));
  $$('.edit-entry').forEach(button => button.addEventListener('click', () => entryModal(button.dataset.entry)));
}
function renderPomodoroTotals() {
  const start = new Date(`${plannerDate}T00:00:00`), end = new Date(start); end.setDate(end.getDate()+1);
  const seconds = focusIntervals(pomodoro).reduce((sum,span)=>sum+Math.max(0,Math.min(+end,span.end)-Math.max(+start,span.start))/1000,0);
  $('#focus-minute-count').textContent = Math.floor(seconds/60);
  $('#day-focus-minutes').textContent = Math.floor(seconds/60);
}
function renderFocusInsights() {
  const report = focusReport(pomodoro,state.planner,insightRange);
  if (!report.days.some(d=>d.date===insightDay)) insightDay=dayKey();
  const selected = report.days.find(d=>d.date===insightDay);
  const running = pomodoro.status==='running' && pomodoro.phase==='work';
  $('#insight-total').textContent = focusDuration(report.seconds);
  const difference = report.seconds-report.previousSeconds;
  $('#insight-comparison').textContent = report.previousSeconds>0 ? `${difference>=0?'↑':'↓'} ${focusDuration(Math.abs(difference))} ${difference>=0?'more':'less'} than the previous ${insightRange} days` : report.seconds>0 ? 'You made this time. That matters.' : 'Start a focus session. Watch your effort add up.';
  $('#insight-live').innerHTML = `<i class="${running?'is-live':''}"></i>${running?'Focus is running · updates each minute':'Saved on this Mac'}`;
  $$('[data-insight-range]').forEach(b=>b.setAttribute('aria-pressed',String(Number(b.dataset.insightRange)===insightRange)));
  const maxHours = Math.max(1,Math.ceil(Math.max(...report.days.map(d=>d.seconds))/3600));
  $('#focus-chart-axis').innerHTML = [maxHours,maxHours/2,0].map(n=>`<span>${Number(n.toFixed(1))}h</span>`).join('');
  $('#focus-bars').classList.toggle('month-range',insightRange===30);
  $('#focus-bars').innerHTML = report.days.map((d,i)=> {
    const label = new Date(`${d.date}T12:00:00`).toLocaleDateString(undefined,{weekday:'short',month:'short',day:'numeric'});
    return `<button class="focus-bar ${d.date===dayKey()?'today':''}" data-focus-day="${d.date}" aria-pressed="${d.date===insightDay}" aria-label="${escape(label)}: ${focusDuration(d.seconds)}, ${d.done} of ${d.tasks} tasks complete" title="${escape(label)} · ${focusDuration(d.seconds)}"><span class="bar-column"><span class="bar-fill" style="height:${Math.max(d.seconds>0?1:0,d.seconds/(maxHours*3600)*100)}%"></span>${insightRange===7?`<span class="bar-value">${d.seconds>0?focusDuration(d.seconds):'—'}</span>`:''}</span><span class="bar-date">${insightRange===7?escape(new Date(`${d.date}T12:00:00`).toLocaleDateString(undefined,{weekday:'short'})):(i%5===0||i===29?new Date(`${d.date}T12:00:00`).getDate():'')}</span><i></i></button>`;
  }).join('');
  $$('[data-focus-day]').forEach(b=>b.addEventListener('click',()=>{insightDay=b.dataset.focusDay;renderFocusInsights();}));
  const bestHour = report.bestHour===null ? '—' : new Date(2000,0,1,report.bestHour).toLocaleTimeString(undefined,{hour:'numeric',minute:'2-digit'});
  $('#focus-stat-cards').innerHTML = [['DAILY AVERAGE',focusDuration(report.average),`across ${insightRange} days`],['DAYS WITH FOCUS',`${report.activeDays}<small> / ${insightRange}</small>`,`${report.sessions} completed ${report.sessions===1?'session':'sessions'}`],['YOUR STRONGEST HOUR',bestHour,report.bestHour===null?'Your rhythm will appear here':'most focus time in this period']].map(([label,value,note])=>`<section class="card focus-stat"><span class="section-label">${label}</span><strong>${value}</strong><p>${note}</p></section>`).join('');
  $('#focus-day-title').textContent = insightDay===dayKey()?'Today':formatDate(new Date(`${insightDay}T12:00:00`),{weekday:'long'});
  $('#focus-day-total').textContent = focusDuration(selected.seconds);
  $('#focus-day-caption').textContent = `${selected.sessions} completed ${selected.sessions===1?'session':'sessions'} · ${selected.done} / ${selected.tasks} tasks done`;
  const peak = Math.max(3600,...selected.hours);
  $('#focus-hour-chart').innerHTML = selected.hours.map((seconds,hour)=>`<div title="${String(hour).padStart(2,'0')}:00 · ${focusDuration(seconds)}" role="img" aria-label="${hour}:00, ${focusDuration(seconds)}"><i style="height:${Math.max(seconds>0?3:0,seconds/peak*100)}%"></i></div>`).join('');
  const merged = [];
  for (const span of [...selected.spans].sort((a,b)=>a.start-b.start)) {
    const last = merged.at(-1);
    if (last && span.taskId===last.taskId && span.legacy===last.legacy && span.start-last.end<=1000) last.end=Math.max(last.end,span.end);
    else merged.push({...span});
  }
  const time = at=>new Date(at).toLocaleTimeString(undefined,{hour:'2-digit',minute:'2-digit'});
  $('#focus-day-detail').innerHTML = merged.length ? merged.slice(-4).reverse().map(span=>`<div><i></i><span><b>${escape(span.taskTitle||'Open focus')}</b><small>${time(span.start)} – ${time(span.end)}${span.legacy?' · estimated':''}</small></span><strong>${focusDuration((span.end-span.start)/1000,true)}</strong></div>`).join('')+(merged.length>4?`<p class="insight-caption">Showing the latest 4 of ${merged.length} focus stretches.</p>`:'') : '<div class="insight-empty">A clear space for your next focus session.</div>';
  const percent = report.tasks ? Math.round(report.done/report.tasks*100) : 0;
  $('#task-completion-ring').innerHTML = `<svg viewBox="0 0 180 180" aria-hidden="true"><circle cx="90" cy="90" r="78"/><circle class="completion-arc" cx="90" cy="90" r="78" stroke-dasharray="${percent*4.901} 490.1"/></svg><div><strong>${percent}<small>%</small></strong><span>tasks complete</span></div>`;
  $('#task-momentum-caption').textContent = report.tasks ? `${report.done} of ${report.tasks} planned tasks. ${percent===100?'Everything you planned, done. ✦':percent>=50?'Look at you, moving things forward.':'One small finish at a time.'}` : 'Plan a few tasks. Give your day a little direction.';
  $('#insight-task-days').innerHTML = report.days.slice(-7).map(d=>`<span title="${d.date}: ${d.done}/${d.tasks} tasks"><i class="${d.tasks && d.done===d.tasks?'all-done':''}" style="--done:${d.tasks?d.done/d.tasks:0}">${d.tasks && d.done===d.tasks?'✓':d.done||'·'}</i><small>${escape(new Date(`${d.date}T12:00:00`).toLocaleDateString(undefined,{weekday:'narrow'}))}</small></span>`).join('');
  const top = report.byTask.slice(0,5), largest = top[0]?.seconds || 1;
  $('#focus-task-ranking').innerHTML = top.length ? top.map((task,i)=>`<div class="allocation-row"><span class="allocation-number">${String(i+1).padStart(2,'0')}</span><div><span>${escape(task.title)}</span><div class="allocation-track"><i style="width:${task.seconds/largest*100}%"></i></div></div><strong>${focusDuration(task.seconds)}</strong></div>`).join('') : '<div class="insight-empty">Start with a task or an open focus session. Your time will find its place here.</div>';
}
function renderInsights() {
  if (isMac) renderFocusInsights();
  const h = habit(), s = stats(h), review = weeklyReview(h);
  $('#weekly-summary').innerHTML = [['Check-ins', `${review.checkins}/7`], ['Small wins', review.intentions], ['Urges passed', review.passed]].map(([label,value]) => `<div><strong>${value}</strong><span>${label}</span></div>`).join('');
  const scores = { tough: 1, low: 2, okay: 3, good: 4, great: 5 };
  $('#mood-chart').innerHTML = review.dates.map(date => {
    const c = h.checkins.find(c => c.date === date);
    const d = new Date(`${date}T12:00:00`);
    return `<div class="mood-column ${c ? '' : 'empty'}" role="img" aria-label="${escape(formatDate(d))}: ${c ? c.mood : 'no check-in'}"><div class="mood-bar-space"><div style="height:${c ? 12 + scores[c.mood] * 10 : 6}px"></div></div><span>${d.toLocaleDateString(undefined, {weekday:'narrow'})}</span></div>`;
  }).join('');
  const items = [['CURRENT STREAK', s.currentDays, 'full days and counting'], ['PERSONAL BEST', s.bestDays, 'full days in a streak'], ['SHOWING UP', s.checkins, 'daily check-ins'], ['FRESH STARTS', s.resets, 'each one a new beginning']];
  $('#stats-grid').innerHTML = items.map(([title, value, detail]) => `<div class="card stat-card"><span class="section-label">${title}</span><strong>${value}</strong><small>${detail}</small></div>`).join('');
  $('#history-list').innerHTML = `<div class="history-row"><div><h3>Current streak <span class="live-label">LIVE</span></h3><p>${escape(formatFull(h.startedAt))} → now</p></div><strong>${duration(elapsed(h).total)}</strong></div>` + [...h.history].reverse().map(r => `<div class="history-row"><div><h3>${escape(formatDate(r.startedAt))} — ${escape(formatDate(r.endedAt, { year: 'numeric' }))}</h3><p>${escape(r.trigger || 'No trigger noted')}${r.note ? ` · ${escape(r.note)}` : ''}</p></div><strong>${duration(r.endedAt - r.startedAt)}</strong></div>`).join('');
  const triggers = Object.create(null);
  [...h.history, ...(h.urges || [])].forEach(r => { if (r.trigger) triggers[r.trigger] = (triggers[r.trigger] || 0) + 1; });
  $('#trigger-list').innerHTML = Object.keys(triggers).length ? Object.entries(triggers).sort((a, b) => b[1] - a[1]).map(([name, count]) => `<div class="trigger-row"><span>${escape(name)}</span><span>${count} ${count === 1 ? 'time' : 'times'}</span></div>`).join('') : '<p class="muted">When you log a reset, you can note a trigger. Over time, your patterns will appear here.</p>';
}
function renderStorageStatus() {
  $('#storage-warning').hidden = storageAvailable;
  if (nativeHost) $('#storage-warning').textContent = savedDataUnreadable ? 'Your saved data could not be loaded and has been left untouched. Restore a backup in Settings to continue saving.' : `Couldn’t save to this ${nativeDevice}. Export a backup before closing.`;
  $('.local-chip').innerHTML = `<i></i>${!storageAvailable ? 'Changes not saved' : nativeSavePending ? `Saving to this ${nativeDevice}…` : nativeHost ? `Saved on this ${nativeDevice}` : 'Saved on this device'}`;
}
function render() {
  renderStorageStatus();
  $('#habit-select').innerHTML = state.habits.map(h => `<option value="${escape(h.id)}"${h.id === state.activeId ? ' selected' : ''}>${escape(h.name)}</option>`).join('');
  $('#date-label').textContent = new Date().toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric', year: 'numeric' });
  renderedDay = dayKey();
  $('#setup-banner').hidden = habit().name !== 'My habit' || !!habit().reason;
  if (isMac) { renderCalendar(); renderPlanner(); }
  renderPlan(); renderCounter(); renderCheckin(); renderGoals(); renderActivity(); renderMilestones(); renderJournal(); renderInsights();
  window.HabitControls?.sync();
}
function route() {
  window.HabitControls?.close();
  const requested = location.hash.slice(1);
  currentView = ['overview', 'journal', 'insights', ...(isMac ? ['planner','tasks','phone'] : [])].includes(requested) ? requested : isMac ? 'planner' : 'overview';
  document.documentElement.dataset.view = currentView;
  const titles = { phone: ['Your phone, in perspective', 'A little awareness. A little more intention.', 'iPhone Screen Time'], tasks: ['Less noise. More done', 'A task worth doing. A little space to focus.', 'Tasks & focus'], planner: ['Make today count', 'A clear mind. A little direction. A day that feels like yours.', 'My day'], overview: ['Today is yours', 'One small choice. A little more you.', 'Today'], journal: ['Put it into words', 'A quiet place to notice, reflect, and grow.', 'My journal'], insights: ['See your progress', 'Every time you show up, it adds up.', 'Insights'] };
  if (isMac) {
    titles.planner = ['My Day', 'Plan what matters, make time to focus, and close the day with a short review.', 'My Day'];
    titles.tasks = ['Tasks & Focus', 'Organize your tasks and give one thing your full attention.', 'Tasks & Focus'];
    titles.overview = ['Bad Habits', 'Track patterns you want to change and see your progress over time.', 'Bad Habits'];
    titles.insights = ['Insights', 'See how you spend your focus time and what you get done.', 'Insights'];
  }
  const [heading, subtitle, label] = titles[currentView];
  $('#heading').textContent = isMac ? heading : heading + '.';
  $('#breathe-button').hidden = isMac && currentView !== 'overview';
  $('#subheading').textContent = subtitle;
  $('#page-label').textContent = label;
  for (const view of ['overview', 'journal', 'insights', 'planner', 'tasks', 'phone']) $(`#${view}-view`).hidden = view !== currentView;
  $$('.nav-item[data-view]').forEach(link => { link.classList.toggle('active', link.dataset.view === currentView); if (link.dataset.view === currentView) link.setAttribute('aria-current', 'page'); else link.removeAttribute('aria-current'); });
  phoneScreenTime?.activate(currentView === 'phone');
  if (currentView === 'insights') renderInsights();
  if (currentView === 'journal') renderJournal();
  if (currentView === 'overview' && isMac) renderCalendar();
  if (isMac && ['planner','tasks'].includes(currentView)) renderPlanner();
  window.scrollTo({ top: 0, behavior: 'instant' });
}

function habitModal(isNew = false) {
  const h = habit();
  const presets = [['Less scrolling','Put my phone in another room.'],['Smoke-free','Step outside and take a short walk.'],['Less caffeine','Make a glass of water first.'],['No gambling','Leave the app and do something offline.']];
  modal(`${modalHeading(isNew ? (isMac ? 'Add a bad habit' : 'A new intention') : (isMac ? 'Edit bad habit' : 'Make this space yours'))}<p class="modal-intro">Name the habit you want to step away from. You can start now or pick when your streak began.</p>${isNew ? `<div class="habit-presets" role="group" aria-label="Habit suggestions">${presets.map(([name],i) => `<button type="button" data-preset="${i}">${name}</button>`).join('')}</div>` : ''}<form id="habit-form"><label class="field"><span>Habit name</span><input id="habit-name" maxlength="60" required placeholder="e.g. Late-night scrolling" value="${isNew ? '' : escape(h.name)}" autofocus></label><label class="field"><span>My reason for starting <span class="muted">(optional)</span></span><textarea id="habit-reason" maxlength="500" placeholder="I want to be more present in my life…">${isNew ? '' : escape(h.reason)}</textarea></label><label class="field"><span>Streak started</span><input type="datetime-local" id="habit-start" required max="${localInput(Date.now())}" value="${localInput(isNew ? Date.now() : h.startedAt)}"><small>Days are counted in full 24-hour periods. Past streaks stay in your history.</small></label><div class="settings-section"><h3>Make it personal</h3><label class="field"><span>My goal in days</span><input type="number" id="habit-target" min="1" max="3650" required value="${isNew ? 30 : h.targetDays || 30}" inputmode="numeric"></label><label class="field"><span>When an urge hits, I’ll… <span class="muted">(optional)</span></span><input id="habit-replacement" maxlength="300" placeholder="Take a walk, message a friend, make some tea…" value="${isNew ? '' : escape(h.replacement || '')}"></label></div>${actions(isNew ? 'Start tracking' : 'Save changes')}</form>`);
  $$('[data-preset]').forEach(button => button.addEventListener('click', () => { const preset = presets[Number(button.dataset.preset)]; $('#habit-name').value = preset[0]; $('#habit-replacement').value = preset[1]; }));
  $('#habit-form').addEventListener('submit', event => {
    event.preventDefault();
    const targetDays = Number($('#habit-target').value), replacement = $('#habit-replacement').value.trim();
    if (!Number.isInteger(targetDays) || targetDays < 1 || targetDays > 3650) { $('#form-error').textContent = 'Choose a goal between 1 and 3,650 days.'; return; }
    const name = $('#habit-name').value.trim(), reason = $('#habit-reason').value.trim(), start = new Date($('#habit-start').value).getTime();
    if (!name) { $('#form-error').textContent = 'Give your habit a name first.'; return; }
    if (!Number.isFinite(start) || start > Date.now() || start < 0) { $('#form-error').textContent = 'Choose a start time in the past or present.'; return; }
    if (isNew && state.habits.length >= 50) { $('#form-error').textContent = 'You can track up to 50 habits.'; return; }
    if (isNew) {
      const next = { ...createHabit(name, reason, start), targetDays, replacement };
      selectedMood = null;
      save({ ...state, activeId: next.id, habits: [...state.habits, next] }, 'Your next chapter starts here.');
    } else {
      // Preserve seconds when the user only changes the name or reason.
      updateHabit({ ...h, name, reason, targetDays, replacement, startedAt: $('#habit-start').value === localInput(h.startedAt) ? h.startedAt : start }, 'Your habit is updated.');
    }
    closeModal();
  });
}
function checkinModal() {
  const h = habit(), today = h.checkins.find(c => c.date === dayKey());
  let chosen = today?.mood || selectedMood;
  modal(`${modalHeading(today ? 'Your moment today' : 'You’re showing up')}<p class="modal-intro">An honest check-in. As little or as much as you need.</p><form id="checkin-form"><div class="checkin-choices" role="group" aria-label="How are you feeling?">${['tough','low','okay','good','great'].map(mood => `<button type="button" data-checkin-mood="${mood}" aria-label="${mood[0].toUpperCase()+mood.slice(1)} mood" aria-pressed="${mood === chosen}">${mood[0].toUpperCase()+mood.slice(1)}</button>`).join('')}</div><label class="field"><span>A thought for today <span class="muted">(optional)</span></span><textarea id="checkin-note" maxlength="12000" placeholder="What helped? What felt hard?">${escape(today?.note || '')}</textarea></label>${actions('Save check-in')}</form>`);
  const submit = $('#checkin-form button[type=submit]'); submit.disabled = !chosen;
  $$('[data-checkin-mood]').forEach(button => button.addEventListener('click', () => { chosen = button.dataset.checkinMood; submit.disabled = false; $$('[data-checkin-mood]').forEach(b => b.setAttribute('aria-pressed', String(b === button))); }));
  $('#checkin-form').addEventListener('submit', event => {
    event.preventDefault(); if (!chosen || habit().id !== h.id) return;
    const note = $('#checkin-note').value.trim();
    const next = today ? { ...habit(), checkins: habit().checkins.map(c => c.id === today.id ? { ...c, mood: chosen, note } : c) } : checkIn(habit(), chosen, note);
    updateHabit(next, today ? 'Your check-in is updated.' : 'You showed up. That’s a win.'); closeModal();
  });
}
function entryModal(entryId = null) {
  const h = habit(), existing = typeof entryId === 'string' ? h.entries.find(e => e.id === entryId) : null;
  modal(`${modalHeading(existing ? 'Revisit your reflection' : 'A moment of reflection')}<p class="modal-intro">No right words needed. Just write what’s here.</p><div class="writing-prompts" role="group" aria-label="Writing prompts">${['What helped me today?','What do I want to make room for?','One small win I noticed…'].map(text => `<button type="button" data-prompt="${escape(text)}">${escape(text)}</button>`).join('')}</div><form id="entry-form"><label class="field"><span>Your thoughts</span><textarea id="entry-text" required maxlength="12000" rows="6" placeholder="Today, I noticed…">${escape(existing?.text || '')}</textarea></label>${actions('Save to my journal')}</form>`);
  $$('[data-prompt]').forEach(button => button.addEventListener('click', () => { const input = $('#entry-text'); input.value = `${input.value}${input.value ? '\n\n' : ''}${button.dataset.prompt}\n`; input.focus(); }));
  $('#entry-form').addEventListener('submit', event => { event.preventDefault(); const text = $('#entry-text').value.trim(); if (!text) { $('#form-error').textContent = 'Write a little something first.'; return; } if (habit().id !== h.id) return; updateHabit({ ...habit(), entries: existing ? habit().entries.map(e => e.id === existing.id ? { ...e, text } : e) : [...habit().entries, { id: uid(), at: Date.now(), text }] }, 'Saved to your journal.'); closeModal(); });
}
function resetModal() {
  const h = habit();
  modal(`${modalHeading('A fresh start, not a failure')}<p class="modal-intro">This streak will move to your history. Your check-ins, journal, and previous progress stay with you.</p>${h.reason ? `<div class="reason-note">Your why: ${escape(h.reason)}</div>` : ''}<form id="reset-form"><label class="field"><span>What came up? <span class="muted">(optional)</span></span><select id="reset-trigger"><option value="">Choose a trigger</option>${['Stress', 'Boredom', 'Feeling lonely', 'Late-night habits', 'Social media', 'Being tired', 'Something else'].map(s => `<option>${s}</option>`).join('')}</select></label><label class="field"><span>One thing to take with you <span class="muted">(optional)</span></span><textarea id="reset-note" maxlength="12000" placeholder="Next time, I could try…"></textarea></label>${actions('Save & restart counter', true)}</form>`);
  $('#reset-form').addEventListener('submit', event => { event.preventDefault(); updateHabit(resetHabit(h, $('#reset-trigger').value, $('#reset-note').value), 'A new start. Your progress still counts.'); closeModal(); });
}
function breatheModal() {
  const h = habit();
  modal(`${modalHeading('Come back to this moment')}<p class="modal-intro">Pause. Give yourself one minute before deciding what’s next.</p><div class="breathing-orb" id="breathing-orb" aria-hidden="true"></div><div class="breathing-text" id="breathing-text" role="status" aria-live="polite">You have a little space.</div><div class="breathe-count" id="breathe-count">4 seconds in · 4 hold · 4 out</div>${h.replacement ? `<div class="reason-note">My next step: ${escape(h.replacement)}</div>` : h.reason ? `<div class="reason-note">${escape(h.reason)}</div>` : ''}<p class="breathe-tip">Put both feet on the ground. Relax your shoulders.<br>You can take the next moment as it comes.</p><button class="button primary" id="start-breathing">Start 60-second breathing</button><button class="button" data-close>I’m ready to return</button>`, { breathing: true });
  $('#start-breathing').addEventListener('click', () => {
    if (breathingTimer) return;
    const started = Date.now();
    $('#breathing-orb').classList.add('running');
    $('#start-breathing').hidden = true;
    const tick = () => {
      const seconds = Math.floor((Date.now() - started) / 1000);
      if (seconds >= 60) { stopBreathing(); $('#breathing-orb').classList.remove('running'); $('#breathing-text').textContent = 'One minute, just for you.'; $('#breathe-count').textContent = 'Take a sip of water or change your surroundings.'; $('#start-breathing').textContent = 'Take another minute'; $('#start-breathing').hidden = false; return; }
      const phase = seconds % 12;
      $('#breathing-text').textContent = phase < 4 ? 'Breathe in…' : phase < 8 ? 'Gently hold…' : 'Breathe out…';
      $('#breathe-count').textContent = `${4 - phase % 4} · ${60 - seconds} seconds remaining`;
    };
    tick(); breathingTimer = setInterval(tick, 250);
  });
}
function downloadBackup() {
  if (nativeHost) { nativeHost.postMessage({ action: 'export', state }); return; }
  const blob = new Blob([JSON.stringify(state, null, 2)], { type: 'application/json' });
  const link = document.createElement('a');
  link.href = URL.createObjectURL(blob); link.download = `habit-counter-${dayKey()}.json`; link.click();
  setTimeout(() => URL.revokeObjectURL(link.href), 1000);
  toast('Your backup is ready. Keep it somewhere private.');
}
function settingsModal() {
  const storageNote = nativeHost ? `Your records are saved locally in this ${nativeDevice} app, independently of your browser. This version works offline and doesn’t sync between devices. Import a backup to bring over your existing data.${isMac ? ' Task notes and estimates are included in backups. Pomodoro settings and session totals stay on this Mac.' : ''}` : 'Data is stored in this browser only. It won’t sync between devices. Clearing browser data removes your records. Export a backup to keep a copy.';
  modal(`${modalHeading('Your space, your settings')}<p class="modal-intro">${isMac ? 'Set up FocoNow and manage your local backups.' : 'Manage your habit and keep a copy of your progress.'}</p><div class="settings-section appearance-section"><h3>Appearance</h3><p>Choose your look, or follow your device.</p><div class="appearance-options" role="group" aria-label="Appearance">${[['system','System','◐'],['light','Light','☀'],['dark','Dark','☾']].map(([value,label,symbol]) => `<button type="button" data-appearance-choice="${value}" aria-label="${label} appearance" aria-pressed="${appearance === value}"><span aria-hidden="true">${symbol}</span><b>${label}</b><i aria-hidden="true">${svg('check')}</i></button>`).join('')}</div><p id="appearance-status" class="appearance-status" role="status">${appearanceStatus()}</p></div>${isMac ? '' : `<div class="settings-section"><h3>${escape(habit().name)}</h3><p>Change your habit’s name, your reason, or when your current streak began.</p><button class="button" id="settings-edit">${svg('edit')}Edit current habit</button></div>`}${hasIPhoneFocus ? `<div class="settings-section"><h3>Protect your focus</h3><p>Choose which apps to block or give them one shared daily usage budget.</p><button class="button" id="settings-focus">${svg('lock')}App limits</button></div>` : ''}${isMac ? '' : `<div class="settings-section"><h3>A gentle daily nudge</h3><p>${reminder.enabled ? `A reminder at ${escape(reminder.time)}, every day.` : 'Choose a time to pause and check in.'}</p><button class="button" id="open-reminder">${svg('sun')}Daily reminder</button></div>`}<div class="settings-section"><h3>Keep your progress safe</h3><p>${storageNote}</p><div class="settings-buttons"><button class="button primary" id="export-backup">Export backup</button><button class="button" id="import-backup">Import backup</button><input type="file" id="backup-file" accept="application/json,.json" hidden></div><p class="modal-error" id="import-error" role="alert"></p></div>${isMac ? '<div class="settings-section"><h3>Recovery copies</h3><p>Before your first change each day, the Mac app keeps a local copy of your previous data. Your 14 most recent copies stay on this Mac.</p><button class="button" id="open-recovery">Browse recovery copies</button></div><div class="settings-section"><h3>Made for your Mac</h3><div id="desktop-preferences"></div><p>Your counter and shortcuts are also in the menu bar. The app stays available there after you close this window.</p><button class="button" id="show-shortcuts">Keyboard shortcuts</button></div>' : ''}<div class="settings-section"><h3>A personal space</h3><p>No analytics, ads, or tracking scripts. Your notes and habit data aren’t sent to a server by this app.</p></div>`);
  $$('[data-appearance-choice]').forEach(button => button.addEventListener('click', () => applyAppearance(button.dataset.appearanceChoice, true)));
  $('#settings-focus')?.addEventListener('click', () => nativeHost.postMessage({ action: 'openFocus' }));
  $('#open-reminder')?.addEventListener('click', reminderModal);
  $('#settings-edit')?.addEventListener('click', () => habitModal());
  $('#open-recovery')?.addEventListener('click', () => nativeHost.postMessage({ action: 'recoveryList' }));
  $('#show-shortcuts')?.addEventListener('click', shortcutsModal);
  if (isMac) { renderDesktopPreferences(); nativeHost.postMessage({ action: 'desktopPreferences' }); }
  $('#export-backup').addEventListener('click', downloadBackup);
  $('#import-backup').addEventListener('click', () => nativeHost ? nativeHost.postMessage({ action: 'import' }) : $('#backup-file').click());
  $('#backup-file').addEventListener('change', async event => {
    const file = event.target.files[0];
    if (!file) return;
    try {
      if (file.size > 10 * 1024 * 1024) throw new Error('Choose a backup smaller than 10 MB.');
      confirmBackupImport(JSON.parse(await file.text()));
    } catch (error) { $('#import-error').textContent = error instanceof SyntaxError ? 'This file isn’t a readable JSON backup.' : error.message; }
  });
}

function confirmBackupImport(raw) {
  pendingImport = validateState(raw);
  modal(`${modalHeading('Restore your backup?')}<p class="modal-intro">This file contains ${pendingImport.habits.length} habit${pendingImport.habits.length === 1 ? '' : 's'}. Importing replaces all habits, tasks, and daily summaries currently ${nativeHost ? `in this ${nativeDevice} app` : 'on this browser'}.</p><p class="reason-note">${Object.keys(pendingImport.planner || {}).length} saved daily plans · ${Object.values(pendingImport.planner || {}).filter(p => p.summary.trim()).length} day summaries${Object.keys(pendingImport.planner || {}).length ? '' : '. This backup has no daily plans; restoring it clears the current planner.'}</p><div class="import-preview">${pendingImport.habits.slice(0,5).map(h => `<div><b>${escape(h.name)}</b><small>${h.checkins.length} check-ins · ${h.entries.length} reflections · ${h.history.length} past streaks</small></div>`).join('')}${pendingImport.habits.length > 5 ? `<p>And ${pendingImport.habits.length - 5} more habits.</p>` : ''}</div><p class="modal-intro">Export your current data first if you want to keep it.</p><div class="settings-buttons"><button class="button" id="export-before-import">Export current data</button></div><div class="modal-actions"><button class="button" data-close>Cancel</button><button class="button danger" id="confirm-import">Replace with backup</button></div>`);
  $('#export-before-import').addEventListener('click', downloadBackup);
  $('#confirm-import').addEventListener('click', () => { selectedMood = null; savedDataUnreadable = false; save(pendingImport, 'Your backup has been restored.', true); pendingImport = undefined; closeModal(); });
}

paintIcons();
$$('[data-face]').forEach(face => {
  const mood = face.dataset.face;
  const mouth = {tough: 'M8 17q4-5 8 0', low: 'M8 16q4-3 8 0', okay: 'M8 15h8', good: 'M8 14q4 5 8 0', great: 'M7 13q5 9 10 0Z'}[mood];
  face.innerHTML = `<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="10"/><path d="M8 9h.01M16 9h.01" stroke-width="2.6"/><path d="${mouth}"/></svg>`;
});
// Keep Settings reachable on small screens without crowding the bottom navigation.
const mobileSettings = document.createElement('button');
mobileSettings.className = 'icon-button mobile-settings';
mobileSettings.setAttribute('aria-label', 'Settings and backup');
mobileSettings.innerHTML = svg('settings');
$('.sidebar').append(mobileSettings);
mobileSettings.addEventListener('click', settingsModal);
$('#settings-button').addEventListener('click', settingsModal);
$('#edit-habit').addEventListener('click', () => habitModal());
$('#add-habit').addEventListener('click', () => habitModal(true));
$('#reset-button').addEventListener('click', resetModal);
$('#breathe-button').addEventListener('click', breatheModal);
$('#checkin-button').addEventListener('click', checkinModal);
$('#new-entry').addEventListener('click', () => entryModal());
$('#quick-reflect').addEventListener('click', () => entryModal());
$('#quick-checkin').addEventListener('click', checkinModal);
$('#quick-urge').addEventListener('click', urgeModal);
$('#open-focus').hidden = !hasIPhoneFocus;
$('#open-focus').addEventListener('click', () => nativeHost.postMessage({ action: 'openFocus' }));
$('#edit-intentions').addEventListener('click', intentionsModal);
$('#start-setup').addEventListener('click', () => habitModal());
$('#journal-search').addEventListener('input', event => { journalQuery = event.target.value; renderJournal(); });
$$('[data-journal-filter]').forEach(button => button.addEventListener('click', () => { journalFilter = button.dataset.journalFilter; renderJournal(); }));
$('#habit-select').addEventListener('change', event => selectHabit(event.target.value));
$$('.moods button').forEach(button => button.addEventListener('click', () => { selectedMood = button.dataset.mood; renderCheckin(); }));
window.addEventListener('hashchange', route);
window.addEventListener('storage', event => {
  if (event.key === 'habit-counter.appearance') { applyAppearance(event.newValue || 'system'); return; }
  if (event.key !== STORAGE_KEY) return;
  if ($('#modal').open) closeModal();
  try { state = event.newValue ? validateState(JSON.parse(event.newValue)) : initialState(); selectedMood = null; render(); toast('Progress updated from another tab.'); } catch { toast('Couldn’t read the updated data. Your current view is unchanged.', true); }
});
function refreshDayBoundary() { if (dayKey() !== renderedDay && plannerDate === renderedDay) plannerDate = dayKey(); }
setInterval(() => { if (document.hidden) return; if (dayKey() !== renderedDay) { refreshDayBoundary(); selectedMood = null; render(); } else renderCounter(); }, 1000);
document.addEventListener('visibilitychange', () => { if (!document.hidden) { refreshDayBoundary(); render(); } });
render(); route();
if (nativeHost) {
  window.addEventListener('habit-native-event', event => {
    const detail = event.detail;
    if (['phoneScreenTime','phoneScreenTimeRefresh','phoneSettingsRead','phoneSettingsReports','phoneSettingsSync'].includes(detail.type)) { phoneScreenTime?.event(detail); return; }
    if (detail.type === 'saved' && detail.requestId === nativeSaveId) {
      nativeSavePending = false;
      storageAvailable = detail.success === true;
      if (isMac && ['day-summary','day-focus'].includes(document.activeElement?.id)) { renderStorageStatus(); renderPlanner(); } else render();
      if (!storageAvailable) toast(detail.error || 'Couldn’t save. Export a backup before closing.', true);
    } else if (detail.type === 'pomodoro') {
      pomodoro = detail.snapshot; if (detail.error) { pendingPomoSettings = false; pomodoroError = detail.error; if ($('#pomo-settings-error')) $('#pomo-settings-error').textContent = detail.error; if (currentView === 'planner') toast(detail.error, true); }
      if ($('#pomo-setting-sounds')) { $('#pomo-setting-sounds').checked = pomodoro.settings.sounds !== false; $('#preview-focus-sound').disabled = pomodoro.settings.sounds === false; $('#preview-break-sound').disabled = pomodoro.settings.sounds === false; }
      if ($('#pomo-setting-notifications') && detail.error) $('#pomo-setting-notifications').checked = !!pomodoro.settings.notifications;
      if ($('#pomo-settings-form') && !detail.error && !pomodoro.error && pendingPomoSettings) { pendingPomoSettings = false; closeModal(); }
      renderPomodoro(); renderPlanner(); if (currentView === 'insights') renderInsights();
    } else if (detail.type === 'pomodoroTick') {
      pomodoro.remaining = detail.remaining; renderPomodoroClock();
      const minute = `${dayKey()}-${Math.floor(Date.now()/60000)}`;
      if (minute !== lastInsightMinute) { lastInsightMinute = minute; renderPomodoroTotals(); if (currentView === 'insights') renderFocusInsights(); }
    } else if (detail.type === 'permissionStatus') {
      permissionStatus = detail;
      renderPermissionStatus();
    } else if (detail.type === 'desktopPreferences') {
      desktopPreferences = detail.preferences || {}; renderDesktopPreferences();
      if (detail.message) toast(detail.message, !detail.success);
    } else if (detail.type === 'plannerReminders') {
      plannerReminders = detail.configuration;
      if (detail.success) { toast(plannerReminders.enabled ? 'Morning and evening reminders are set.' : 'Daily planner reminders are off.'); closeModal(); }
      else { if ($('#planner-reminder-error')) $('#planner-reminder-error').textContent = detail.message; else toast(detail.message, true); }
      $('#save-planner-reminders')?.removeAttribute('disabled');
    } else if (detail.type === 'reminder') {
      if (detail.success) { reminder = detail.reminder; toast(reminder.enabled ? 'Your daily reminder is set.' : 'Daily reminder turned off.'); closeModal(); }
      else { const error = $('#reminder-error'); if (error) error.textContent = detail.message; else toast(detail.message, true); }
      $('#save-reminder')?.removeAttribute('disabled');
    } else if (detail.type === 'notice') toast(detail.message, detail.error === true);
    else if (detail.type === 'recoveryList') recoveryModal(detail.copies);
    else if (detail.type === 'import') {
      try { confirmBackupImport(detail.state); }
      catch (error) { toast(error.message, true); }
    } else if (detail.type === 'command') {
      runCommand(detail.action);
    }
  });
  if (!savedDataUnreadable) { persistNative(); render(); }
}

function renderPlan() {
  const h = habit(), days = elapsed(h).days, target = h.targetDays || 30;
  const percent = Math.min(100, Math.floor(days / target * 100));
  $('#personal-plan').innerHTML = `<div class="card-top"><span class="section-label">YOUR BIGGER PICTURE</span><button class="icon-button" id="edit-plan" aria-label="Edit personal plan">${svg('edit')}</button></div><h2>${h.reason ? 'Remember your why.' : 'A little more you.'}</h2><p class="plan-why">${escape(h.reason || 'Choose a reason that matters to you. Come back to it when you need a little direction.')}</p><div class="personal-target"><span><b>${days}</b> / ${target} days</span><small>${percent === 100 ? 'You reached your goal.' : `${percent}% of your personal goal`}</small></div><div class="progress-track"><div style="width:${percent}%"></div></div>${h.replacement ? `<div class="plan-next">${svg('leaf')}<span>When an urge hits, I’ll ${escape(h.replacement.replace(/^I[’']ll /i, ''))}</span></div>` : ''}`;
  $('#edit-plan').addEventListener('click', () => habitModal());
}
function intentionsModal() {
  const h = habit();
  modal(`${modalHeading('Small wins, your way')}<p class="modal-intro">Choose three little things that help you feel more like yourself. You can change them any time.</p><form id="intentions-form">${(h.intentionLabels || DEFAULT_INTENTIONS).map((label,i) => `<label class="field"><span>Intention ${i+1}</span><input id="intention-${i}" value="${escape(label)}" maxlength="80" required></label>`).join('')}<p class="muted">Today’s completion marks stay in place when you rename an intention.</p>${actions('Save my intentions')}</form>`);
  $('#intentions-form').addEventListener('submit', event => {
    event.preventDefault(); const intentionLabels = [0,1,2].map(i => $(`#intention-${i}`).value.trim());
    if (intentionLabels.some(s => !s)) { $('#form-error').textContent = 'Give each intention a short name.'; return; }
    if (habit().id !== h.id) return;
    updateHabit({ ...habit(), intentionLabels }, 'Your intentions, your pace.'); closeModal();
  });
}
function urgeModal() {
  const h = habit();
  modal(`${modalHeading('Notice the moment')}<p class="modal-intro">Logging an urge keeps your streak intact. A pause is something to build on.</p><form id="urge-form"><label class="field"><span>How strong is it? <b id="urge-intensity-value">3 / 5</b></span><input type="range" id="urge-intensity" min="1" max="5" value="3"><small>1 · A passing thought <span class="range-end">5 · Very strong</span></small></label><label class="field"><span>What brought it on? <span class="muted">(optional)</span></span><select id="urge-trigger"><option value="">Choose a trigger</option>${['Stress','Boredom','Feeling lonely','Late-night habits','Social media','Being tired','Something else'].map(t=>`<option>${t}</option>`).join('')}</select></label><label class="field"><span>A note to yourself <span class="muted">(optional)</span></span><textarea id="urge-note" maxlength="12000" placeholder="What was happening? What might help?"></textarea></label><label class="field"><span>Where am I now?</span><select id="urge-outcome"><option value="noted">I’m noticing it</option><option value="passed">The urge has passed</option></select></label>${h.replacement ? `<div class="reason-note">My next step: ${escape(h.replacement)}</div>` : ''}<div class="modal-error" id="form-error" role="alert"></div><div class="modal-actions urge-actions"><button type="submit" name="next" value="breathe" class="button">Save & breathe</button><button type="submit" name="next" value="close" class="button primary">Save this moment</button></div></form>`);
  $('#urge-intensity').addEventListener('input', event => $('#urge-intensity-value').textContent = `${event.target.value} / 5`);
  $('#urge-form').addEventListener('submit', event => {
    event.preventDefault(); if (habit().id !== h.id) return;
    const next = logUrge(habit(), Number($('#urge-intensity').value), $('#urge-trigger').value, $('#urge-note').value, $('#urge-outcome').value);
    const breathe = event.submitter?.value === 'breathe';
    updateHabit(next, 'Moment saved. Your streak keeps going.');
    if (breathe) breatheModal(); else closeModal();
  });
}
function reminderModal() {
  modal(`${modalHeading('A gentle daily reminder')}<p class="modal-intro">One quiet nudge to check in with yourself. Your reminder says “A moment for you” and doesn’t name your habit.</p>${nativeHost ? `<form id="reminder-form"><label class="reminder-toggle"><span><b>Daily check-in reminder</b><small>Once a day, at a time you choose</small></span><input id="reminder-enabled" type="checkbox" role="switch" ${reminder.enabled ? 'checked' : ''}></label><label class="field"><span>Remind me at</span><input id="reminder-time" type="time" value="${escape(reminder.time)}" required></label><p class="modal-error" id="reminder-error" role="alert"></p><div class="modal-actions"><button type="button" class="button" data-close>Cancel</button><button id="save-reminder" type="submit" class="button primary">Save reminder</button></div></form>` : '<p class="reason-note">Daily notifications are available in the iPhone and Mac apps.</p>'}`);
  $('#reminder-form')?.addEventListener('submit', event => {
    event.preventDefault(); $('#save-reminder').disabled = true;
    $('#reminder-error').textContent = '';
    nativeHost.postMessage({ action: 'reminder', enabled: $('#reminder-enabled').checked, time: $('#reminder-time').value });
  });
}

function selectHabit(id) {
  if (!state.habits.some(h => h.id === id)) return;
  selectedMood = null;
  if ($('#modal').open) closeModal();
  save({ ...state, activeId: id });
}
function renderCalendar() {
  const h = habit();
  const cells = calendarMonth(calendarYear, calendarMonthIndex);
  $('#calendar-month').textContent = new Date(calendarYear, calendarMonthIndex, 1).toLocaleDateString(undefined, { month: 'long', year: 'numeric' });
  $('#calendar-next').disabled = calendarYear === new Date().getFullYear() && calendarMonthIndex === new Date().getMonth();
  const moments = new Map();
  journalItems().forEach(item => { const key = item.date || dayKey(item.at); moments.set(key, (moments.get(key) || 0) + 1); });
  Object.entries(state.planner || {}).forEach(([date,plan]) => { if (plan.tasks.length || plan.focus) moments.set(date, (moments.get(date) || 0) + 1); });
  $('#calendar-days').innerHTML = cells.map(cell => {
    const total = moments.get(cell.date) || 0, wins = h.goals[cell.date]?.length || 0;
    const recorded = total > 0 || wins > 0;
    const label = `${formatDate(new Date(`${cell.date}T12:00:00`), { weekday: 'long', year: 'numeric' })}${cell.today ? ', today' : ''}: ${total} recorded moments, ${wins} intentions completed`;
    return `<button class="calendar-day${recorded ? ' has-record' : ''}${cell.today ? ' is-today' : ''}${cell.inMonth ? '' : ' outside'}" data-calendar-date="${cell.date}" aria-label="${escape(label)}" ${cell.today ? 'aria-current="date"' : ''} ${cell.future ? 'disabled' : ''}>${cell.day}</button>`;
  }).join('');
  $$('[data-calendar-date]').forEach(button => button.addEventListener('click', () => dayModal(button.dataset.calendarDate)));
  const inMonth = cells.filter(c => c.inMonth);
  const count = inMonth.filter(c => moments.has(c.date) || h.goals[c.date]?.length).length;
  $('#calendar-summary').textContent = `${count} ${count === 1 ? 'day' : 'days'} with a recorded moment this month`;
}
function dayModal(date) {
  const h = habit();
  const checkin = h.checkins.find(c => c.date === date);
  const wins = h.goals[date] || [];
  const plan = dayPlan(state, date);
  const items = journalItems().filter(e => (e.date || dayKey(e.at)) === date);
  modal(`${modalHeading(date === dayKey() ? 'Your day, so far' : formatDate(new Date(`${date}T12:00:00`), { weekday: 'short', year: 'numeric' }))}<div class="day-summary"><span>${checkin ? `Feeling ${escape(checkin.mood)}` : 'No check-in'}</span><span>${wins.length} / 3 intentions</span></div>${wins.length ? `<p class="reason-note">${wins.map(i => escape(h.intentionLabels[i])).join(' · ')}</p>` : ''}${items.length ? items.map(e => `<article class="day-moment"><div class="entry-meta"><span class="entry-tag">${escape(e.type)}</span><span>${e.plannerDate ? 'Your day' : escape(new Date(e.at).toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' }))}</span></div><p>${escape(e.text)}</p></article>`).join('') : '<p class="modal-intro">No written moments were recorded on this day. Your progress still counts.</p>'}<div class="modal-actions"><button class="button" data-close>Close</button>${date === dayKey() ? '<button class="button primary" id="day-checkin">My check-in</button>' : ''}</div>`);
  $('#day-checkin')?.addEventListener('click', checkinModal);
  if (isMac) {
    const content = document.createElement('div'); content.className = 'day-plan-preview';
    content.innerHTML = `<div class="day-moment"><h3>Your daily plan</h3>${plan.focus ? `<p>${escape(plan.focus)}</p>` : ''}<p>${plan.tasks.filter(t => t.done).length} / ${plan.tasks.length} tasks complete</p><button class="button" id="review-day-plan">Open this day’s planner</button></div>`;
    $('#modal-content .modal-actions').before(content);
    $('#review-day-plan').addEventListener('click', () => { closeModal(); openPlanner(date); });
  }
}
const desktopCommands = [
  ['planner', 'Open my daily planner', 'sun', '⌘ 4'],
  ['tasks', 'Open tasks & focus', 'check', '⌘ 5'],
  ['pomodoroToggle', 'Start / pause Pomodoro', 'sun', '⇧ ⌘ F'],
  ['summary', 'Write my daily summary', 'book', '⇧ ⌘ J'],
  ['checkin', 'Check in for today', 'check', '⌘ D'],
  ['reflect', 'Write a reflection', 'book', '⌘ N'],
  ['urge', 'Log an urge', 'shield', '⇧ ⌘ U'],
  ['breathe', 'Take a breath', 'wind', '⇧ ⌘ B'],
  ['addHabit', 'Add a bad habit', 'plus', '⇧ ⌘ N'],
  ['overview', 'Go to Bad Habits', 'shield', '⌘ 1'],
  ['journal', 'Go to My journal', 'book', '⌘ 2'],
  ['insights', 'Go to Insights', 'chart', '⌘ 3'],
  ['phone', 'iPhone Screen Time', 'phone', '⌘ 6'],
  ['settings', 'Settings & backup', 'settings', '⌘ ,'],
  ['export', 'Export a backup', 'lock', '⇧ ⌘ E'],
];
function runCommand(action) {
  const handlers = { tasks: () => openTasks(), pomodoroToggle: () => sendPomodoro(pomodoro.status === 'running' ? 'pause' : 'start'), planner: () => openPlanner(), morning: () => { openPlanner(); morningModal(); }, summary: () => { openPlanner(); $('#day-summary').focus(); }, plannerReminders: plannerRemindersModal, checkin: checkinModal, reflect: () => entryModal(), urge: urgeModal, breathe: breatheModal, addHabit: () => habitModal(true), settings: settingsModal, export: downloadBackup, quickActions: commandModal };
  if (handlers[action]) handlers[action]();
  else if (['overview', 'journal', 'insights', ...(isMac?['phone']:[])].includes(action)) { closeModal(); location.hash = action; route(); }
  else if (action.startsWith('habit:')) {
    selectHabit(action.slice(6));
    if (isMac) { location.hash = 'overview'; route(); }
  }
}
function commandModal() {
  modal(`${modalHeading('A little less clicking')}<label class="journal-search"><span>${svg('spark')}</span><input id="command-search" placeholder="Find an action or habit…" aria-label="Find an action or habit" role="combobox" aria-autocomplete="list" aria-controls="command-results" aria-expanded="true" autocomplete="off"></label><div id="command-results" class="command-list" role="listbox" aria-label="Quick actions"></div>`);
  const search = $('#command-search');
  let selected = 0, filtered = [];
  const all = [...(isMac ? [['morning', 'Plan my morning targets', 'flag', ''], ['plannerReminders', 'Morning & evening reminders', 'sun', '']] : []), ...desktopCommands, ...state.habits.map(h => [`habit:${h.id}`, `Switch to ${h.name}`, 'leaf', ''])];
  function highlight() {
    $$('#command-results button').forEach((button, index) => button.setAttribute('aria-selected', String(index === selected)));
    if (filtered.length) { search.setAttribute('aria-activedescendant', `command-${selected}`); $(`#command-${selected}`)?.scrollIntoView({ block: 'nearest' }); }
    else search.removeAttribute('aria-activedescendant');
  }
  function draw() {
    filtered = all.filter(([, label]) => label.toLocaleLowerCase().includes(search.value.trim().toLocaleLowerCase()));
    selected = 0;
    $('#command-results').innerHTML = filtered.length ? filtered.map(([action, label, icon, key], i) => `<button id="command-${i}" class="command-option" role="option" aria-selected="${i === 0}" tabindex="-1" data-command="${escape(action)}">${svg(icon)}<span>${escape(label)}</span>${key ? `<kbd>${key}</kbd>` : ''}</button>`).join('') : '<p class="modal-intro">No matches. Try “check in” or a habit name.</p>';
    $$('[data-command]').forEach(button => button.addEventListener('click', () => { closeModal(); runCommand(button.dataset.command); }));
    highlight();
  }
  search.addEventListener('input', draw);
  search.addEventListener('keydown', event => {
    if (['ArrowDown', 'ArrowUp'].includes(event.key)) {
      event.preventDefault();
      if (filtered.length) { selected = (selected + (event.key === 'ArrowDown' ? 1 : -1) + filtered.length) % filtered.length; highlight(); }
    } else if (event.key === 'Enter' && filtered[selected]) { event.preventDefault(); const action = filtered[selected][0]; closeModal(); runCommand(action); }
  });
  draw(); search.focus();
}
function shortcutsModal() {
  modal(`${modalHeading('A few handy shortcuts')}<p class="modal-intro">Use these while ${appName} is active. Press Escape to close any dialog.</p><div class="shortcuts-list"><span>Quick actions</span><kbd>⌘ K</kbd>${desktopCommands.map(([, label,, key]) => `<span>${label}</span><kbd>${key}</kbd>`).join('')}<span>Save an open form</span><kbd>⌘ ↵</kbd></div>`);
}
function recoveryModal(copies) {
  if (!isMac || !Array.isArray(copies)) return;
  modal(`${modalHeading('A little peace of mind')}<p class="modal-intro">Each copy holds your data before the first change on its date. Choose one to review the restore confirmation. Your current data stays in place until you confirm.</p><div>${copies.length ? copies.map(copy => `<div class="recovery-copy"><span>${escape(formatDate(new Date(`${copy.date}T12:00:00`), { year: 'numeric' }))}<small>Before the first change that day</small></span><button class="button" data-recovery="${escape(copy.name)}">Choose copy</button></div>`).join('') : '<p class="reason-note">No recovery copies yet. The first copy appears after you change previously saved data.</p>'}</div><div class="modal-actions"><button class="button" data-close>Close</button></div>`);
  $$('[data-recovery]').forEach(button => button.addEventListener('click', () => nativeHost.postMessage({ action: 'recoveryOpen', name: button.dataset.recovery })));
}
if (isMac) {
  $$('.desktop-only:not(.view)').forEach(el => el.hidden = false);
  $('.brand').href = '#planner';
  $('#overview-view').prepend($('.habit-toolbar'));
  $('#habit-history-panel').append($('#habit-insights'));
  $('#add-habit').innerHTML = `${svg('plus')}Add bad habit`;
  $('label[for=habit-select]').textContent = 'Bad habit to track';
  const habitReminder = document.createElement('button');
  habitReminder.className = 'text-button';
  habitReminder.textContent = 'Check-in reminder';
  habitReminder.addEventListener('click', reminderModal);
  $('#add-habit').before(habitReminder);
  setupPlanner();
  $('#desktop-search').addEventListener('click', commandModal);
  const changeMonth = step => {
    const date = new Date(calendarYear, calendarMonthIndex + step, 1);
    if (date > new Date()) return;
    calendarYear = date.getFullYear(); calendarMonthIndex = date.getMonth(); renderCalendar();
  };
  $('#calendar-prev').addEventListener('click', () => changeMonth(-1));
  $('#calendar-next').addEventListener('click', () => changeMonth(1));
  $('#calendar-now').addEventListener('click', () => { calendarYear = new Date().getFullYear(); calendarMonthIndex = new Date().getMonth(); renderCalendar(); });
  document.addEventListener('keydown', event => {
    if (event.metaKey && event.key.toLowerCase() === 'k') { event.preventDefault(); commandModal(); }
    if (event.metaKey && event.key === 'Enter' && $('#modal').open) {
      const form = $('#modal form');
      if (form && !form.querySelector('button[type=submit]')?.disabled) { event.preventDefault(); form.requestSubmit(); }
    }
  });
}

function openPlanner(date = dayKey(), view = 'planner') {
  if (!isMac || !/^\d{4}-\d{2}-\d{2}$/.test(date) || dayKey(new Date(`${date}T12:00:00`)) !== date) return;
  plannerDate = date;
  location.hash = view; route(); renderPlanner();
}
function saveDay(patch, date = plannerDate, message, editorOnly = false) { save(updateDayPlan(state, date, patch), message, false, editorOnly); }
function renderPlanner() {
  const activeTaskControl = document.activeElement?.closest('#day-tasks button');
  const focusAttribute = ['data-toggle-task','data-priority-task','data-edit-task','data-focus-task'].find(name => activeTaskControl?.hasAttribute(name));
  const focusedTaskId = focusAttribute && activeTaskControl.getAttribute(focusAttribute);
  const plan = dayPlan(state, plannerDate), done = plan.tasks.filter(t => t.done).length;
  $('#planner-date').value = plannerDate;
  $('#tasks-date').value = plannerDate;
  const focus = $('#day-focus'), summary = $('#day-summary');
  if (document.activeElement !== focus || focus.dataset.date !== plannerDate) focus.value = plan.focus;
  if (document.activeElement !== summary || summary.dataset.date !== plannerDate) summary.value = plan.summary;
  focus.dataset.date = summary.dataset.date = plannerDate;
  if ($('#new-task').dataset.date !== plannerDate) { $('#new-task').value = ''; $('#new-task').dataset.date = plannerDate; }
  summary.disabled = plannerDate > dayKey();
  $$('[data-summary-prompt]').forEach(button => button.disabled = summary.disabled);
  $('#finish-day').disabled = plannerDate > dayKey();
  $('#finish-day').innerHTML = `${plan.summarySavedAt ? 'Daily summary saved' : 'Save my daily summary'}${svg('check')}`;
  $('#day-focus-status').textContent = plan.focus ? (nativeSavePending ? 'Saving…' : storageAvailable ? 'Target saved' : 'Not saved — export a backup') : 'Start with one thing that matters.';
  $('#summary-status').textContent = !storageAvailable ? 'Not saved — export a backup' : nativeSavePending ? 'Saving to this Mac…' : plan.summarySavedAt ? 'Day reviewed · saved on this Mac' : plan.summary ? 'Draft saved on this Mac' : plannerDate > dayKey() ? 'Write your summary when this day arrives.' : 'Your words stay on this Mac.';
  const words = plan.summary.trim() ? plan.summary.trim().split(/\s+/).length : 0;
  $('#summary-word-count').textContent = `${words} ${words === 1 ? 'word' : 'words'}`;
  $('#task-progress').textContent = `${done} / ${plan.tasks.length} done`;
  $('#task-progress-bar').style.width = `${plan.tasks.length ? done / plan.tasks.length * 100 : 0}%`;
  $$('[data-task-filter]').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.taskFilter === taskFilter)));
  const tasks = [...plan.tasks].filter(t => (taskFilter === 'all' || (taskFilter === 'done' ? t.done : taskFilter === 'priority' ? t.priority && !t.done : !t.done)) && `${t.title} ${t.notes || ''}`.toLocaleLowerCase().includes(taskQuery.toLocaleLowerCase())).sort((a,b) => Number(a.done) - Number(b.done) || Number(b.priority) - Number(a.priority));
  $('#day-tasks').innerHTML = tasks.length ? tasks.map(t => {
    const completed = (pomodoro.sessions || []).filter(session => session.taskId === t.originId).length;
    return `<div class="task-row${t.done ? ' complete' : ''}${t.priority ? ' priority' : ''}${pomodoro.taskId === t.originId && ['running','paused'].includes(pomodoro.status) ? ' focused' : ''}"><button class="task-checkbox" data-toggle-task="${escape(t.id)}" aria-label="${escape(t.done ? `Mark ${t.title} as unfinished` : `Complete ${t.title}`)}" aria-pressed="${t.done}">${t.done ? svg('check') : ''}</button><button class="task-title" data-edit-task="${escape(t.id)}"><span>${escape(t.title)}</span>${t.notes ? `<p>${escape(t.notes.slice(0,140))}${t.notes.length>140?'…':''}</p>` : ''}<small>${t.priority ? '<b>PRIORITY</b><i>·</i>' : ''}${completed} / ${t.estimate || 1} focus sessions</small></button><div class="task-row-actions">${!t.done ? `<button class="task-focus-button" data-focus-task="${escape(t.id)}" aria-label="Focus on ${escape(t.title)}">${svg('arrow')}<span>Focus</span></button>` : ''}<button class="task-priority" data-priority-task="${escape(t.id)}" aria-label="${escape(t.priority ? `Remove priority from ${t.title}` : `Prioritize ${t.title}`)}" aria-pressed="${t.priority}">${svg('star')}</button></div></div>`;
  }).join('') : `<div class="task-empty"><span>${svg('flag')}</span><h3>${plan.tasks.length ? 'A little breathing room.' : 'Your next good thing starts here.'}</h3><p>${plan.tasks.length ? 'No tasks match this view. Try another filter or search.' : 'Add a task, choose a priority, and give it one focused session.'}</p></div>`;
  $$('[data-toggle-task]').forEach(button => button.addEventListener('click', () => changeTask(button.dataset.toggleTask, t => ({ ...t, done: !t.done }))));
  $$('[data-priority-task]').forEach(button => button.addEventListener('click', () => changeTask(button.dataset.priorityTask, t => ({ ...t, priority: !t.priority }))));
  $$('[data-edit-task]').forEach(button => button.addEventListener('click', () => taskModal(button.dataset.editTask)));
  $$('[data-focus-task]').forEach(button => button.addEventListener('click', () => { const task = dayPlan(state,plannerDate).tasks.find(t => t.id === button.dataset.focusTask); if (task) sendPomodoro('focusTask',{taskId:task.originId,taskDate:plannerDate,taskTitle:task.title}); }));
  if (focusAttribute) $$(`#day-tasks [${focusAttribute}]`).find(button => button.getAttribute(focusAttribute) === focusedTaskId)?.focus({ preventScroll: true });
  $('#day-task-completed').textContent = done;
  $('#day-task-open').textContent = plan.tasks.length - done;
  const pending = plan.tasks.filter(task => !task.done);
  const next = [...pending.filter(task => task.priority), ...pending.filter(task => !task.priority)].slice(0, 3);
  $('#day-next-tasks').hidden = next.length === 0;
  $('#day-next-tasks').innerHTML = next.map(task =>
    `<li>${svg(task.priority ? 'star' : 'circle')}<span>${escape(task.title)}</span></li>`
  ).join('');
  $('#day-next-empty').hidden = next.length > 0;
  $('#day-next-empty').textContent = plan.tasks.length ? 'All tasks for this day are done.' : 'Add a task to give your plan a next step.';
  $('#tasks-header-count').textContent = `${plan.tasks.length - done} ${plan.tasks.length - done === 1 ? 'task' : 'tasks'} left · ${done} complete`;
  renderPomodoro();
  const history = Object.entries(state.planner || {}).filter(([date,p]) => date <= dayKey() && (p.focus || p.tasks.length || p.summary)).sort(([a],[b]) => b.localeCompare(a)).slice(0,14);
  $('#planner-history-list').innerHTML = history.length ? history.map(([date,p]) => `<button class="day-history-card${date === plannerDate ? ' selected' : ''}" data-plan-date="${date}"><span>${escape(formatDate(new Date(`${date}T12:00:00`), { weekday: 'short' }))}${date === dayKey() ? ' · TODAY' : ''}</span><h3>${escape(p.focus || 'One day at a time.')}</h3><p>${p.tasks.filter(t => t.done).length} / ${p.tasks.length} tasks · ${p.summarySavedAt ? 'Summary saved' : p.summary ? 'Summary draft' : 'No summary yet'}</p>${p.summary ? `<small>${escape(p.summary.slice(0,140))}${p.summary.length > 140 ? '…' : ''}</small>` : ''}</button>`).join('') : '<p class="muted">Your daily plans and summaries will collect here. Use the date picker to revisit any day.</p>';
  $$('[data-plan-date]').forEach(button => button.addEventListener('click', () => openPlanner(button.dataset.planDate)));
}
function changeTask(id, change, date = plannerDate) {
  const plan = dayPlan(state, date);
  saveDay({ tasks: plan.tasks.map(t => t.id === id ? change(t) : t) }, date);
}
function taskModal(id) {
  const date = plannerDate, task = dayPlan(state,date).tasks.find(t => t.id === id);
  if (!task) return;
  modal(`${modalHeading('Make it a little clearer')}<form id="edit-task-form"><label class="field"><span>Task</span><input id="edit-task-title" maxlength="240" required value="${escape(task.title)}"></label><label class="field"><span>A little detail <span class="muted">(optional)</span></span><textarea id="edit-task-notes" maxlength="2000" placeholder="What does done look like?">${escape(task.notes || '')}</textarea></label><label class="field"><span>Estimated focus sessions</span><input id="edit-task-estimate" type="number" min="1" max="12" required value="${task.estimate || 1}"><small>One session uses your chosen Pomodoro duration.</small></label><label class="reminder-toggle"><span>Make this a priority</span><input id="edit-task-priority" type="checkbox" ${task.priority ? 'checked' : ''}></label>${actions('Save task')}</form><button class="text-button delete-task" id="delete-task">Delete task</button>`);
  $('#edit-task-form').addEventListener('submit', event => {
    event.preventDefault(); const title = $('#edit-task-title').value.trim();
    if (!title) { $('#form-error').textContent = 'Give this task a short name.'; return; }
    const priority = $('#edit-task-priority').checked;
    const notes = $('#edit-task-notes').value.trim(), estimate = Number($('#edit-task-estimate').value);
    if (!Number.isInteger(estimate) || estimate < 1 || estimate > 12) { $('#form-error').textContent = 'Estimate between 1 and 12 focus sessions.'; return; }
    changeTask(id, t => ({ ...t, title, priority, notes, estimate }), date); closeModal();
  });
  $('#delete-task').addEventListener('click', () => {
    modal(`${modalHeading('Remove this task?')}<p class="modal-intro">${escape(task.title)}</p><div class="modal-actions"><button class="button" data-close>Keep task</button><button class="button danger" id="confirm-delete-task">Delete task</button></div>`);
    $('#confirm-delete-task').addEventListener('click', () => { saveDay({ tasks: dayPlan(state,date).tasks.filter(t => t.id !== id) }, date, 'Task removed.'); closeModal(); });
  });
}
function morningModal() {
  const date = plannerDate, plan = dayPlan(state,date);
  modal(`${modalHeading('Give your day a direction')}<p class="modal-intro">Choose a main target and write a short list. Put one task on each line. These will be added to your existing tasks.</p><form id="morning-form"><label class="field"><span>My main target</span><input id="morning-focus" maxlength="240" placeholder="One thing that would make today worthwhile" value="${escape(plan.focus)}"></label><label class="field"><span>My tasks, one per line</span><textarea id="morning-tasks" rows="7" maxlength="24000" placeholder="Finish the important project\nTake a walk\nCall someone I care about"></textarea><small>You can star your priorities after adding them.</small></label>${actions('Save my morning plan')}</form>`);
  $('#morning-form').addEventListener('submit', event => {
    event.preventDefault();
    const lines = $('#morning-tasks').value.split('\n').map(s => s.trim()).filter(Boolean);
    if (!$('#morning-focus').value.trim() && !lines.length && !dayPlan(state,date).tasks.length) { $('#form-error').textContent = 'Choose a main target or add a task to give this day a direction.'; return; }
    if (lines.some(s => s.length > 240) || dayPlan(state,date).tasks.length + lines.length > 100) { $('#form-error').textContent = 'Keep tasks under 240 characters, with up to 100 tasks per day.'; return; }
    let next = updateDayPlan(state, date, { focus: $('#morning-focus').value.trim() });
    for (const title of lines) next = addDayTask(next,date,title);
    save(next, 'Your day has a little direction.'); closeModal();
  });
}
function carryTasksModal() {
  const destination = plannerDate;
  const earlier = Object.keys(state.planner || {}).filter(d => d < destination && dayPlan(state,d).tasks.some(t => !t.done)).sort().reverse();
  modal(`${modalHeading('Bring the useful things forward')}<p class="modal-intro">Copy unfinished tasks from an earlier day. The original day stays in your history, and the same task won’t be copied here twice.</p>${earlier.length ? `<form id="carry-form"><label class="field"><span>From this day</span><select id="carry-source">${earlier.map(date => `<option value="${date}">${escape(formatDate(new Date(`${date}T12:00:00`),{year:'numeric'}))}</option>`).join('')}</select></label><div id="carry-options"></div>${actions('Bring selected tasks forward')}</form>` : '<p class="reason-note">No unfinished tasks from earlier days yet.</p>'}`);
  const draw = () => {
    const existing = new Set(dayPlan(state,destination).tasks.map(t => t.originId));
    $('#carry-options').innerHTML = dayPlan(state,$('#carry-source').value).tasks.filter(t => !t.done).map(t => `<label class="carry-option"><input type="checkbox" value="${escape(t.id)}" ${existing.has(t.originId) ? 'disabled' : 'checked'}><span>${escape(t.title)}${existing.has(t.originId) ? '<small>Already in this day</small>' : ''}</span></label>`).join('');
  };
  if (!earlier.length) return;
  draw(); $('#carry-source').addEventListener('change', draw);
  $('#carry-form').addEventListener('submit', event => {
    event.preventDefault();
    try { save(bringTasksForward(state,$('#carry-source').value,destination,$$('#carry-options input:checked:not(:disabled)').map(i => i.value)), 'Tasks brought forward.'); closeModal(); }
    catch (error) { $('#form-error').textContent = error.message; }
  });
}
function setupPlanner() {
  const moveDay = step => { const d = new Date(`${plannerDate}T12:00:00`); d.setDate(d.getDate()+step); openPlanner(dayKey(d),currentView === 'tasks' ? 'tasks' : 'planner'); };
  $('#planner-prev').addEventListener('click', () => moveDay(-1));
  $('#planner-next').addEventListener('click', () => moveDay(1));
  $('#planner-today').addEventListener('click', () => openPlanner());
  $('#planner-date').addEventListener('change', event => openPlanner(event.target.value));
  $('#day-open-tasks').addEventListener('click', () => openTasks(plannerDate));
  $('#day-plan-morning').addEventListener('click', morningModal);
  $('#day-timer-toggle').addEventListener('click', () => sendPomodoro(pomodoro.status === 'running' ? 'pause' : 'start'));
  $('#tasks-prev').addEventListener('click', () => moveDay(-1));
  $('#tasks-next').addEventListener('click', () => moveDay(1));
  $('#tasks-today').addEventListener('click', () => openTasks());
  $('#tasks-date').addEventListener('change', event => openTasks(event.target.value));
  $('#task-search').addEventListener('input', event => { taskQuery = event.target.value; renderPlanner(); });
  setupPomodoro();
  $$('[data-insight-range]').forEach(button=>button.addEventListener('click',()=>{ insightRange=Number(button.dataset.insightRange); renderFocusInsights(); }));
  $('#insight-open-day').addEventListener('click',()=>openTasks(insightDay));
  $('#planner-reminders').addEventListener('click', plannerRemindersModal);
  $('#day-focus-form').addEventListener('submit', event => { event.preventDefault(); saveDay({ focus: $('#day-focus').value.trim() }); $('#day-focus').blur(); });
  $('#day-focus').addEventListener('input', event => saveDay({ focus: event.target.value }, event.target.dataset.date, undefined, true));
  $('#add-task-form').addEventListener('submit', event => {
    event.preventDefault(); const input = $('#new-task');
    try { save(addDayTask(state,plannerDate,input.value)); input.value = ''; $('#task-error').textContent = ''; input.focus(); }
    catch (error) { $('#task-error').textContent = error.message; }
  });
  $$('[data-task-filter]').forEach(button => button.addEventListener('click', () => { taskFilter = button.dataset.taskFilter; renderPlanner(); }));
  $('#plan-morning').addEventListener('click', morningModal);
  $('#carry-tasks').addEventListener('click', carryTasksModal);
  $('#day-summary').addEventListener('input', event => { $('#summary-error').textContent = ''; saveDay({ summary: event.target.value, summarySavedAt: 0 }, event.target.dataset.date, undefined, true); });
  $$('[data-summary-prompt]').forEach(button => button.addEventListener('click', () => {
    const input = $('#day-summary'); if (input.disabled) return;
    input.value += `${input.value ? '\n\n' : ''}${button.dataset.summaryPrompt}\n`;
    input.value = input.value.slice(0,20000); input.focus(); input.dispatchEvent(new Event('input'));
  }));
  $('#finish-day').addEventListener('click', () => {
    if (!$('#day-summary').value.trim()) { $('#summary-error').textContent = 'Write a few words about your day first.'; $('#day-summary').focus(); return; }
    saveDay({ summary: $('#day-summary').value, summarySavedAt: Date.now() }, plannerDate, 'Your day, kept in your own words.');
  });
  const summaryFilter = document.createElement('button'); summaryFilter.dataset.journalFilter = 'Daily summary'; summaryFilter.setAttribute('aria-pressed','false'); summaryFilter.textContent = 'Daily summaries';
  summaryFilter.addEventListener('click', () => { journalFilter = 'Daily summary'; renderJournal(); }); $('.journal-filters').append(summaryFilter);
}
function permissionsModal(initialStep = 0, review = false) {
  if (!isMac) return;
  const permission = (key, icon, title, reason) => `
    <article class="permission-row">
      <span class="permission-icon" data-icon="${icon}"></span>
      <div><h3>${title}</h3><p>${reason}</p></div>
      <button type="button" class="button" data-permission="${key}"></button>
    </article>`;
  modal(`<section id="permission-setup">
    <div class="setup-brand"><span data-icon="scope"></span>FocoNow</div>
    <ol class="setup-steps" aria-label="Setup progress">
      <li><span>01</span> Workspace</li><li><span>02</span> Alerts &amp; login</li><li><span>03</span> Screen Time</li>
    </ol>
    <section class="setup-panel" data-setup-step="0" hidden>
      <div class="permission-intro">
        <span class="permission-kicker">${svg('lock')} 100% LOCAL APP DATA</span>
        <h2 tabindex="-1">Welcome to FocoNow</h2>
        <p>A daily workspace for your priorities, focus sessions, and reflections. Your records stay on this Mac, and you can work offline.</p>
      </div>
      <div class="setup-workflow">
        <article><span data-icon="sun"></span><h3>Plan in My Day</h3><p>Pick a priority and see what’s next.</p></article>
        <article><span data-icon="clock"></span><h3>Focus on a task</h3><p>Use the Pomodoro from the app or menu bar.</p></article>
        <article><span data-icon="book"></span><h3>Review your day</h3><p>Write in your journal and see where your time went.</p></article>
      </div>
      <p class="permission-note">You can use the workspace right away. The next two steps explain optional access and what it enables.</p>
    </section>
    <section class="setup-panel" data-setup-step="1" hidden>
      <div class="permission-intro">
        <span class="permission-kicker">OPTIONAL · EVERYDAY CONVENIENCE</span>
        <h2 tabindex="-1">Make it part of your day</h2>
        <p>Choose if you’d like FocoNow to alert you or be ready when you sign in.</p>
      </div>
      ${permission('notifications', 'clock', 'Notifications', 'Show a macOS alert when a focus or break interval ends. You can also schedule daily reminders later.')}
      ${permission('launchAtLogin', 'arrow', 'Open at login', 'Start FocoNow when you sign in so the menu bar controls are ready.')}
      <p class="permission-note">Focus alarms can play while FocoNow is running. macOS notifications are a separate option.</p>
    </section>
    <section class="setup-panel" data-setup-step="2" hidden>
      <div class="permission-intro">
        <span class="permission-kicker">OPTIONAL · IPHONE SCREEN TIME</span>
        <h2 tabindex="-1">See your phone time on Mac</h2>
        <p>Apple syncs Screen Time between your devices. FocoNow can read it from your Mac using either source below.</p>
      </div>
      ${permission('accessibility', 'phone', 'Accessibility', 'Read the report you open in System Settings and move between report dates. Turn on FocoNow under Accessibility.')}
      ${permission('fullDiskAccess', 'lock', 'Full Disk Access', 'Read protected activity files for the synced activity source. This is a broad Mac permission.')}
      <p id="synced-access-status" class="permission-note" role="status" hidden></p>
      <p class="permission-note">Imported reports stay on your Mac. You can revisit these choices later in Settings &amp; backup.</p>
    </section>
    <div class="setup-actions">
      <button type="button" class="text-button" id="permissions-skip">${review ? 'Close setup' : 'Skip setup'}</button>
      <div>
        <button type="button" class="button" id="permissions-back" hidden>Back</button>
        <button type="button" class="button primary" id="permissions-next"><span></span>${svg('arrow')}</button>
      </div>
    </div>
  </section>`);
  const setup = $('#permission-setup');
  const request = (operation, extra = {}) => nativeHost.postMessage({ action: 'permissionSetup', operation, ...extra });
  const panels = [...setup.querySelectorAll('[data-setup-step]')];
  const steps = [...setup.querySelectorAll('.setup-steps li')];
  let currentStep = 0;
  function showStep(index) {
    currentStep = index;
    panels.forEach((panel, i) => { panel.hidden = i !== index; });
    steps.forEach((step, i) => {
      if (i === index) step.setAttribute('aria-current', 'step');
      else step.removeAttribute('aria-current');
    });
    $('#permissions-back').hidden = index === 0;
    $('#permissions-next span').textContent = index === panels.length - 1 ? 'Open FocoNow' : 'Continue';
    const heading = panels[index].querySelector('h2');
    $('#modal').setAttribute('aria-label', heading.textContent);
    heading.focus({ preventScroll: true });
    $('#modal').scrollTop = 0;
    if (!review) request('progress', { step: index });
    checkPermissionStatus();
  }
  function checkPermissionStatus() {
    delete permissionStatus.syncedAccess;
    renderPermissionStatus();
    request('show', { step: currentStep });
  }
  function finish() {
    if (!review) request('finish');
    closeModal();
  }
  setup.addEventListener('click', event => {
    const button = event.target.closest('[data-permission]');
    if (!button || button.disabled) return;
    if (button.dataset.operation === 'checkSyncedAccess') checkPermissionStatus();
    else request(button.dataset.operation);
  });
  $('#permissions-back').addEventListener('click', () => showStep(currentStep - 1));
  $('#permissions-next').addEventListener('click', () => currentStep < panels.length - 1 ? showStep(currentStep + 1) : finish());
  $('#permissions-skip').addEventListener('click', finish);
  $('#modal').addEventListener('close', () => request('dismiss'), { once: true });
  showStep([0, 1, 2].includes(initialStep) ? initialStep : 0);
}

function renderPermissionStatus() {
  if (!$('#permission-setup')) return;
  const { notifications, timerAlerts, accessibility, launchAtLogin, loginApproval, syncedAccess } = permissionStatus;
  const accessStates = {
    accessible: ['Access confirmed', null, ''],
    blocked: ['Open Settings', 'fullDiskAccess', 'macOS blocked access to the synced activity files. Enable FocoNow in Full Disk Access, then quit and reopen the app.'],
    unavailable: ['Check again', 'checkSyncedAccess', 'The synced activity files are unavailable on this Mac. You can use the Settings report instead.'],
    unverified: ['Check again', 'checkSyncedAccess', 'FocoNow couldn’t verify access to the synced activity files.'],
  };
  const [accessLabel, accessAction, accessMessage] = accessStates[syncedAccess] || ['Checking…', null, ''];
  const accessStatus = $('#synced-access-status');
  accessStatus.textContent = accessMessage;
  accessStatus.hidden = !accessMessage;
  const states = {
    notifications: !notifications ? ['Checking…', null] : notifications === 'denied' ? ['Open Settings', 'notificationSettings'] :
      notifications === 'allowed' && timerAlerts ? ['Enabled', null] : ['Enable timer alerts', 'notifications'],
    launchAtLogin: launchAtLogin === undefined ? ['Checking…', null] : loginApproval ? ['Open Login Items', 'loginSettings'] :
      launchAtLogin ? ['Enabled', null] : ['Enable', 'launchAtLogin'],
    accessibility: accessibility === undefined ? ['Checking…', null] : accessibility ? ['Allowed', null] : ['Open Settings', 'accessibility'],
    fullDiskAccess: [accessLabel, accessAction],
  };
  for (const [key, [label, operation]] of Object.entries(states)) {
    const button = $(`[data-permission="${key}"]`);
    button.textContent = label;
    button.dataset.operation = operation || '';
    button.disabled = !operation;
    button.setAttribute('aria-label', `${button.closest('article').querySelector('h3').textContent}: ${label}`);
  }
}

function renderDesktopPreferences() {
  const container = $('#desktop-preferences'); if (!container) return;
  container.innerHTML = `<div class="settings-section"><h3>Permissions &amp; setup</h3><p>Review the optional macOS access for alerts, startup, and iPhone Screen Time.</p><button class="button" id="open-permission-setup">Review permissions</button></div><div class="settings-section"><h3>macOS desktop widgets</h3><p>Right-click your desktop → Edit Widgets → search FocoNow. Choose Focus timer, Today’s tasks, or Bad habit streak, then drag one onto your desktop.</p><button class="button" id="reload-native-widgets">Refresh desktop widgets</button></div><label class="reminder-toggle"><span><b>Open at login</b><small>Keep your planner a click away after restarting your Mac.</small></span><input id="launch-at-login" type="checkbox" role="switch" ${desktopPreferences.launchAtLogin ? 'checked' : ''}></label><p>${desktopPreferences.requiresApproval ? 'macOS needs your approval in Login Items.' : 'Closing the window keeps the menu bar app running. Quit exits it.'}</p>${desktopPreferences.requiresApproval ? '<button class="button" id="login-settings">Open Login Items</button>' : ''}<label class="reminder-toggle"><span><b>Floating mini panel (optional)</b><small>A separate compact window with play/pause controls. ⇧⌘W to show or hide.</small></span><input id="desktop-widget-visible" type="checkbox" role="switch" ${desktopPreferences.widgetVisible ? 'checked' : ''}></label><label class="reminder-toggle"><span><b>Keep mini panel above windows</b><small>Turn off to keep it behind your work, on the desktop.</small></span><input id="desktop-widget-pinned" type="checkbox" role="switch" ${desktopPreferences.widgetPinned ? 'checked' : ''}></label><label class="reminder-toggle"><span><b>Dock glance</b><small>Minutes left while the timer runs, Ⅱ when paused, ✓ when finished. Otherwise, your unfinished task count.</small></span><input id="desktop-dock-badge" type="checkbox" role="switch" ${desktopPreferences.dockBadge !== false ? 'checked' : ''}></label><p>The mini panel runs while FocoNow is open. Native desktop widgets are available through macOS’s Edit Widgets gallery.</p><div class="modal-actions"><button class="button" id="desktop-widget-reset">Reset mini panel position</button><button class="button" id="settings-planner-reminders">Morning & evening reminders</button></div>`;
  $('#launch-at-login').addEventListener('change', event => { event.target.disabled = true; nativeHost.postMessage({ action: 'launchAtLogin', enabled: event.target.checked }); });
  for (const [id, key] of [['desktop-widget-visible', 'visible'], ['desktop-widget-pinned', 'pinned'], ['desktop-dock-badge', 'dockBadge']]) {
    $(`#${id}`).addEventListener('change', event => nativeHost.postMessage({ action: 'desktopWidget', [key]: event.target.checked }));
  }
  $('#open-permission-setup').addEventListener('click', () => permissionsModal(1, true));
  $('#reload-native-widgets').addEventListener('click', () => nativeHost.postMessage({ action: 'reloadNativeWidgets' }));
  $('#desktop-widget-reset').addEventListener('click', () => nativeHost.postMessage({ action: 'desktopWidget', resetPosition: true }));
  $('#login-settings')?.addEventListener('click', () => nativeHost.postMessage({ action: 'loginSettings' }));
  $('#settings-planner-reminders').addEventListener('click', plannerRemindersModal);
}
function plannerRemindersModal() {
  modal(`${modalHeading('A little rhythm for your day')}<p class="modal-intro">A morning nudge to choose your targets. An evening moment to write about your day. Notifications never include your tasks or notes.</p><form id="planner-reminders-form"><label class="reminder-toggle"><span><b>Morning & evening reminders</b><small>Two gentle reminders, every day</small></span><input id="planner-reminders-enabled" type="checkbox" role="switch" ${plannerReminders.enabled ? 'checked' : ''}></label><div class="reminder-time-grid"><label class="field"><span>Plan my morning</span><input id="planner-morning-time" type="time" value="${escape(plannerReminders.morning)}" required></label><label class="field"><span>Write my day summary</span><input id="planner-evening-time" type="time" value="${escape(plannerReminders.evening)}" required></label></div><p class="modal-error" id="planner-reminder-error" role="alert"></p><div class="modal-actions"><button type="button" class="button" data-close>Cancel</button><button type="submit" id="save-planner-reminders" class="button primary">Save reminders</button></div></form>`);
  $('#planner-reminders-form').addEventListener('submit', event => {
    event.preventDefault(); $('#save-planner-reminders').disabled = true;
    nativeHost.postMessage({ action: 'plannerReminders', enabled: $('#planner-reminders-enabled').checked, morning: $('#planner-morning-time').value, evening: $('#planner-evening-time').value });
  });
}

function openTasks(date = dayKey()) { openPlanner(date,'tasks'); }
function sendPomodoro(operation, extra = {}) {
  if (!isMac) return;
  pomodoroError = ''; $('#pomo-error').textContent = '';
  if (operation === 'settings') pendingPomoSettings = true;
  nativeHost.postMessage({action:'pomodoro',operation,...extra});
}
function renderPomodoroClock() {
  const seconds = Math.max(0,Number(pomodoro.remaining) || 0), active = ['running','paused'].includes(pomodoro.status);
  $('#pomo-clock').textContent = `${String(Math.floor(seconds/60)).padStart(2,'0')}:${String(seconds%60).padStart(2,'0')}`;
  $('#pomo-ring-progress').style.strokeDashoffset = 678.584 * (1 - Math.min(1,seconds/(pomodoro.duration || 1500)));
  $('#pomo-state').textContent = pomodoro.status === 'running' ? 'IN THE MOMENT' : pomodoro.status === 'paused' ? 'TAKE YOUR TIME' : pomodoro.status === 'completed' ? 'A LITTLE PROGRESS, MADE' : 'MAKE A LITTLE SPACE';
  $('.pomodoro-panel').dataset.status = pomodoro.status;
  $('#pomo-start-label').textContent = pomodoro.status === 'running' ? 'Pause' : pomodoro.status === 'paused' ? 'Resume' : pomodoro.status === 'completed' ? `Start ${pomodoro.nextPhase === 'work' ? 'focus' : pomodoro.nextPhase === 'long' ? 'long break' : 'short break'}` : pomodoro.phase === 'work' ? 'Start focus' : 'Start break';
  $('#pomo-message').textContent = pomodoro.status === 'completed' ? (pomodoro.phase === 'work' ? 'That focus session is yours. Take a breath before the next.' : 'A little reset. Start again when you’re ready.') : pomodoro.status === 'paused' ? 'Your time is safe here. Resume when you’re ready.' : pomodoro.phase === 'work' ? 'One task. One clear stretch of time.' : 'Step away for a moment. You’ve made room for it.';
  const every = pomodoro.settings?.every || 4;
  const session = pomodoro.status === 'completed' && pomodoro.phase === 'work' ? (pomodoro.cycle-1)%every+1 : pomodoro.cycle%every+1;
  $('#pomo-cycle').textContent = `${pomodoro.phase === 'work' ? 'Session' : 'Next focus'} ${session} of ${every}`;
  $$('[data-pomo-phase]').forEach(button => { button.setAttribute('aria-pressed',String(button.dataset.pomoPhase === pomodoro.phase)); button.disabled = active; });
  $('#pomo-start').disabled = !!pomodoro.error;
  $('#day-timer-clock').textContent = $('#pomo-clock').textContent;
  $('#day-timer-toggle').textContent = $('#pomo-start-label').textContent;
  $('#day-timer-toggle').disabled = !!pomodoro.error;
  const phase = pomodoro.phase === 'work' ? 'Focus' : pomodoro.phase === 'long' ? 'Long break' : 'Short break';
  const status = { running: 'running', paused: 'paused', completed: 'complete' }[pomodoro.status];
  $('#day-timer-state').textContent = status ? `${phase} · ${status}` : `${phase} timer`;
  $('#pomo-reset').disabled = !!pomodoro.error;
}
function renderPomodoro() {
  renderPomodoroClock();
  const plan = dayPlan(state,plannerDate), available = plan.tasks.filter(t=>!t.done);
  const selection = $('#pomo-task'), priorFocus = document.activeElement === selection;
  const signature = JSON.stringify([plannerDate,available.map(t=>[t.originId,t.title]),pomodoro.taskId,pomodoro.taskTitle]);
  if (!priorFocus && selection.dataset.signature !== signature) {
    selection.innerHTML = `<option value="">An open focus session</option>${available.map(t=>`<option value="${escape(t.originId)}">${escape(t.title)}</option>`).join('')}${pomodoro.taskId && !available.some(t=>t.originId===pomodoro.taskId) ? `<option value="${escape(pomodoro.taskId)}">${escape(pomodoro.taskTitle || 'Saved task')}</option>` : ''}`;
    selection.value = pomodoro.taskId || ''; selection.dataset.signature = signature;
  }
  selection.disabled = ['running','paused'].includes(pomodoro.status) || !!pomodoro.error;
  $('#pomo-error').textContent = pomodoroError || pomodoro.error || '';
  const sessions = (pomodoro.sessions || []).filter(s=>dayKey(s.endedAt) === plannerDate);
  renderPomodoroTotals();
  $('#focus-session-count').textContent = sessions.length;

  $('#focus-session-dots').innerHTML = Array.from({length:Math.min(12,Math.max(4,sessions.length))},(_,i)=>`<i class="${i<sessions.length?'filled':''}"></i>`).join('');
  const focused = dayPlan(state,pomodoro.taskDate || plannerDate).tasks.find(t=>t.originId === pomodoro.taskId && !t.done);
  $('#pomo-complete-task').hidden = !(focused && pomodoro.phase === 'work' && pomodoro.status === 'completed');
}
function pomodoroSettingsModal() {
  const settings = pomodoro.settings || {work:25,short:5,long:15,every:4}, active = ['running','paused'].includes(pomodoro.status);
  modal(`${modalHeading('Make the rhythm yours')}<p class="modal-intro">Start with 25 minutes of focus, 5 minutes away, and a longer break every four sessions. Adjust it to fit your day.</p>${active?'<p class="reason-note">End the current session before changing its durations. You can still change alarms and notifications.</p>':''}<form id="pomo-settings-form"><div class="pomo-settings-grid">${[['work','Focus',180],['short','Short break',60],['long','Long break',120]].map(([key,label,max])=>`<label class="field"><span>${label} <small>minutes</small></span><input id="pomo-setting-${key}" type="number" min="1" max="${max}" required value="${settings[key]}" ${active?'disabled':''}></label>`).join('')}</div><label class="field"><span>A long break after</span><select id="pomo-setting-every" ${active?'disabled':''}>${[2,3,4,5,6,7,8].map(n=>`<option value="${n}" ${n===settings.every?'selected':''}>${n} focus sessions</option>`).join('')}</select></label><label class="reminder-toggle"><span><b>Completion alarms</b><small>A rising chime after focus. A different bell after either break.</small></span><input id="pomo-setting-sounds" type="checkbox" role="switch" ${settings.sounds !== false?'checked':''}></label><div class="alarm-previews"><button type="button" class="button" id="preview-focus-sound" ${settings.sounds===false?'disabled':''}>♫ Focus alarm</button><button type="button" class="button" id="preview-break-sound" ${settings.sounds===false?'disabled':''}>♫ Break alarm</button></div><label class="reminder-toggle"><span><b>Tell me when time is up</b><small>A private notification, even with the window closed.</small></span><input id="pomo-setting-notifications" type="checkbox" role="switch" ${settings.notifications?'checked':''}></label><p class="modal-error" id="pomo-settings-error" role="alert"></p><div class="modal-actions"><button class="button" type="button" data-close>Close</button><button class="button primary" type="submit" ${active?'disabled':''}>Save rhythm</button></div></form>`);
  $('#pomo-setting-sounds').addEventListener('change',event=>sendPomodoro('sounds',{enabled:event.target.checked}));
  $('#preview-focus-sound').addEventListener('click',()=>sendPomodoro('previewSound',{phase:'work'}));
  $('#preview-break-sound').addEventListener('click',()=>sendPomodoro('previewSound',{phase:'short'}));
  $('#pomo-setting-notifications').addEventListener('change',event=>sendPomodoro('notifications',{enabled:event.target.checked}));
  $('#pomo-settings-form').addEventListener('submit',event=>{ event.preventDefault(); sendPomodoro('settings',{work:Number($('#pomo-setting-work').value),short:Number($('#pomo-setting-short').value),long:Number($('#pomo-setting-long').value),every:Number($('#pomo-setting-every').value)}); });
}
function setupPomodoro() {
  $('#pomo-start').addEventListener('click',()=>sendPomodoro(pomodoro.status==='running'?'pause':'start'));
  $('#pomo-reset').addEventListener('click',()=>{
    if (!['running','paused'].includes(pomodoro.status)) { sendPomodoro('reset'); return; }
    modal(`${modalHeading('End this session?')}<p class="modal-intro">This unfinished interval won’t count as a completed focus session. Your task and earlier sessions stay saved.</p><div class="modal-actions"><button class="button" data-close>Keep going</button><button class="button danger" id="confirm-pomo-reset">End session</button></div>`);
    $('#confirm-pomo-reset').addEventListener('click',()=>{sendPomodoro('reset');closeModal();});
  });
  $$('[data-pomo-phase]').forEach(button=>button.addEventListener('click',()=>sendPomodoro('phase',{phase:button.dataset.pomoPhase})));
  $('#pomo-task').addEventListener('change',event=>{
    const task = dayPlan(state,plannerDate).tasks.find(t=>t.originId === event.target.value);
    sendPomodoro('task',{taskId:task?.originId || '',taskDate:task?plannerDate:'',taskTitle:task?.title || ''});
    event.target.blur();
  });
  $('#pomo-settings').addEventListener('click',pomodoroSettingsModal);
  $('#pomo-complete-task').addEventListener('click',()=>{
    const date=pomodoro.taskDate,task=dayPlan(state,date).tasks.find(t=>t.originId===pomodoro.taskId);
    if(task) changeTask(task.id,t=>({...t,done:true}),date);
  });
}

if (isMac && window.__HABIT_NATIVE__?.showPermissionSetup) permissionsModal(window.__HABIT_NATIVE__.permissionSetupStep);
