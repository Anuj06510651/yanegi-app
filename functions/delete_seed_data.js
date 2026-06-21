/**
 * Deletes all data created by seed_ranchi_events.js.
 *
 * Usage (from the functions/ directory):
 *   node delete_seed_data.js                 — live delete
 *   node delete_seed_data.js --dry-run       — print what would be deleted, no writes
 *
 * Deletes:
 *   events/ranchi_event_01 … ranchi_event_20
 *   chats/grp_ranchi_event_01 … grp_ranchi_event_20
 *   event_participants/ranchi_event_01/users/ranchi_host_* (and siblings)
 *   users/ranchi_host_1 … ranchi_host_5
 */

const admin = require('firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp({ projectId: process.env.FIREBASE_PROJECT_ID || 'yanegi-684f9' });
}

const db = admin.firestore();
const isDryRun = process.argv.includes('--dry-run');

const DUMMY_HOST_IDS = [
  'ranchi_host_1',
  'ranchi_host_2',
  'ranchi_host_3',
  'ranchi_host_4',
  'ranchi_host_5',
];

const DUMMY_EVENT_IDS = Array.from({ length: 20 }, (_, i) =>
  `ranchi_event_${String(i + 1).padStart(2, '0')}`,
);

const log = (msg) => console.log(`[${isDryRun ? 'DRY-RUN' : 'DELETE'}] ${msg}`);

async function deleteSubcollection(parentRef, subcollection) {
  const snap = await parentRef.collection(subcollection).get();
  if (snap.empty) return 0;
  const batch = db.batch();
  for (const doc of snap.docs) {
    log(`  subcollection doc: ${doc.ref.path}`);
    if (!isDryRun) batch.delete(doc.ref);
  }
  if (!isDryRun) await batch.commit();
  return snap.size;
}

async function run() {
  let total = 0;

  // 1. Events + their chats + event_participants subcollections
  for (const eventId of DUMMY_EVENT_IDS) {
    const eventRef = db.collection('events').doc(eventId);
    const chatRef = db.collection('chats').doc(`grp_${eventId}`);
    const participantsParent = db.collection('event_participants').doc(eventId);

    // Delete participant subcollection docs
    const subCount = await deleteSubcollection(participantsParent, 'users');
    if (subCount > 0) {
      log(`event_participants/${eventId}/users — ${subCount} doc(s)`);
      total += subCount;
    }

    // Delete the event_participants parent doc itself (if it exists)
    const ppSnap = await participantsParent.get();
    if (ppSnap.exists) {
      log(`event_participants/${eventId}`);
      if (!isDryRun) await participantsParent.delete();
      total++;
    }

    // Delete chat
    const chatSnap = await chatRef.get();
    if (chatSnap.exists) {
      log(`chats/grp_${eventId}`);
      if (!isDryRun) await chatRef.delete();
      total++;
    }

    // Delete event
    const eventSnap = await eventRef.get();
    if (eventSnap.exists) {
      log(`events/${eventId}`);
      if (!isDryRun) await eventRef.delete();
      total++;
    }
  }

  // 2. Dummy host user docs
  for (const hostId of DUMMY_HOST_IDS) {
    const userRef = db.collection('users').doc(hostId);
    const snap = await userRef.get();
    if (snap.exists) {
      log(`users/${hostId}`);
      if (!isDryRun) await userRef.delete();
      total++;
    }
  }

  console.log(`\n${isDryRun ? 'Would delete' : 'Deleted'} ${total} document(s).`);
  if (isDryRun) {
    console.log('\nRe-run without --dry-run to apply.');
  }
}

run().catch((err) => {
  console.error('Error:', err);
  process.exit(1);
});
