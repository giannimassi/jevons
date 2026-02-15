#!/usr/bin/env node
// Generates deterministic fixture data for E2E tests.
// Run: node tests/e2e/generate-fixtures.js
// Output: tests/e2e/fixtures/

const fs = require('fs');
const path = require('path');

const FIXTURE_DIR = path.join(__dirname, 'fixtures');
const now = Math.floor(Date.now() / 1000);
const DAY = 86400;
const HOUR = 3600;

// Normalize "now" to the start of the current UTC day + some hours offset,
// so generated timestamps are always within "recent" range for dashboard filters.
const todayStart = now - (now % DAY);

const slugs = ['proj-alpha', 'proj-beta', 'proj-gamma'];
const projectPaths = [
  '/Users/test/dev/alpha',
  '/Users/test/dev/beta',
  '/Users/test/work/gamma',
];

// Schedule: dayBack=0 means today, dayBack=6 means 6 days ago.
const schedule = [
  { dayBack: 6, hours: [9, 14] },
  { dayBack: 5, hours: [10, 15, 17] },
  { dayBack: 4, hours: [8, 11, 16] },
  { dayBack: 3, hours: [9, 12, 14, 18] },
  { dayBack: 2, hours: [10, 13, 16] },
  { dayBack: 1, hours: [9, 11, 14, 17, 20] },
  { dayBack: 0, hours: [8, 10] },
];

// ---- events.tsv ----
const eventsHeader =
  'ts_epoch\tts_iso\tproject_slug\tsession_id\tinput\toutput\tcache_read\tcache_create\tbillable\ttotal_with_cache\tcontent_type\tsignature';
const eventRows = [];
let idx = 0;

for (const { dayBack, hours } of schedule) {
  for (const h of hours) {
    const slug = slugs[idx % slugs.length];
    const epoch = todayStart - dayBack * DAY + h * HOUR;
    const isoDate = new Date(epoch * 1000).toISOString();
    const sessionId = `sess-${String(idx + 1).padStart(3, '0')}`;
    const input = 1000 * (idx + 1);
    const output = 500 * (idx + 1);
    const cacheRead = 200 * (idx + 1);
    const cacheCreate = 100 * (idx + 1);
    const billable = input + output;
    const totalWithCache = billable + cacheRead + cacheCreate;
    const sig = `sig-${String(idx + 1).padStart(3, '0')}`;
    eventRows.push(
      [epoch, isoDate, slug, sessionId, input, output, cacheRead, cacheCreate, billable, totalWithCache, 'text', sig].join('\t')
    );
    idx++;
  }
}

fs.writeFileSync(
  path.join(FIXTURE_DIR, 'events.tsv'),
  eventsHeader + '\n' + eventRows.join('\n') + '\n'
);

// ---- live-events.tsv ----
const liveHeader =
  'ts_epoch\tts_iso\tproject_slug\tsession_id\tprompt_preview\tinput\toutput\tcache_read\tcache_create\tbillable\ttotal_with_cache\tcontent_type\tsignature';
const liveRows = [];
const prompts = [
  'How do I fix this bug?',
  'Explain the auth flow',
  'Write a test for parser',
  'Refactor the sync module',
  'Add error handling',
  'Create a new endpoint',
  'Review this PR',
  'Debug the failing test',
  'Optimize the query',
  'Update the docs',
  'Add a migration',
  'Fix the linter warnings',
];

// Generate live events: last 2 hours, mix of projects
for (let i = 0; i < 12; i++) {
  const slug = slugs[i % slugs.length];
  const epoch = now - (120 - i * 10) * 60; // spread over last 2h, 10m apart
  const isoDate = new Date(epoch * 1000).toISOString();
  const sessionId = `live-sess-${String(i + 1).padStart(3, '0')}`;
  const prompt = prompts[i];
  const input = 800 * (i + 1);
  const output = 400 * (i + 1);
  const cacheRead = 150 * (i + 1);
  const cacheCreate = 50 * (i + 1);
  const billable = input + output;
  const totalWithCache = billable + cacheRead + cacheCreate;
  const sig = `live-sig-${String(i + 1).padStart(3, '0')}`;
  liveRows.push(
    [epoch, isoDate, slug, sessionId, prompt, input, output, cacheRead, cacheCreate, billable, totalWithCache, 'text', sig].join('\t')
  );
}

fs.writeFileSync(
  path.join(FIXTURE_DIR, 'live-events.tsv'),
  liveHeader + '\n' + liveRows.join('\n') + '\n'
);

// ---- projects.json ----
const projects = slugs.map((slug, i) => ({
  slug,
  path: projectPaths[i],
}));
fs.writeFileSync(path.join(FIXTURE_DIR, 'projects.json'), JSON.stringify(projects, null, 2) + '\n');

// ---- sync-status.json ----
const syncStatus = {
  last_sync_epoch: now,
  last_sync_iso: new Date(now * 1000).toISOString(),
  sessions_synced: 22,
  events_written: 22,
  duration_ms: 42,
};
fs.writeFileSync(path.join(FIXTURE_DIR, 'sync-status.json'), JSON.stringify(syncStatus, null, 2) + '\n');

// ---- account.json ----
const account = {
  email: 'test@example.com',
  member_id: 'mem_test123',
  organization: 'Test Org',
};
fs.writeFileSync(path.join(FIXTURE_DIR, 'account.json'), JSON.stringify(account, null, 2) + '\n');

// ---- heartbeat/sync.txt ----
fs.writeFileSync(
  path.join(FIXTURE_DIR, 'heartbeat', 'sync.txt'),
  `${now},999,12345,ok\n`
);

// ---- ui-context.json ----
const uiContext = {
  cwd: '/Users/test/dev/alpha',
};
fs.writeFileSync(path.join(FIXTURE_DIR, 'ui-context.json'), JSON.stringify(uiContext, null, 2) + '\n');

// Print summary
console.log(`Generated fixtures in ${FIXTURE_DIR}:`);
console.log(`  events.tsv: ${eventRows.length} rows`);
console.log(`  live-events.tsv: ${liveRows.length} rows`);
console.log(`  projects.json: ${projects.length} projects`);
console.log(`  sync-status.json, account.json, heartbeat/sync.txt, ui-context.json`);

// Also export computed totals for test assertions
const totalBillable = eventRows.reduce((sum, row) => {
  const parts = row.split('\t');
  return sum + Number(parts[8]);
}, 0);

const projTotals = {};
eventRows.forEach((row) => {
  const parts = row.split('\t');
  const slug = parts[2];
  projTotals[slug] = (projTotals[slug] || 0) + Number(parts[8]);
});

console.log(`\nComputed totals for assertions:`);
console.log(`  Total billable (all time): ${totalBillable.toLocaleString()}`);
for (const [slug, total] of Object.entries(projTotals)) {
  console.log(`  ${slug}: ${total.toLocaleString()}`);
}
