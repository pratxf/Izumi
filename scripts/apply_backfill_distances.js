/**
 * apply_backfill_distances.js — WRITES corrections to Firestore.
 *
 * Run ONCE after reviewing dry_run_backfill_distances.js output.
 *
 * Writes:
 *   1. sessions/{sessionId}.totalDistance ← corrected (per-session Haversine)
 *   2. dailySummaries/{empId}_{IST-date}.totalDistance ← resum of all corrected sessions for that day (merge:true)
 *
 * Skips sessions with corrected distance > 300 km (safety cap for manual review).
 * Skips sessions with delta < 0.1 km (no-op).
 */

const admin = require('firebase-admin');
const path = require('path');

process.env.GOOGLE_APPLICATION_CREDENTIALS = path.join(
  process.env.APPDATA,
  'firebase',
  'aasmandigitals_gmail_com_application_default_credentials.json',
);

admin.initializeApp({ projectId: 'izumi-6e087' });

const MAX_CORRECTED_DISTANCE_KM = 300;
const MAX_REALISTIC_SPEED_KMH = 120;
const MAX_SEGMENT_DISTANCE_KM = 100;

function haversineDistanceKm(lat1, lng1, lat2, lng2) {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function calculateTrustedDistanceKm(locations) {
  let total = 0;
  let skipped = 0;
  for (let i = 1; i < locations.length; i++) {
    const prev = locations[i - 1];
    const curr = locations[i];
    const seg = haversineDistanceKm(prev.latitude, prev.longitude, curr.latitude, curr.longitude);
    const prevTs = prev.timestamp?.toMillis?.() ?? 0;
    const currTs = curr.timestamp?.toMillis?.() ?? 0;
    const hours = prevTs && currTs && currTs > prevTs ? (currTs - prevTs) / 3_600_000 : 0;
    const speed = hours > 0 ? seg / hours : Infinity;
    if (seg > MAX_SEGMENT_DISTANCE_KM || speed > MAX_REALISTIC_SPEED_KMH) {
      skipped++;
      continue;
    }
    total += seg;
  }
  return { totalDistance: Math.round(total * 100) / 100, skippedSegments: skipped };
}

function formatDateIST(timestamp) {
  const date = timestamp.toDate();
  const utcMs = date.getTime() + date.getTimezoneOffset() * 60_000;
  const istDate = new Date(utcMs + 330 * 60_000);
  return `${istDate.getFullYear()}-${String(istDate.getMonth() + 1).padStart(2, '0')}-${String(istDate.getDate()).padStart(2, '0')}`;
}

(async () => {
  const db = admin.firestore();
  console.log('[apply] WRITE MODE — applying corrections to Firestore');
  console.log('[apply] Querying candidate sessions...');

  const [autoEnded, inflatedAny] = await Promise.all([
    db.collection('sessions').where('status', '==', 'auto_ended').get(),
    db.collection('sessions').where('totalDistance', '>', 500).get(),
  ]);
  const inflatedCompleted = inflatedAny.docs.filter((d) => d.data().status === 'completed');
  const seen = new Set();
  const sessionDocs = [];
  for (const d of [...autoEnded.docs, ...inflatedCompleted]) {
    if (seen.has(d.id)) continue;
    seen.add(d.id);
    sessionDocs.push(d);
  }
  console.log(`[apply] auto_ended=${autoEnded.size}, completed>500km=${inflatedCompleted.length}, unique=${sessionDocs.length}\n`);

  let processed = 0;
  let corrected = 0;
  let noChange = 0;
  let skippedManualReview = 0;
  let writeErrors = 0;
  let distanceRemoved = 0;
  const summariesToRecalc = new Map();

  for (const sDoc of sessionDocs) {
    const s = sDoc.data();
    const oldDistance = Number(s.totalDistance) || 0;
    const employeeId = s.employeeId;
    const enterpriseId = s.enterpriseId;
    const startTime = s.startTime;
    if (!employeeId || !startTime) {
      processed++;
      continue;
    }

    const locs = await db.collection('sessions').doc(sDoc.id).collection('locations').orderBy('timestamp', 'asc').get();
    const locations = locs.docs.map((d) => d.data());
    let correctedDistance = 0;
    if (locations.length >= 2) {
      const r = calculateTrustedDistanceKm(locations);
      correctedDistance = r.totalDistance;
    }
    processed++;

    if (correctedDistance > MAX_CORRECTED_DISTANCE_KM) {
      console.log(`  MANUAL-REVIEW  sid=${sDoc.id}  corrected=${correctedDistance}`);
      skippedManualReview++;
      continue;
    }
    if (Math.abs(oldDistance - correctedDistance) < 0.1) {
      noChange++;
      continue;
    }

    const dateStr = formatDateIST(startTime);
    try {
      await db.collection('sessions').doc(sDoc.id).update({ totalDistance: correctedDistance });
      console.log(`  WROTE  sid=${sDoc.id}  emp=${employeeId}  ${dateStr}  ${oldDistance.toFixed(2)} → ${correctedDistance}`);
      corrected++;
      distanceRemoved += oldDistance - correctedDistance;
      summariesToRecalc.set(`${employeeId}_${dateStr}`, { employeeId, enterpriseId, dateStr });
    } catch (err) {
      console.error(`  ERROR  sid=${sDoc.id}: ${err.message || err}`);
      writeErrors++;
    }
  }

  // Phase 2: resum daily summaries
  console.log(`\n[apply] Recalculating ${summariesToRecalc.size} daily summaries...`);
  let summariesWritten = 0;
  let summaryErrors = 0;

  for (const [summaryId, meta] of summariesToRecalc) {
    const { employeeId, enterpriseId, dateStr } = meta;
    const [y, m, d] = dateStr.split('-').map(Number);
    const startOfDayUTC = new Date(Date.UTC(y, m - 1, d, 0, 0, 0) - 330 * 60_000);
    const endOfDayUTC = new Date(startOfDayUTC.getTime() + 24 * 3600 * 1000);

    try {
      const daySessionsSnap = await db
        .collection('sessions')
        .where('employeeId', '==', employeeId)
        .where('startTime', '>=', admin.firestore.Timestamp.fromDate(startOfDayUTC))
        .where('startTime', '<', admin.firestore.Timestamp.fromDate(endOfDayUTC))
        .get();

      let summed = 0;
      let counted = 0;
      for (const sd of daySessionsSnap.docs) {
        const s = sd.data();
        if (s.status !== 'completed' && s.status !== 'auto_ended') continue;
        summed += Number(s.totalDistance) || 0;
        counted++;
      }
      summed = Math.round(summed * 100) / 100;

      await db.collection('dailySummaries').doc(summaryId).set(
        {
          totalDistance: summed,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          enterpriseId,
          employeeId,
        },
        { merge: true },
      );
      console.log(`  SUMMARY  ${summaryId}  sessions=${counted}  totalDistance=${summed}`);
      summariesWritten++;
    } catch (err) {
      console.error(`  SUMMARY-ERROR  ${summaryId}: ${err.message || err}`);
      summaryErrors++;
    }
  }

  console.log('\n[apply] === FINAL SUMMARY ===');
  console.log(JSON.stringify({
    totalSessionsQueried: sessionDocs.length,
    totalProcessed: processed,
    totalCorrected: corrected,
    totalSkippedNoChange: noChange,
    totalSkippedManualReview: skippedManualReview,
    sessionWriteErrors: writeErrors,
    totalDistanceRemovedKm: Math.round(distanceRemoved * 100) / 100,
    dailySummariesRecalculated: summariesToRecalc.size,
    dailySummariesWritten: summariesWritten,
    dailySummaryWriteErrors: summaryErrors,
  }, null, 2));

  process.exit(0);
})().catch((e) => {
  console.error('FATAL:', e);
  process.exit(1);
});
