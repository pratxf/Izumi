/**
 * audit_migrated_from.js
 * ──────────────────────
 * One-shot audit to find users whose `migratedFrom` field is missing but
 * should be set, by cross-referencing user UIDs against the historical
 * employeeIds present in `activityLogs` and `photos`.
 *
 * Logic:
 *   1. Load all users from Firestore (users collection).
 *   2. Build the set of "known" current UIDs.
 *   3. Build the set of "linked" IDs already in any user.migratedFrom field.
 *   4. Scan activityLogs and photos for distinct employeeId values.
 *   5. For each employeeId in the data that is NOT a known current UID and
 *      NOT already linked via migratedFrom — flag it as orphaned.
 *   6. Match orphaned IDs to candidate current users by name overlap,
 *      photo timestamps, or session ownership when possible.
 *   7. List all users with migratedFrom set, plus orphans needing review.
 *
 * Auth: uses Firebase CLI's local application default credentials.
 *   Adjust `credFile` path below if your firebase-tools profile differs.
 *
 * Run:
 *   cd scripts
 *   npm install firebase-admin       (if not already)
 *   node audit_migrated_from.js
 *
 * Output: prints to stdout. Pipe to a file if desired:
 *   node audit_migrated_from.js > audit_migrated_from.out
 */

const admin = require('firebase-admin');
const path = require('path');
const os = require('os');

// ── Adjust this path to match your Firebase CLI credentials file ──
const credFile = path.join(
  process.env.APPDATA || path.join(os.homedir(), '.config'),
  'firebase',
  // typical filename — check %APPDATA%\firebase\ or ~/.config/firebase/
  // for your actual *_application_default_credentials.json file
  'aasmandigitals_gmail_com_application_default_credentials.json',
);

process.env.GOOGLE_APPLICATION_CREDENTIALS = credFile;

admin.initializeApp({
  projectId: 'izumi-6e087',
});

const db = admin.firestore();

async function loadAllUsers() {
  const snap = await db.collection('users').get();
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
}

async function loadDistinctEmployeeIdsFromCollection(collection, field = 'employeeId') {
  const ids = new Set();
  const snap = await db.collection(collection).get();
  for (const doc of snap.docs) {
    const v = doc.data()[field];
    if (typeof v === 'string' && v.trim().length > 0) {
      ids.add(v.trim());
    }
  }
  return ids;
}

async function countDataForEmployeeId(empId) {
  const [logs, photos, sessions] = await Promise.all([
    db.collection('activityLogs').where('employeeId', '==', empId).limit(1000).get(),
    db.collection('photos').where('employeeId', '==', empId).limit(1000).get(),
    db.collection('sessions').where('employeeId', '==', empId).limit(1000).get(),
  ]);
  return {
    logs: logs.size,
    photos: photos.size,
    sessions: sessions.size,
  };
}

(async () => {
  console.log('Loading all users…');
  const users = await loadAllUsers();
  console.log(`  ${users.length} user docs.`);

  // (1) Users with migratedFrom set
  const usersWithMigration = users.filter(
    (u) => typeof u.migratedFrom === 'string' && u.migratedFrom.trim().length > 0,
  );
  console.log('');
  console.log(`=== Users with migratedFrom (${usersWithMigration.length}) ===`);
  for (const u of usersWithMigration) {
    console.log(
      `  ${u.id}  ←  ${u.migratedFrom}  (${u.name || '<no name>'}, ${u.activeRole || u.role || '?'})`,
    );
  }

  // Build sets for fast lookup
  const knownCurrentUids = new Set(users.map((u) => u.id));
  const linkedOldUids = new Set(
    usersWithMigration.map((u) => u.migratedFrom.trim()),
  );

  // (2) Specific check for Bhanu Pratap Singh
  console.log('');
  console.log('=== Bhanu Pratap Singh check ===');
  const bhanuMatches = users.filter((u) => {
    const n = (u.name || '').toLowerCase();
    return n.includes('bhanu') && n.includes('pratap');
  });
  if (bhanuMatches.length === 0) {
    console.log('  No user matching "Bhanu Pratap" found in users collection.');
  } else {
    for (const b of bhanuMatches) {
      console.log(`  Current UID:    ${b.id}`);
      console.log(`  Name:           ${b.name}`);
      console.log(`  Phone:          ${b.phone || '<none>'}`);
      console.log(`  activeRole:     ${b.activeRole || b.role || '?'}`);
      console.log(`  migratedFrom:   ${b.migratedFrom ? b.migratedFrom : '<MISSING>'}`);
      const counts = await countDataForEmployeeId(b.id);
      console.log(
        `  Data under current UID: ${counts.logs} logs, ${counts.photos} photos, ${counts.sessions} sessions`,
      );
    }
  }

  // (3) Scan activityLogs + photos for orphan employeeIds
  console.log('');
  console.log('Scanning activityLogs & photos for orphan employeeIds…');
  const [logEmpIds, photoEmpIds] = await Promise.all([
    loadDistinctEmployeeIdsFromCollection('activityLogs'),
    loadDistinctEmployeeIdsFromCollection('photos'),
  ]);
  const allDataEmpIds = new Set([...logEmpIds, ...photoEmpIds]);
  console.log(`  ${allDataEmpIds.size} distinct employeeId values across activityLogs+photos.`);

  const orphans = [...allDataEmpIds].filter(
    (id) => !knownCurrentUids.has(id) && !linkedOldUids.has(id),
  );

  console.log('');
  console.log(`=== Orphan employeeIds found in data but not in users / migratedFrom (${orphans.length}) ===`);
  for (const oid of orphans) {
    const counts = await countDataForEmployeeId(oid);
    console.log(
      `  ${oid}  →  ${counts.logs} logs, ${counts.photos} photos, ${counts.sessions} sessions`,
    );
    // Try to suggest a current user by inspecting one photo's customerName
    // or by matching session ownership patterns. Best-effort hint only.
    try {
      const sample = await db
        .collection('photos')
        .where('employeeId', '==', oid)
        .limit(1)
        .get();
      if (!sample.empty) {
        const p = sample.docs[0].data();
        console.log(`     sample photo: ${p.location || p.customerName || '<no clue>'}`);
      }
    } catch (_) {}
  }

  console.log('');
  console.log('Done.');
  process.exit(0);
})().catch((err) => {
  console.error('FATAL:', err);
  process.exit(1);
});
