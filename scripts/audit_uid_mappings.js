/**
 * audit_uid_mappings.js
 * Read-only audit. Produces 4 reports:
 *   1. Orphaned employeeIds in activity data with no matching users doc
 *   2. Duplicate users (same phone, or same name+enterprise)
 *   3. Stale UIDs referenced anywhere but with no users doc
 *   4. migratedFrom chains pointing to nothing
 *
 * Does NOT write anything. Does NOT delete anything.
 */

const admin = require('firebase-admin');
const path = require('path');

process.env.GOOGLE_APPLICATION_CREDENTIALS = path.join(
  process.env.APPDATA,
  'firebase',
  'aasmandigitals_gmail_com_application_default_credentials.json',
);

admin.initializeApp({ projectId: 'izumi-6e087' });

const db = admin.firestore();

function normalizePhone(p) {
  if (!p) return '';
  return String(p).replace(/\D/g, '');
}

async function distinctEmployeeIdsWithCounts(collection) {
  const counts = new Map();
  const snap = await db.collection(collection).get();
  for (const doc of snap.docs) {
    const eid = doc.data().employeeId;
    if (typeof eid === 'string' && eid.trim().length > 0) {
      counts.set(eid, (counts.get(eid) || 0) + 1);
    }
  }
  return counts;
}

