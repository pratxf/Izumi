/**
 * Photo Audit + Complete Migration Script
 * ========================================
 * 1. Counts photos per employee
 * 2. Migrates old UID → new UID for ALL collections
 * 3. Finds any photos with unlinked/orphaned IDs
 */

const admin = require('firebase-admin');
const path = require('path');

const credFile = path.join(
  process.env.APPDATA,
  'firebase',
  'aasmandigitals_gmail_com_application_default_credentials.json'
);
process.env.GOOGLE_APPLICATION_CREDENTIALS = credFile;

admin.initializeApp({ projectId: 'izumi-6e087' });
const db = admin.firestore();

const MIGRATION_MAP = {
  '46K2pNpUQzTb0t3Q6O3n': '11nz0qXwxvdzEvzLP2d94ir03gx2', // Sandeep Kumar
  'xny5HhjQuCLoWbyfmCna': '7QT4wsLwckhc2rYwHBzNksfiNMI2', // Sudhir Poonia
  'gsrTwXETD7eqKwQGj6sH': 'EwVF1ZtQ7hO0SkqUnDWrws2jy2K2', // aman rana
  'ih5lXPZS0AsiSjS27oLq': 'S53wcUgoILOyYlt5FAKaNGmvWRo2', // Prem Narayan Malviya
  'SiBZ820fn1x8K5bjwrqG': 'VW3SmRHZxVcsM1QkYwWex6WeOIl2', // Izumi
  'GWsLEyvTcxkJAtxrw4RA': 'XEoQbxo14HZixaUbrCoOHhcXq7m2', // Ajay Momi
  'NhXhUGgMDOVPN9zOgZsb': 'ZhRoRWiFfdVd9nmSDrgUS09aGKu1', // Vikas Rana
  's4qag9x8Zfz3xred9Cjy': 'iLVuFY5v86RXTWPUcv7yrVFe7io1', // Vinod Rana
  'zuYsENp5Nj4xsWWfUWZH': 'nkRRVkDApITJTRgHt8plD598m8h2', // Vinay Sharma
  's2FTd8Ckykmd9baN2UbV': 'tKg85ookUybRT0UkVc4O7E3ZJjJ3', // Pawan Kumar Rana
  'VIwImKACa4SlfRF8OYyZ': 'tMou6tAIiuVWOfNo4LAUhFYLo6T2', // Aditya Rana
};

const KNOWN_CURRENT_UIDS = new Set([
  '11nz0qXwxvdzEvzLP2d94ir03gx2', '7QT4wsLwckhc2rYwHBzNksfiNMI2',
  'EwVF1ZtQ7hO0SkqUnDWrws2jy2K2', 'S53wcUgoILOyYlt5FAKaNGmvWRo2',
  'VW3SmRHZxVcsM1QkYwWex6WeOIl2', 'XEoQbxo14HZixaUbrCoOHhcXq7m2',
  'ZhRoRWiFfdVd9nmSDrgUS09aGKu1', 'iLVuFY5v86RXTWPUcv7yrVFe7io1',
  'nkRRVkDApITJTRgHt8plD598m8h2', 'tKg85ookUybRT0UkVc4O7E3ZJjJ3',
  'tMou6tAIiuVWOfNo4LAUhFYLo6T2', '7lcl0IxCrkhtoT9AjHKFPz6gCFz2',
  'Fpln4OTAJ4Oi9XZVBISEyMggybJ2', 'NqNRINy8YJUCrenZr5LxdPzH5Xk2',
  'CLuXh7VGuhgHyRMmR2qFpvx8unH2', 'p9yInMBoMbMPOsQYmzzLzT7zNyd2',
  'qjBnft2fj0f63LcLQiLzCzcjTwi1', 'ZhRoRWiFfdVd9nmSDrgUS09aGKu1',
]);

