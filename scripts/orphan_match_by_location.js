/**
 * orphan_match_by_location.js — read-only
 *
 * Stronger match heuristic: extracts location-area tokens (city/colony names,
 * not generic words) from orphan's activity logs + photos, and compares
 * against every current user's activity logs + photos. The user whose
 * territory overlaps most with the orphan is the best candidate.
 *
 * Two employees in the same enterprise rarely share the same set of unique
 * neighborhood/village names — location overlap is a much stronger signal
 * than date-range contiguity (everyone is active in the same overall window).
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

const ORPHANS = [
  '7lcl0IxCrkhtoT9AjHKFPz6gCFz2',
  'EwVF1ZtQ7hO0SkqUnDWrws2jy2K2',
  'CLuXh7VGuhgHyRMmR2qFpvx8unH2',
  'S2WLdvgSDYTg2fhnzqRi0XULXcv2',
  'KvzENlCWKugUCtAuJ2Ak7KiiasE3',
];

const GENERIC_WORDS = new Set([
  'location', 'tracking', 'update', 'tracked', 'session', 'started', 'ended',
  'auto', 'services', 'restored', 'recovered', 'interrupted', 'checking',
  'lost', 'the', 'employee', 'field', 'photo', 'captured', 'distributor',
  'farmer', 'testing', 'checked', 'watermelon', 'lat', 'lng', 'sector',
  'new', 'grain', 'market', 'duration', 'out', 'was', 'cvcvv', 'road',
  'nagar', 'colony', 'town', 'vihar', 'street', 'area', 'near', 'main',
  'chowk', 'sadar', 'market', 'bazar',
]);

function extractPlaceTokens(text) {
  if (!text) return [];
  return String(text)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .split(' ')
    .filter((t) => t.length >= 4 && !GENERIC_WORDS.has(t) && !/^\d+$/.test(t));
}

async function extractPlacesForEmployee(empId) {
  const [logsSnap, photosSnap] = await Promise.all([
    db.collection('activityLogs').where('employeeId', '==', empId).limit(300).get(),
    db.collection('photos').where('employeeId', '==', empId).limit(100).get(),
  ]);
  const textBlob = [];
  for (const d of logsSnap.docs) {
    const l = d.data();
    if (l.detail) textBlob.push(l.detail);
    if (l.metadata?.address) textBlob.push(l.metadata.address);
  }
  for (const d of photosSnap.docs) {
    const p = d.data();
    if (p.location) textBlob.push(p.location);
  }
  const tokens = textBlob.flatMap(extractPlaceTokens);
  const counts = new Map();
  for (const t of tokens) counts.set(t, (counts.get(t) || 0) + 1);
  // Return tokens sorted by frequency, with their counts
  return [...counts.entries()].sort((a, b) => b[1] - a[1]);
}

function overlapScore(orphanPlaces, userPlaces) {
  // orphanPlaces / userPlaces are [ [token, count], ... ]
  const orphanMap = new Map(orphanPlaces);
  const userMap = new Map(userPlaces);
  let score = 0;
  const shared = [];
  for (const [token, oCount] of orphanMap) {
    const uCount = userMap.get(token);
    if (uCount) {
      // Jaccard-style weighting: tokens appearing in both contribute by min count
      const w = Math.min(oCount, uCount);
      score += w;
      shared.push([token, oCount, uCount]);
    }
  }
  shared.sort((a, b) => b[1] + b[2] - (a[1] + a[2]));
  return { score, shared: shared.slice(0, 8) };
}

(async () => {
  console.log('Loading users...');
  const usersSnap = await db.collection('users').get();
  const users = usersSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
  console.log(`  ${users.length} users\n`);

  console.log('Building place fingerprint for each current user (this takes a minute)...');
  const userPlaces = new Map();
  for (const u of users) {
    try {
      const places = await extractPlacesForEmployee(u.id);
      userPlaces.set(u.id, places);
      const top = places.slice(0, 5).map(([t, c]) => `${t}(${c})`).join(',');
      console.log(`  ${u.id}  "${u.name || ''}"  top=${top || '<none>'}`);
    } catch (e) {
      console.log(`  ${u.id}  ERROR: ${e.message}`);
    }
  }

  console.log('\n' + '='.repeat(78));
  console.log('ORPHAN MATCHING BY LOCATION-TERM OVERLAP');
  console.log('='.repeat(78));

  for (const orphanId of ORPHANS) {
    const orphanPlaces = await extractPlacesForEmployee(orphanId);
    console.log(`\nOrphan: ${orphanId}`);
    console.log(`  orphan top places: ${orphanPlaces.slice(0, 8).map(([t, c]) => `${t}(${c})`).join(', ') || '<none>'}`);
    if (orphanPlaces.length === 0) {
      console.log('  (no place tokens — cannot match)');
      continue;
    }

    const scored = users.map((u) => {
      const uPlaces = userPlaces.get(u.id) || [];
      const r = overlapScore(orphanPlaces, uPlaces);
      return { user: u, score: r.score, shared: r.shared };
    });
    scored.sort((a, b) => b.score - a.score);

    console.log('  top candidates by place overlap:');
    const top = scored.slice(0, 5).filter((c) => c.score > 0);
    if (top.length === 0) {
      console.log('    (no place-term overlap with any current user)');
    } else {
      for (const c of top) {
        const sh = c.shared.map(([t, o, u]) => `${t}(o:${o}/u:${u})`).join(', ');
        console.log(`    score=${c.score.toString().padStart(4)}  ${c.user.id}  "${c.user.name || ''}"  phone=${c.user.phone || ''}`);
        console.log(`         shared: ${sh}`);
      }
    }
  }

  process.exit(0);
})().catch((e) => {
  console.error('FATAL:', e);
  process.exit(1);
});
