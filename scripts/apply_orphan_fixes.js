/**
 * apply_orphan_fixes.js
 *
 * Writes the orphan-UID reconciliation.
 *
 * OPERATIONS (run ONLY when DRY_RUN = false):
 *   1. Rajendra kr.Sharma (NqNRINy8YJUCrenZr5LxdPzH5Xk2)
 *       - If user.migratedFrom is empty → set migratedFrom = '7lcl0IxCrkhtoT9AjHKFPz6gCFz2'
 *       - Else → add '7lcl0IxCrkhtoT9AjHKFPz6gCFz2' to migratedFromChain
 *   2. Pawan Kumar Rana (tKg85ookUybRT0UkVc4O7E3ZJjJ3)
 *       - Leave migratedFrom unchanged
 *       - Add 'EwVF1ZtQ7hO0SkqUnDWrws2jy2K2' to migratedFromChain
 *   3. Prateek (BDnmvN6WqKT8NZtKgeKiXILrYaw2)
 *       - Leave migratedFrom unchanged
 *       - Add ['CLuXh7VGuhgHyRMmR2qFpvx8unH2', 'S2WLdvgSDYTg2fhnzqRi0XULXcv2'] to migratedFromChain
 *   4. DELETE 6 test docs owned by orphan KvzENlCWKugUCtAuJ2Ak7KiiasE3
 *       - 3 activityLogs where employeeId == KvzENl…
 *       - 3 photos where employeeId == KvzENl…
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

const DRY_RUN = true;

const FIXES = [
  {
    name: 'Rajendra kr.Sharma',
    userId: 'NqNRINy8YJUCrenZr5LxdPzH5Xk2',
    addLink: '7lcl0IxCrkhtoT9AjHKFPz6gCFz2',
    // If migratedFrom empty → set it there; else push to chain
    preferMigratedFromIfEmpty: true,
  },
  {
    name: 'Pawan Kumar Rana',
    userId: 'tKg85ookUybRT0UkVc4O7E3ZJjJ3',
    addChain: ['EwVF1ZtQ7hO0SkqUnDWrws2jy2K2'],
  },
  {
    name: 'Prateek',
    userId: 'BDnmvN6WqKT8NZtKgeKiXILrYaw2',
    addChain: [
      'CLuXh7VGuhgHyRMmR2qFpvx8unH2',
      'S2WLdvgSDYTg2fhnzqRi0XULXcv2',
    ],
  },
];

const TEST_ORPHAN_TO_DELETE = 'KvzENlCWKugUCtAuJ2Ak7KiiasE3';

(async () => {
  console.log(`[orphan-fix] DRY_RUN=${DRY_RUN}`);
  console.log('─'.repeat(78));

  // ── Phase 1: user-doc updates ────────────────────────────────────────
  for (const fix of FIXES) {
    const ref = db.collection('users').doc(fix.userId);
    const snap = await ref.get();
    if (!snap.exists) {
      console.log(`  MISS    ${fix.userId}  "${fix.name}"  — user doc does not exist`);
      continue;
    }
    const u = snap.data();
    const currentMigratedFrom = typeof u.migratedFrom === 'string' ? u.migratedFrom.trim() : '';
    const currentChain = Array.isArray(u.migratedFromChain)
      ? u.migratedFromChain.filter((x) => typeof x === 'string' && x.trim()).map((x) => x.trim())
      : [];

    const update = {};
    let action = '';

    if (fix.preferMigratedFromIfEmpty) {
      // Rajendra
      if (!currentMigratedFrom) {
        update.migratedFrom = fix.addLink;
        action = `SET migratedFrom = "${fix.addLink}"`;
      } else if (currentMigratedFrom === fix.addLink) {
        action = `NO-OP: migratedFrom already equals "${fix.addLink}"`;
      } else if (currentChain.includes(fix.addLink)) {
        action = `NO-OP: "${fix.addLink}" already in migratedFromChain`;
      } else {
        update.migratedFromChain = [...currentChain, fix.addLink];
        action = `APPEND migratedFromChain += "${fix.addLink}"  (migratedFrom="${currentMigratedFrom}" preserved)`;
      }
    } else {
      // Pawan, Prateek: always append to chain
      const toAdd = fix.addChain.filter(
        (id) => !currentChain.includes(id) && id !== currentMigratedFrom,
      );
      if (toAdd.length === 0) {
        action = `NO-OP: all chain entries already present`;
      } else {
        update.migratedFromChain = [...currentChain, ...toAdd];
        action = `APPEND migratedFromChain += ${JSON.stringify(toAdd)}  (migratedFrom="${currentMigratedFrom}" preserved)`;
      }
    }

    console.log(`  ${fix.userId}  "${fix.name}"`);
    console.log(`     before: migratedFrom="${currentMigratedFrom}"  migratedFromChain=${JSON.stringify(currentChain)}`);
    console.log(`     plan:   ${action}`);

    if (!DRY_RUN && Object.keys(update).length > 0) {
      update.updatedAt = admin.firestore.FieldValue.serverTimestamp();
      await ref.update(update);
      console.log(`     APPLIED`);
    }
  }

  // ── Phase 2: delete test orphan's docs ───────────────────────────────
  console.log('');
  console.log(`[orphan-fix] Test orphan cleanup: ${TEST_ORPHAN_TO_DELETE}`);

  const [logs, photos, sessions] = await Promise.all([
    db.collection('activityLogs').where('employeeId', '==', TEST_ORPHAN_TO_DELETE).get(),
    db.collection('photos').where('employeeId', '==', TEST_ORPHAN_TO_DELETE).get(),
    db.collection('sessions').where('employeeId', '==', TEST_ORPHAN_TO_DELETE).get(),
  ]);

  console.log(`  found: logs=${logs.size}, photos=${photos.size}, sessions=${sessions.size}`);

  for (const d of logs.docs) {
    const data = d.data();
    console.log(`    LOG    ${d.id}  type=${data.type || '?'}  detail="${(data.detail || '').slice(0, 60)}"`);
    if (!DRY_RUN) await d.ref.delete();
  }
  for (const d of photos.docs) {
    const data = d.data();
    console.log(`    PHOTO  ${d.id}  location="${(data.location || '').slice(0, 60)}"  customer="${data.customerName || ''}"  notes="${(data.notes || '').slice(0, 40)}"`);
    if (!DRY_RUN) await d.ref.delete();
  }
  for (const d of sessions.docs) {
    const data = d.data();
    console.log(`    SESSION  ${d.id}  status=${data.status || '?'}  startTime=${data.startTime?.toDate?.()?.toISOString?.() || '?'}`);
    if (!DRY_RUN) await d.ref.delete();
  }

  console.log('');
  console.log('[orphan-fix] === SUMMARY ===');
  console.log(JSON.stringify({
    dryRun: DRY_RUN,
    userFixes: FIXES.length,
    docsToDelete: {
      activityLogs: logs.size,
      photos: photos.size,
      sessions: sessions.size,
    },
  }, null, 2));
  process.exit(0);
})().catch((e) => {
  console.error('FATAL:', e);
  process.exit(1);
});
