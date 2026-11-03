const fs = require('node:fs');
const path = require('node:path');

const file = path.join(__dirname, 'data', 'app.json');
if (!fs.existsSync(file)) {
  console.error('No data file. Start the server once first.');
  process.exit(1);
}
const db = JSON.parse(fs.readFileSync(file, 'utf8'));
const [command, id] = process.argv.slice(2);

if (command === 'reports') {
  const open = db.reports.filter((r) => r.status === 'open');
  if (open.length === 0) console.log('No open reports.');
  for (const report of open) {
    const from = db.users.find((u) => u.id === report.from);
    const to = db.users.find((u) => u.id === report.to);
    console.log(`${report.id} | ${report.at} | ${from?.name || 'deleted'} → ${to?.name || 'deleted'} (${report.to}) | ${report.reason}`);
  }
} else if (command === 'ban' && id) {
  const user = db.users.find((u) => u.id === id);
  if (!user) { console.error('User not found.'); process.exit(1); }
  user.banned = true;
  db.sessions = db.sessions.filter((s) => s.userId !== id);
  fs.writeFileSync(file, JSON.stringify(db, null, 2), { mode: 0o600 });
  console.log(`Banned ${user.name} (${id}).`);
} else if (command === 'resolve' && id) {
  const report = db.reports.find((r) => r.id === id);
  if (!report) { console.error('Report not found.'); process.exit(1); }
  report.status = 'resolved';
  report.resolvedAt = new Date().toISOString();
  fs.writeFileSync(file, JSON.stringify(db, null, 2), { mode: 0o600 });
  console.log(`Resolved report ${id}.`);
} else {
  console.log('Usage: node admin.cjs reports | ban USER_ID | resolve REPORT_ID');
  process.exit(1);
}
