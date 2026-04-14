/**
 * orphan_match_audit.js — read-only
 *
 * For each of 5 orphan UIDs, derive fingerprint:
 *   - enterpriseId
 *   - earliest/latest session startTime
 *   - most common location terms from activityLogs
 *   - session count, log count, photo count
 *
 * Then score every current user in that enterprise against the orphan by:
 *   - name match against the orphan's data sample (e.g. "Ronak Kumawat")
 *   - date-range overlap with orphan sessions
 *   - location area overlap (top locations)
 *
 * Output a ranked candidate list per orphan with confidence tier.
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

function topCounts(items, n = 5) {
  const counts = new Map();
  for (const it of items) {
    if (!it) continue;
    const key = String(it).trim();
    if (!key) continue;
    counts.set(key, (counts.get(key) || 0) + 1);
  }
  return [...counts.entries()].sort((a, b) => b[1] - a[1]).slice(0, n);
}

function extractTokens(text) {
  if (!text) return [];
  return String(text)
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .split(' ')
    .filter((t) => t.length >= 3);
}

async function fingerprint(orphanId) {
  const [sesSnap, actSnap, phoSnap] = await Promise.all([
    db.collection('sessions').where('employeeId', '==', orphanId).get(),
    db.collection('activityLogs').where('employeeId', '==', orphanId).limit(200).get(),
    db.collection('photos').where('employeeId', '==', orphanId).limit(100).get(),
  ]);

  const sessions = sesSnap.docs.map((d) => d.data());
  const logs = actSnap.docs.map((d) => d.data());
  const photos = phoSnap.docs.map((d) => d.data());

  let earliest = null;
  let latest = null;
  const enterpriseIds = new Set();
  for (const s of sessions) {
    const t = s.startTime?.toDate?.();
    if (t && (!earliest || t < earliest)) earliest = t;
    if (t && (!latest || t > latest)) latest = t;
    if (s.enterpriseId) enterpriseIds.add(s.enterpriseId);
  }
  if (enterpriseIds.size === 0) {
    for (const l of logs) if (l.enterpriseId) enterpriseIds.add(l.enterpriseId);
    for (const p of photos) if (p.enterpriseId) enterpriseIds.add(p.enterpriseId);
  }

  // Location terms from log.detail / log.metadata.address / photo.location
  const locationText = [];
  for (const l of logs) {
    if (l.detail) locationText.push(l.detail);
    if (l.metadata?.address) locationText.push(l.metadata.address);
    if (l.title) locationText.push(l.title);
  }
  for (const p of photos) {
    if (p.location) locationText.push(p.location);
    if (p.customerName) locationText.push(p.customerName);
    if (p.notes) locationText.push(p.notes);
  }

  // Name hints from photo customerName fields (sometimes employee name leaks)
  // and from any title/detail text
  const allText = locationText.join(' | ');
  const tokens = extractTokens(allText);
  const tokenCounts = new Map();
  for (const t of tokens) tokenCounts.set(t, (tokenCounts.get(t) || 0) + 1);

  return {
    orphanId,
    enterpriseIds: [...enterpriseIds],
    sessionCount: sessions.length,
    logCountSampled: logs.length,
    photoCountSampled: photos.length,
    earliest,
    latest,
    topLocations: topCounts(locationText, 8),
    tokens: [...tokenCounts.entries()].sort((a, b) => b[1] - a[1]).slice(0, 20),
    sessions,
  };
}

(async () => {
  console.log('Loading all users...');
  const usersSnap = await db.collection('users').get();
  const users = usersSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
  console.log(`  ${users.length} users loaded.\n`);

  for (const orphanId of ORPHANS) {
    console.log('='.repeat(78));
    console.log(`ORPHAN  ${orphanId}`);
    console.log('='.repeat(78));

    const fp = await fingerprint(orphanId);
    console.log(`  enterpriseId(s):   ${fp.enterpriseIds.join(', ') || '<none>'}`);
    console.log(`  total sessions:    ${fp.sessionCount}`);
    console.log(`  logs sampled:      ${fp.logCountSampled}`);
    console.log(`  photos sampled:    ${fp.photoCountSampled}`);
    console.log(`  earliest session:  ${fp.earliest ? fp.earliest.toISOString().slice(0, 10) : 'n/a'}`);
    console.log(`  latest session:    ${fp.latest ? fp.latest.toISOString().slice(0, 10) : 'n/a'}`);
    console.log(`  top locations (from logs/photos, sample-based):`);
    for (const [loc, n] of fp.topLocations) {
      const trunc = loc.length > 100 ? loc.slice(0, 100) + '…' : loc;
      console.log(`    ${n.toString().padStart(4)}  ${trunc}`);
    }
    console.log(`  top tokens: ${fp.tokens.map(([t, n]) => `${t}(${n})`).join(', ')}`);

    // Candidate users = same enterprise + name tokens overlap with orphan tokens
    const orphanTokens = new Set(fp.tokens.map(([t]) => t));
    const candidates = users.filter((u) => fp.enterpriseIds.includes(u.enterpriseId));
    const scored = [];
    for (const u of candidates) {
      const userTokens = extractTokens(u.name || '');
      const tokenOverlap = userTokens.filter((t) => orphanTokens.has(t));

      // Date overlap: we already have fp earliest/latest. Check if user has any
      // sessions and whether they overlap. For now use user doc createdAt as a proxy.
      const userCreated = u.createdAt?.toDate?.() ?? null;
      const userBeforeOrphanEnd = userCreated && fp.latest ? userCreated <= fp.latest : null;

      scored.push({
        user: u,
        nameTokenOverlap: tokenOverlap,
        userCreated,
        userBeforeOrphanEnd,
      });
    }

    // Also: for each candidate, query their sessions and see if any temporal overlap
    // with the orphan's date range
    const orphanStart = fp.earliest;
    const orphanEnd = fp.latest;

    for (const entry of scored) {
      const ses = await db
        .collection('sessions')
        .where('employeeId', '==', entry.user.id)
        .limit(200)
        .get();
      const uSessions = ses.docs.map((d) => d.data());
      let uEarliest = null;
      let uLatest = null;
      for (const s of uSessions) {
        const t = s.startTime?.toDate?.();
        if (t && (!uEarliest || t < uEarliest)) uEarliest = t;
        if (t && (!uLatest || t > uLatest)) uLatest = t;
      }
      entry.userSessionCount = uSessions.length;
      entry.userSessionsEarliest = uEarliest;
      entry.userSessionsLatest = uLatest;

      // Date range overlap (orphan data ends near when user starts, or fully continuous)
      let dateOverlapKind = 'none';
      if (orphanEnd && uEarliest) {
        const gapDays = Math.round((uEarliest - orphanEnd) / 86400000);
        if (gapDays >= -30 && gapDays <= 30) dateOverlapKind = `contiguous(±${gapDays}d)`;
        else if (uEarliest < orphanEnd && uLatest > orphanStart) dateOverlapKind = 'overlapping';
      }
      entry.dateOverlap = dateOverlapKind;
    }

    // Ranking heuristic
    const ranked = scored
      .map((e) => {
        let score = 0;
        const reasons = [];
        if (e.nameTokenOverlap.length > 0) {
          score += 100 * e.nameTokenOverlap.length;
          reasons.push(`name-tokens=[${e.nameTokenOverlap.join(',')}]`);
        }
        if (e.dateOverlap === 'contiguous(±0d)' || e.dateOverlap === 'contiguous(±1d)') {
          score += 50;
          reasons.push('very-close-date-continuation');
        } else if (e.dateOverlap.startsWith('contiguous')) {
          score += 20;
          reasons.push(e.dateOverlap);
        } else if (e.dateOverlap === 'overlapping') {
          // Overlapping is LESS suspicious if it's the same person — a person normally
          // doesn't have two UIDs active at once. Still worth noting.
          score += 5;
          reasons.push('date-ranges-overlap');
        }
        if (e.userSessionCount > 0 && fp.sessionCount > 0) {
          // Mild boost if both have session history
        }
        return { ...e, score, reasons };
      })
      .sort((a, b) => b.score - a.score);

    console.log(`\n  Candidates (sorted by score):`);
    const top = ranked.slice(0, 5);
    for (const r of top) {
      if (r.score === 0 && r.reasons.length === 0) continue;
      const u = r.user;
      const ue = r.userSessionsEarliest ? r.userSessionsEarliest.toISOString().slice(0, 10) : 'n/a';
      const ul = r.userSessionsLatest ? r.userSessionsLatest.toISOString().slice(0, 10) : 'n/a';
      console.log(`    score=${r.score.toString().padStart(3)}  ${u.id}  "${u.name || ''}"  phone=${u.phone || ''}  sessions=${r.userSessionCount}  range=${ue}..${ul}`);
      console.log(`         reasons: ${r.reasons.join(' | ')}`);
    }
    if (top.every((r) => r.score === 0)) {
      console.log('    (no scoring match. Listing all users in same enterprise for manual review:)');
      for (const entry of scored.slice(0, 12)) {
        const u = entry.user;
        const ue = entry.userSessionsEarliest ? entry.userSessionsEarliest.toISOString().slice(0, 10) : 'n/a';
        const ul = entry.userSessionsLatest ? entry.userSessionsLatest.toISOString().slice(0, 10) : 'n/a';
        console.log(`    -    ${u.id}  "${u.name || ''}"  phone=${u.phone || ''}  sessions=${entry.userSessionCount}  range=${ue}..${ul}`);
      }
    }
    console.log('');
  }

  process.exit(0);
})().catch((e) => {
  console.error('FATAL:', e);
  process.exit(1);
});