(async () => {
  console.log('Loading collections...');
  const [usersSnap, actSnap, sesSnap, phoSnap, taskSnap] = await Promise.all([
    db.collection('users').get(),
    db.collection('activityLogs').get(),
    db.collection('sessions').get(),
    db.collection('photos').get(),
    db.collection('tasks').get(),
  ]);
  console.log(`  users=${usersSnap.size} activityLogs=${actSnap.size} sessions=${sesSnap.size} photos=${phoSnap.size} tasks=${taskSnap.size}\n`);

  // Index users
  const users = [];
  const usersById = new Map();
  const migratedFromToUser = new Map(); // old UID -> current user
  for (const d of usersSnap.docs) {
    const u = { id: d.id, ...d.data() };
    users.push(u);
    usersById.set(u.id, u);
    const mf = typeof u.migratedFrom === 'string' ? u.migratedFrom.trim() : '';
    if (mf) migratedFromToUser.set(mf, u);
  }
  const knownIds = new Set(users.map((u) => u.id));
  const linkedOldIds = new Set(migratedFromToUser.keys());

  // Build per-collection employeeId count maps
  const actCounts = new Map();
  const sesCounts = new Map();
  const phoCounts = new Map();
  const taskCountsByAssignedTo = new Map();

  for (const d of actSnap.docs) {
    const v = d.data().employeeId;
    if (typeof v === 'string' && v.trim()) actCounts.set(v, (actCounts.get(v) || 0) + 1);
  }
  for (const d of sesSnap.docs) {
    const v = d.data().employeeId;
    if (typeof v === 'string' && v.trim()) sesCounts.set(v, (sesCounts.get(v) || 0) + 1);
  }
  for (const d of phoSnap.docs) {
    const v = d.data().employeeId;
    if (typeof v === 'string' && v.trim()) phoCounts.set(v, (phoCounts.get(v) || 0) + 1);
  }
  for (const d of taskSnap.docs) {
    const v = d.data().assignedTo;
    if (typeof v === 'string' && v.trim()) {
      taskCountsByAssignedTo.set(v, (taskCountsByAssignedTo.get(v) || 0) + 1);
    }
  }

  // Union of all IDs referenced in data
  const referencedIds = new Set([
    ...actCounts.keys(),
    ...sesCounts.keys(),
    ...phoCounts.keys(),
    ...taskCountsByAssignedTo.keys(),
  ]);

  // ── CHECK 1: Orphaned employeeIds (not a user doc, not a migratedFrom either)
  console.log('='.repeat(70));
  console.log('CHECK 1: Orphaned employeeIds in activity data');
  console.log('='.repeat(70));
  const orphans = [...referencedIds].filter((id) => !knownIds.has(id) && !linkedOldIds.has(id));
  if (orphans.length === 0) {
    console.log('  None found.');
  } else {
    console.log(`  ${orphans.length} orphan IDs found:\n`);
    // For each orphan, try to guess who it belongs to by sampling a photo/session name
    for (const oid of orphans) {
      const counts = {
        activityLogs: actCounts.get(oid) || 0,
        sessions: sesCounts.get(oid) || 0,
        photos: phoCounts.get(oid) || 0,
        tasks: taskCountsByAssignedTo.get(oid) || 0,
      };
      const total = counts.activityLogs + counts.sessions + counts.photos + counts.tasks;

      // Suggest a candidate current user:
      //   1. If a photo for this orphan has customerName hints, skip (customer not employee)
      //   2. Look for a current user whose name matches sample activity log metadata
      let hint = '';
      try {
        const sample = await db.collection('photos').where('employeeId', '==', oid).limit(1).get();
        if (!sample.empty) {
          const p = sample.docs[0].data();
          hint = p.location || p.customerName || '';
        }
        if (!hint) {
          const sampleAct = await db.collection('activityLogs').where('employeeId', '==', oid).limit(1).get();
          if (!sampleAct.empty) {
            const a = sampleAct.docs[0].data();
            hint = a.detail || a.title || '';
          }
        }
      } catch (_) {}

      console.log(`  ${oid}`);
      console.log(`    counts: logs=${counts.activityLogs} sessions=${counts.sessions} photos=${counts.photos} tasks=${counts.tasks} total=${total}`);
      if (hint) console.log(`    sample: ${hint.slice(0, 120)}`);
    }
  }

  // ── CHECK 2: Duplicate users
  console.log('\n' + '='.repeat(70));
  console.log('CHECK 2: Duplicate users (same phone OR same name+enterprise)');
  console.log('='.repeat(70));

  const byPhone = new Map();
  const byNameEnt = new Map();
  for (const u of users) {
    const phone = normalizePhone(u.phone);
    if (phone) {
      if (!byPhone.has(phone)) byPhone.set(phone, []);
      byPhone.get(phone).push(u);
    }
    const nameEnt = `${(u.name || '').trim().toLowerCase()}__${u.enterpriseId || ''}`;
    if ((u.name || '').trim()) {
      if (!byNameEnt.has(nameEnt)) byNameEnt.set(nameEnt, []);
      byNameEnt.get(nameEnt).push(u);
    }
  }

  const phoneDupes = [...byPhone.entries()].filter(([_, arr]) => arr.length > 1);
  if (phoneDupes.length === 0) {
    console.log('  No duplicates by phone.');
  } else {
    console.log(`  ${phoneDupes.length} duplicate phone groups:`);
    for (const [phone, arr] of phoneDupes) {
      console.log(`\n  phone=${phone}`);
      for (const u of arr) {
        console.log(`    ${u.id}  name="${u.name || ''}"  role=${u.activeRole || u.role || '?'}  enterpriseId=${u.enterpriseId || ''}  migratedFrom=${u.migratedFrom || ''}`);
      }
    }
  }

  const nameDupes = [...byNameEnt.entries()].filter(([_, arr]) => arr.length > 1);
  const nameDupesNotCoveredByPhone = nameDupes.filter(([_, arr]) => {
    // Only surface name dupes if all arr members have DIFFERENT phones (phone dupes already reported)
    const phones = new Set(arr.map((u) => normalizePhone(u.phone)));
    return phones.size > 1 || [...phones].some((p) => !p);
  });
  if (nameDupesNotCoveredByPhone.length === 0) {
    console.log('\n  No duplicates by name+enterprise (beyond phone dupes).');
  } else {
    console.log(`\n  ${nameDupesNotCoveredByPhone.length} duplicate name+enterprise groups:`);
    for (const [key, arr] of nameDupesNotCoveredByPhone) {
      const [name, ent] = key.split('__');
      console.log(`\n  name="${name}"  enterprise=${ent}`);
      for (const u of arr) {
        console.log(`    ${u.id}  phone="${u.phone || ''}"  role=${u.activeRole || u.role || '?'}  migratedFrom=${u.migratedFrom || ''}`);
      }
    }
  }

  // ── CHECK 3: Stale UIDs (same as orphans but reported by collection)
  console.log('\n' + '='.repeat(70));
  console.log('CHECK 3: UIDs referenced in data but with no users doc');
  console.log('='.repeat(70));
  const stale = [...referencedIds].filter((id) => !knownIds.has(id));
  if (stale.length === 0) {
    console.log('  None found.');
  } else {
    console.log(`  ${stale.length} stale UIDs (overlaps with Check 1 but includes linked-via-migratedFrom IDs):\n`);
    for (const sid of stale) {
      const linkedUser = migratedFromToUser.get(sid);
      const status = linkedUser ? `LINKED via migratedFrom ← ${linkedUser.id} (${linkedUser.name || ''})` : 'ORPHAN — no link';
      console.log(`  ${sid}  [${status}]`);
      console.log(`    logs=${actCounts.get(sid) || 0} sessions=${sesCounts.get(sid) || 0} photos=${phoCounts.get(sid) || 0} tasks=${taskCountsByAssignedTo.get(sid) || 0}`);
    }
  }

  // ── CHECK 4: migratedFrom pointing nowhere
  console.log('\n' + '='.repeat(70));
  console.log('CHECK 4: migratedFrom values pointing to nothing');
  console.log('='.repeat(70));
  const badLinks = [];
  for (const u of users) {
    const mf = typeof u.migratedFrom === 'string' ? u.migratedFrom.trim() : '';
    if (!mf) continue;
    const oldHasUserDoc = knownIds.has(mf);
    const oldAppearsInData = referencedIds.has(mf);
    if (!oldHasUserDoc && !oldAppearsInData) {
      badLinks.push({ user: u, reason: 'no users doc AND no data references' });
    } else if (!oldHasUserDoc && oldAppearsInData) {
      // That's the normal migration case — fine.
    }
  }
  if (badLinks.length === 0) {
    console.log('  All migratedFrom links resolve to either a users doc or historical data.');
  } else {
    console.log(`  ${badLinks.length} dead migratedFrom links:\n`);
    for (const { user, reason } of badLinks) {
      console.log(`  ${user.id}  name="${user.name || ''}"  migratedFrom=${user.migratedFrom}  [${reason}]`);
    }
  }

  console.log('\n' + '='.repeat(70));
  console.log('Audit complete. No writes performed.');
  console.log('='.repeat(70));
  process.exit(0);
})().catch((e) => {
  console.error('FATAL:', e);
  process.exit(1);
});
