// Quick audit of dailySummaries data
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

async function main() {
  const snap = await db.collection('dailySummaries').limit(20).get();
  console.log(`Total docs: ${snap.size}`);
  let totalDist = 0;
  snap.docs.forEach(doc => {
    const d = doc.data();
    console.log(`  emp=${d.employeeId?.slice(0,8)} date=${d.date?.toDate?.()?.toISOString?.()?.slice(0,10)} duration=${d.totalDuration}s distance=${d.totalDistance} photos=${d.photosCount}`);
    totalDist += d.totalDistance || 0;
  });
  console.log(`Sum of distance in first 20: ${totalDist}`);

  // Check photo timestamps distribution
  console.log('\n--- Photo timestamp distribution ---');
  const photos = await db.collection('photos').limit(300).get();
  const byMonth = {};
  photos.docs.forEach(doc => {
    const ts = doc.data().timestamp?.toDate?.();
    if (!ts) return;
    const key = `${ts.getFullYear()}-${String(ts.getMonth()+1).padStart(2,'0')}`;
    byMonth[key] = (byMonth[key] || 0) + 1;
  });
  console.log('Photos by month:', JSON.stringify(byMonth, null, 2));

  process.exit(0);
}
main().catch(e => { console.error(e); process.exit(1); });
