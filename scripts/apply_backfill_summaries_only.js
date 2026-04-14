/**
 * Phase-2-only: recalculate dailySummaries.totalDistance for every
 * (employee, IST-date) pair touched by the session backfill.
 *
 * Uses in-memory date filtering (employeeId-only query + JS filter) to
 * avoid needing the composite index on (employeeId, startTime ASC).
 *
 * Session writes were already applied by apply_backfill_distances.js.
 * This script rescans the same candidate sessions to derive the set of
 * (employee, date) pairs that need resumming, then does exactly that.
 */

const admin = require('firebase-admin');
const path = require('path');

process.env.GOOGLE_APPLICATION_CREDENTIALS = path.join(
  process.env.APPDATA,
  'firebase',
  'aasmandigitals_gmail_com_application_default_credentials.json',
);

admin.initializeApp({ projectId: 'izumi-6e087' });

function formatDateIST(timestamp) {
  const date = timestamp.toDate();
  const utcMs = date.getTime() + date.getTimezoneOffset() * 60_000;
  const istDate = new Date(utcMs + 330 * 60_000);
  return `${istDate.getFullYear()}-${String(istDate.getMonth() + 1).padStart(2, '0')}-${String(istDate.getDate()).padStart(2, '0')}`;
}

(async () => {
  const db = admin.firestore();
  console.log('[summaries] Loading all completed + auto_ended sessions...');

  // Pull the candidate set (same as backfill): auto_ended + completed
  // that were touched by the run. We include ALL completed/auto_ended
  // to be safe — for each (employeeId, dateStr) we'll re-sum that day.
  const [autoEnded, completed] = await Promise.all([
    db.collection('sessions').where('status', '==', 'auto_ended').get(),
    db.collection('sessions').where('status', '==', 'completed').get(),
  ]);

  const allSessions = [...autoEnded.docs, ...completed.docs];
  console.log(`[summaries] Loaded ${allSessions.length} sessions (${autoEnded.size} auto_ended + ${completed.size} completed)`);

  // Build (employeeId, dateStr) → list of sessions for that day
  const dayBuckets = new Map();
  for (const sDoc of allSessions) {
    const s = sDoc.data();
    if (!s.employeeId || !s.startTime) continue;
    const dateStr = formatDateIST(s.startTime);
    const key = `${s.employeeId}__${dateStr}`;
    if (!dayBuckets.has(key)) {
      dayBuckets.set(key, {
        employeeId: s.employeeId,
        enterpriseId: s.enterpriseId,
        dateStr,
        sessions: [],
      });
    }
    dayBuckets.get(key).sessions.push(s);
  }

  console.log(`[summaries] ${dayBuckets.size} (employee, date) buckets\n`);

  let written = 0;
  let errors = 0;
  for (const [key, bucket] of dayBuckets) {
    const summaryId = `${bucket.employeeId}_${bucket.dateStr}`;
    let summed = 0;
    for (const s of bucket.sessions) {
      summed += Number(s.totalDistance) || 0;
    }
    summed = Math.round(summed * 100) / 100;

    try {
      await db.collection('dailySummaries').doc(summaryId).set(
        {
          totalDistance: summed,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          enterpriseId: bucket.enterpriseId,
          employeeId: bucket.employeeId,
        },
        { merge: true },
      );
      console.log(`  WROTE  ${summaryId}  sessions=${bucket.sessions.length}  totalDistance=${summed}`);
      written++;
    } catch (err) {
      console.error(`  ERROR  ${summaryId}: ${err.message || err}`);
      errors++;
    }
  }

  console.log('\n[summaries] === FINAL ===');
  console.log(JSON.stringify({
    totalBuckets: dayBuckets.size,
    summariesWritten: written,
    summaryWriteErrors: errors,
  }, null, 2));
  process.exit(0);
})().catch((e) => {
  console.error('FATAL:', e);
  process.exit(1);
});
