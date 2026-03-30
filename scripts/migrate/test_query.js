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
  const sohanUid = 'Fpln4OTAJ4Oi9XZVBISEyMggybJ2';
  // March 1 IST = Feb 28 18:30 UTC
  const start = new Date('2026-02-28T18:30:00Z');
  const end = new Date();

  console.log('Query params:');
  console.log('  UID:', sohanUid);
  console.log('  Start:', start.toISOString());
  console.log('  End:', end.toISOString());

  // Test 1: with range filter (what getPhotosByEmployeeIds does)
  try {
    const snap = await db.collection('photos')
      .where('employeeId', '==', sohanUid)
      .where('timestamp', '>=', admin.firestore.Timestamp.fromDate(start))
      .where('timestamp', '<=', admin.firestore.Timestamp.fromDate(end))
      .orderBy('timestamp', 'desc')
      .limit(150)
      .get();
    console.log('\nTest 1 (with range filter): Photos = ', snap.size);
  } catch (e) {
    console.error('\nTest 1 FAILED:', e.message);
  }

  // Test 2: without range filter (what Unfiltered does)
  try {
    const snap2 = await db.collection('photos')
      .where('employeeId', '==', sohanUid)
      .orderBy('timestamp', 'desc')
      .limit(10)
      .get();
    console.log('Test 2 (orderBy only): Photos = ', snap2.size);
    if (snap2.size > 0) {
      const d = snap2.docs[0].data();
      const ts = d.timestamp ? d.timestamp.toDate().toISOString() : 'no timestamp';
      console.log('  First photo timestamp:', ts);
    }
  } catch (e) {
    console.error('Test 2 FAILED:', e.message);
  }

  // Test 3: no filters at all
  try {
    const snap3 = await db.collection('photos')
      .where('employeeId', '==', sohanUid)
      .get();
    console.log('Test 3 (no sort, no range): Photos = ', snap3.size);
  } catch (e) {
    console.error('Test 3 FAILED:', e.message);
  }

  process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });
