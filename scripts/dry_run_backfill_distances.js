/**
 * Mirrors functions/src/callable/backfill_session_distances.ts DRY_RUN behavior
 * but runs locally via firebase-admin against production Firestore, so we can
 * preview the effect without needing to auth a deployed callable.
 *
 * Same thresholds and helpers as the Cloud Function:
 *   - MAX_REALISTIC_SPEED_KMH = 120
 *   - MAX_SEGMENT_DISTANCE_KM = 100
 *   - MAX_CORRECTED_DISTANCE_KM = 300 (safety cap — skipped for review)
 *   - Processes sessions with status in ('auto_ended', 'completed' && totalDistance > 500)
 *
 * Prints per-session rows + final summary. No Firestore writes — pure read.
 */

const admin = require('firebase-admin');
const path = require('path');

process.env.GOOGLE_APPLICATION_CREDENTIALS = path.join(
  process.env.APPDATA,
  'firebase',
  'aasmandigitals_gmail_com_application_default_credentials.json',
);

admin.initializeApp({ projectId: 'izumi-6e087' });

const DRY_RUN = true;
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
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

function calculateTrustedDistanceKm(locations) {
  let totalDistance = 0;
  let skippedSegments = 0;
  for (let i = 1; i < locations.length; i++) {
    const prev = locations[i - 1];
    const curr = locations[i];
    const seg = haversineDistanceKm(
      prev.latitude, prev.longitude, curr.latitude, curr.longitude,
    );
    const prevTs = prev.timestamp?.toMillis?.() ?? 0;
    const currTs = curr.timestamp?.toMillis?.() ?? 0;
    const elapsedHours = prevTs && currTs && currTs > prevTs
      ? (currTs - prevTs) / 3_600_000
      : 0;
    const impliedSpeed = elapsedHours > 0 ? seg / elapsedHours : Infinity;
    if (seg > MAX_SEGMENT_DISTANCE_KM || impliedSpeed > MAX_REALISTIC_SPEED_KMH) {
      skippedSegments++;
      continue;
    }
    totalDistance += seg;
  }
  return { totalDistance: Math.round(totalDistance * 100) / 100, skippedSegments };
}

function formatDateIST(timestamp) {
  const date = timestamp.toDate();
  const istOffset = 330;
  const utcMs = date.getTime() + date.getTimezoneOffset() * 60_000;
  const istDate = new Date(utcMs + istOffset * 60_000);
  const y = istDate.getFullYear();
  const m = String(istDate.getMonth() + 1).padStart(2, '0');
  const d = String(istDate.getDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

(async () => {
  const db = admin.firestore();
  console.log(`[backfill] DRY_RUN=${DRY_RUN}`);
  console.log('[backfill] Querying candidate sessions...');

  // Avoid composite index on (status, totalDistance) by splitting into two
  // single-field queries and filtering in memory.
  const [autoEnded, inflatedAnyStatus] = await Promise.all([
    db.collection('sessions').where('status', '==', 'auto_ended').get(),
    db.collection('sessions').where('totalDistance', '>', 500).get(),
  ]);
  const inflatedCompleted = {
    size: inflatedAnyStatus.docs.filter((d) => d.data().status === 'completed').length,
    docs: inflatedAnyStatus.docs.filter((d) => d.data().status === 'completed'),
  };

  const seen = new Set();
  const sessionDocs = [];
  for (const d of [...autoEnded.docs, ...inflatedCompleted.docs]) {
    if (seen.has(d.id)) continue;
    seen.add(d.id);
    sessionDocs.push(d);
  }

  console.log(`[backfill] auto_ended: ${autoEnded.size}, completed>500km: ${inflatedCompleted.size}, unique: ${sessionDocs.length}\n`);

  let processed = 0;
  let corrected = 0;
  let noChange = 0;
  let skippedManualReview = 0;
  let distanceRemoved = 0;
  const summariesToRecalc = new Map();

  for (const sDoc of sessionDocs) {
    const s = sDoc.data();
    const oldDistance = Number(s.totalDistance) || 0;
    const employeeId = s.employeeId;
    const enterpriseId = s.enterpriseId;
    const startTime = s.startTime;
    if (!employeeId || !startTime) {
      console.log(`  SKIP  missing data  sid=${sDoc.id}`);
      processed++;
      continue;
    }

    const locs = await db.collection('sessions').doc(sDoc.id).collection('locations').orderBy('timestamp', 'asc').get();
    const locations = locs.docs.map((d) => d.data());

    let correctedDistance = 0;
    let skippedSegments = 0;
    if (locations.length >= 2) {
      const r = calculateTrustedDistanceKm(locations);
      correctedDistance = r.totalDistance;
      skippedSegments = r.skippedSegments;
    }

    processed++;
    const dateStr = formatDateIST(startTime);
    const delta = Math.abs(oldDistance - correctedDistance);

    if (correctedDistance > MAX_CORRECTED_DISTANCE_KM) {
      console.log(`  MANUAL-REVIEW  sid=${sDoc.id}  emp=${employeeId}  date=${dateStr}  status=${s.status}  old=${oldDistance}  corrected=${correctedDistance}  pts=${locations.length}`);
      skippedManualReview++;
      continue;
    }
    if (delta < 0.1) {
      noChange++;
      continue;
    }

    console.log(`  CORRECT  sid=${sDoc.id}  emp=${employeeId}  date=${dateStr}  status=${s.status}  old=${oldDistance}  corrected=${correctedDistance}  removed=${(oldDistance - correctedDistance).toFixed(2)}  pts=${locations.length}  skipped=${skippedSegments}`);
    corrected++;
    distanceRemoved += oldDistance - correctedDistance;
    summariesToRecalc.set(`${employeeId}_${dateStr}`, { employeeId, enterpriseId, dateStr });
  }

  console.log('\n[backfill] === SUMMARY ===');
  console.log(JSON.stringify({
    dryRun: DRY_RUN,
    totalSessionsQueried: sessionDocs.length,
    totalProcessed: processed,
    totalCorrected: corrected,
    totalSkippedNoChange: noChange,
    totalSkippedManualReview: skippedManualReview,
    totalDistanceRemovedKm: Math.round(distanceRemoved * 100) / 100,
    dailySummariesRecalculated: summariesToRecalc.size,
  }, null, 2));

  process.exit(0);
})().catch((e) => {
  console.error('FATAL:', e);
  process.exit(1);
});