const OLD_IDS = Object.keys(MIGRATION_MAP);
const COLLECTIONS = ['photos', 'sessions', 'activityLogs', 'dailySummaries'];

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function getAllDocsFromCollection(collectionName) {
  const allDocs = [];
  let lastDoc = null;

  while (true) {
    let query = db.collection(collectionName).limit(500);
    if (lastDoc) query = query.startAfter(lastDoc);

    const snap = await query.get();
    if (snap.empty) break;

    for (const doc of snap.docs) allDocs.push(doc);
    lastDoc = snap.docs[snap.docs.length - 1];

    if (snap.size < 500) break;
    await sleep(200);
  }

  return allDocs;
}

async function auditPhotos() {
  console.log('\n🔎 Auditing photos collection...');
  const allPhotos = await getAllDocsFromCollection('photos');
  console.log(`   Total photos in Firestore: ${allPhotos.length}`);

  const byEmployee = {};
  const orphaned = [];

  for (const doc of allPhotos) {
    const empId = doc.data().employeeId;
    if (!empId) { orphaned.push(doc.id); continue; }
    byEmployee[empId] = (byEmployee[empId] || 0) + 1;
    if (MIGRATION_MAP[empId]) {
      console.log(`   ⚠️  Photo ${doc.id} still has old UID: ${empId}`);
    }
  }

  console.log('\n   Photos per employee:');
  for (const [empId, count] of Object.entries(byEmployee).sort((a, b) => b[1] - a[1])) {
    const isOld = MIGRATION_MAP[empId] ? ' ← OLD UID (needs migration)' : '';
    const isCurrent = KNOWN_CURRENT_UIDS.has(empId) ? '' : ' ← UNKNOWN UID';
    console.log(`     ${empId}: ${count} photos${isOld}${isCurrent}`);
  }

  if (orphaned.length > 0) {
    console.log(`\n   Orphaned (no employeeId): ${orphaned.join(', ')}`);
  }

  return allPhotos;
}

async function migrateCollection(collectionName) {
  console.log(`\n📂 Migrating: ${collectionName}`);
  let totalFound = 0;
  let totalUpdated = 0;

  // Query using batches of 10 for whereIn
  for (let i = 0; i < OLD_IDS.length; i += 10) {
    const batchIds = OLD_IDS.slice(i, i + 10);

    const snapshot = await db.collection(collectionName)
      .where('employeeId', 'in', batchIds)
      .get();

    if (snapshot.empty) continue;

    totalFound += snapshot.size;
    console.log(`   Found ${snapshot.size} docs with old UIDs`);

    // Commit in batches of 499
    for (let j = 0; j < snapshot.docs.length; j += 499) {
      const writeBatch = db.batch();
      const chunk = snapshot.docs.slice(j, j + 499);

      for (const doc of chunk) {
        const oldId = doc.data().employeeId;
        const newId = MIGRATION_MAP[oldId];
        if (!newId) continue;
        writeBatch.update(doc.ref, { employeeId: newId });
        console.log(`     ✏️  ${doc.id}: ${oldId} → ${newId}`);
      }

      await writeBatch.commit();
      totalUpdated += chunk.length;
      console.log(`     ✅ Committed ${chunk.length} updates`);
      await sleep(300);
    }
  }

  console.log(`   📊 ${collectionName}: found=${totalFound}, updated=${totalUpdated}`);
  return { totalFound, totalUpdated };
}

async function main() {
  // 1. Audit photos first
  await auditPhotos();

  // 2. Migrate all collections  
  console.log('\n\n🚀 Starting Migration across all collections...');
  const summary = {};
  for (const col of COLLECTIONS) {
    summary[col] = await migrateCollection(col);
    await sleep(500);
  }

  // 3. Print summary
  console.log('\n\n═══════════════════════════════════════════');
  console.log('✅ Migration Complete — Summary');
  console.log('═══════════════════════════════════════════');
  for (const [col, stats] of Object.entries(summary)) {
    console.log(`${col}: found=${stats.totalFound}, updated=${stats.totalUpdated}`);
  }
  process.exit(0);
}

main().catch(err => {
  console.error('💥 Error:', err);
  process.exit(1);
});
