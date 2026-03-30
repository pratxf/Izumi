const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');

const credFile = path.join(
  process.env.APPDATA,
  'firebase',
  'aasmandigitals_gmail_com_application_default_credentials.json'
);
process.env.GOOGLE_APPLICATION_CREDENTIALS = credFile;
admin.initializeApp({ projectId: 'izumi-6e087' });
const db = admin.firestore();

async function main() {
  const usersSnap = await db.collection('users').get();
  const uidToName = {};
  usersSnap.docs.forEach(doc => {
    const d = doc.data();
    uidToName[doc.id] = d.name || d.displayName || '?';
  });

  let allPhotos = [];
  let last = null;
  while (true) {
    let q = db.collection('photos').limit(500);
    if (last) q = q.startAfter(last);
    const snap = await q.get();
    if (snap.empty) break;
    snap.docs.forEach(d => allPhotos.push(d.data()));
    last = snap.docs[snap.docs.length - 1];
    if (snap.size < 500) break;
  }

  const byEmp = {};
  allPhotos.forEach(p => {
    const id = p.employeeId || 'MISSING';
    byEmp[id] = (byEmp[id] || 0) + 1;
  });

  const photosByEmployee = Object.entries(byEmp)
    .sort((a, b) => b[1] - a[1])
    .map(([id, cnt]) => ({
      count: cnt,
      uid: id,
      name: uidToName[id] || 'NOT IN USERS',
    }));

  const dsSnap = await db.collection('dailySummaries').get();
  let totalDist = 0;
  const outliers = [];
  dsSnap.docs.forEach(doc => {
    const d = doc.data();
    const dist = d.totalDistance || 0;
    totalDist += dist;
    if (dist > 500) {
      outliers.push({
        emp: uidToName[d.employeeId] || d.employeeId,
        dist,
        date: d.date ? new Date(d.date._seconds * 1000).toISOString().slice(0, 10) : '?',
      });
    }
  });

  const result = {
    totalUsers: usersSnap.size,
    totalPhotos: allPhotos.length,
    photosByEmployee,
    totalSummaries: dsSnap.size,
    totalDistanceSum: totalDist.toFixed(2),
    distanceOutliers: outliers,
  };

  fs.writeFileSync(
    path.join(__dirname, 'audit_result.json'),
    JSON.stringify(result, null, 2)
  );
  console.log('Done. Written to audit_result.json');
  process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
