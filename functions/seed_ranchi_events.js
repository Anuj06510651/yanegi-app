const admin = require('firebase-admin');

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

const isDryRun = process.argv.includes('--dry-run');

const baseLat = 23.3441;
const baseLng = 85.3096;
const now = new Date();

const hosts = [
  {
    id: 'ranchi_host_1',
    name: 'Aarav Singh',
    username: 'aarav_ranchi',
  },
  {
    id: 'ranchi_host_2',
    name: 'Kiara Verma',
    username: 'kiara_v',
  },
  {
    id: 'ranchi_host_3',
    name: 'Rohan Das',
    username: 'rohan_das',
  },
  {
    id: 'ranchi_host_4',
    name: 'Meera Jain',
    username: 'meera_j',
  },
  {
    id: 'ranchi_host_5',
    name: 'Yash Kumar',
    username: 'yash_k',
  },
];

const eventTemplates = [
  {
    title: 'Sunset Coffee Meetup',
    locationName: 'Upper Bazar Cafe Lane',
    description: 'Golden hour coffee and conversation with locals.',
    tags: ['chill', 'coffee', 'community'],
    emoji: '☕',
    hoursFromNow: 20,
    durationHours: 2,
    maxCapacity: 18,
  },
  {
    title: 'Rock Garden Morning Walk',
    locationName: 'Rock Garden, Ranchi',
    description: 'Guided wellness walk with stretch breaks.',
    tags: ['wellness', 'outdoor', 'walk'],
    emoji: '🌿',
    hoursFromNow: 10,
    durationHours: 1.5,
    maxCapacity: 25,
  },
  {
    title: 'Night Market Food Crawl',
    locationName: 'Main Road Night Market',
    description: 'Street food hop with a curated tasting list.',
    tags: ['food', 'nightlife', 'social'],
    emoji: '🌮',
    hoursFromNow: 30,
    durationHours: 3,
    maxCapacity: 30,
  },
  {
    title: 'Cricket in the Park',
    locationName: 'Morabadi Ground',
    description: 'Friendly cricket match, bring your own bat.',
    tags: ['sports', 'outdoor', 'cricket'],
    emoji: '🏏',
    hoursFromNow: 26,
    durationHours: 2.5,
    maxCapacity: 22,
  },
  {
    title: 'Art Jam: Local Sketch Walk',
    locationName: 'Tagore Hill Viewpoint',
    description: 'Sketching session with prompts and snacks.',
    tags: ['art', 'creative', 'outdoor'],
    emoji: '🎨',
    hoursFromNow: 36,
    durationHours: 2,
    maxCapacity: 16,
  },
  {
    title: 'Startup Stories Meetup',
    locationName: 'Lalpur Tech Hub',
    description: 'Lightning talks from Ranchi founders.',
    tags: ['networking', 'startup', 'talks'],
    emoji: '🚀',
    hoursFromNow: 40,
    durationHours: 2.5,
    maxCapacity: 40,
  },
  {
    title: 'Sunrise Yoga Flow',
    locationName: 'Kanke Dam Garden',
    description: 'Gentle yoga flow with breathwork.',
    tags: ['wellness', 'yoga', 'sunrise'],
    emoji: '🧘',
    hoursFromNow: 14,
    durationHours: 1.25,
    maxCapacity: 20,
  },
  {
    title: 'Live Indie Music Night',
    locationName: 'Ranchi Cultural Hub',
    description: 'Local indie bands with acoustic sets.',
    tags: ['music', 'nightlife', 'live'],
    emoji: '🎸',
    hoursFromNow: 44,
    durationHours: 3,
    maxCapacity: 60,
  },
  {
    title: 'Photography Walk',
    locationName: 'Panch Gagh Falls Trailhead',
    description: 'Capture nature shots with a guide.',
    tags: ['photography', 'outdoor', 'nature'],
    emoji: '📸',
    hoursFromNow: 54,
    durationHours: 2.5,
    maxCapacity: 15,
  },
  {
    title: 'Community Chess Night',
    locationName: 'Lower Bazar Community Hall',
    description: 'Chess ladders and rapid games.',
    tags: ['games', 'community', 'indoor'],
    emoji: '♟️',
    hoursFromNow: 28,
    durationHours: 2,
    maxCapacity: 24,
  },
  {
    title: 'Book Club: Modern Indian Fiction',
    locationName: 'Ranchi Central Library',
    description: 'Discussion circle with reading prompts.',
    tags: ['books', 'community', 'chill'],
    emoji: '📚',
    hoursFromNow: 48,
    durationHours: 2,
    maxCapacity: 20,
  },
  {
    title: 'Food Photography Workshop',
    locationName: 'Kokar Studio Loft',
    description: 'Hands-on workshop with lighting tips.',
    tags: ['workshop', 'photography', 'food'],
    emoji: '🍰',
    hoursFromNow: 62,
    durationHours: 2.5,
    maxCapacity: 14,
  },
  {
    title: 'Cycling Crew Ride',
    locationName: 'Doranda Loop',
    description: 'City loop ride at a relaxed pace.',
    tags: ['cycling', 'fitness', 'outdoor'],
    emoji: '🚴',
    hoursFromNow: 22,
    durationHours: 2,
    maxCapacity: 18,
  },
  {
    title: 'Open Mic Poetry Evening',
    locationName: 'Harmu Studio Cafe',
    description: 'Poetry, storytelling, and spoken word.',
    tags: ['poetry', 'community', 'nightlife'],
    emoji: '🎤',
    hoursFromNow: 32,
    durationHours: 2.5,
    maxCapacity: 28,
  },
  {
    title: 'Badminton Friendly Games',
    locationName: 'Bariatu Indoor Court',
    description: 'Doubles rotation with casual play.',
    tags: ['sports', 'indoor', 'badminton'],
    emoji: '🏸',
    hoursFromNow: 24,
    durationHours: 2,
    maxCapacity: 16,
  },
  {
    title: 'Cooking Jam: Jharkhand Flavors',
    locationName: 'Hatia Community Kitchen',
    description: 'Hands-on cooking and shared dinner.',
    tags: ['food', 'workshop', 'community'],
    emoji: '🥘',
    hoursFromNow: 58,
    durationHours: 3,
    maxCapacity: 12,
  },
  {
    title: 'Street Art & Mural Walk',
    locationName: 'Firayalal Chowk',
    description: 'Discover hidden murals with stories.',
    tags: ['art', 'walk', 'culture'],
    emoji: '🖌️',
    hoursFromNow: 34,
    durationHours: 2,
    maxCapacity: 20,
  },
  {
    title: 'Tech + Tea Roundtable',
    locationName: 'Circular Road Tea House',
    description: 'Casual chats about product and design.',
    tags: ['networking', 'tech', 'chill'],
    emoji: '🫖',
    hoursFromNow: 38,
    durationHours: 2,
    maxCapacity: 18,
  },
  {
    title: 'Bollywood Dance Session',
    locationName: 'Sainik Market Studio',
    description: 'High-energy dance warmups and choreo.',
    tags: ['dance', 'fitness', 'music'],
    emoji: '💃',
    hoursFromNow: 42,
    durationHours: 1.5,
    maxCapacity: 25,
  },
  {
    title: 'Weekend Picnic Social',
    locationName: 'Birsa Zoological Park Lawn',
    description: 'Bring snacks, we provide games.',
    tags: ['outdoor', 'community', 'family'],
    emoji: '🧺',
    hoursFromNow: 70,
    durationHours: 3,
    maxCapacity: 35,
  },
];

const locationOffsets = [
  [0.002, 0.001],
  [-0.001, 0.003],
  [0.004, -0.002],
  [-0.003, -0.001],
  [0.0015, -0.003],
  [0.0025, 0.004],
  [-0.0025, 0.0025],
  [0.0035, -0.004],
  [-0.004, 0.0035],
  [0.001, 0.002],
  [-0.0015, -0.0035],
  [0.002, -0.0015],
  [-0.002, 0.001],
  [0.003, 0.0025],
  [-0.003, -0.0025],
  [0.004, 0.0015],
  [-0.004, -0.0015],
  [0.0012, -0.0022],
  [-0.0018, 0.0028],
  [0.0028, -0.0012],
];

const buildEventId = (index) => `ranchi_event_${String(index + 1).padStart(2, '0')}`;

const getTimeLabel = (date) =>
  date.toLocaleTimeString('en-IN', {
    hour: 'numeric',
    minute: '2-digit',
  });

const events = eventTemplates.map((template, index) => {
  const host = hosts[index % hosts.length];
  const offset = locationOffsets[index];
  const lat = baseLat + offset[0];
  const lng = baseLng + offset[1];
  const startAt = new Date(now.getTime() + template.hoursFromNow * 60 * 60 * 1000);
  const endAt = new Date(startAt.getTime() + template.durationHours * 60 * 60 * 1000);

  return {
    eventId: buildEventId(index),
    host,
    title: template.title,
    description: template.description,
    locationName: template.locationName,
    tags: template.tags,
    emoji: template.emoji,
    maxCapacity: template.maxCapacity,
    lat,
    lng,
    startAt,
    endAt,
    timeLabel: getTimeLabel(startAt),
  };
});

const writeData = async () => {
  const batch = db.batch();
  const seededAt = admin.firestore.Timestamp.fromDate(new Date());

  for (const host of hosts) {
    const userRef = db.collection('users').doc(host.id);
    batch.set(
      userRef,
      {
        userId: host.id,
        name: host.name,
        username: host.username,
        usernameLower: host.username.toLowerCase(),
        bio: 'Local host in Ranchi',
        createdAt: seededAt,
        created_at: seededAt,
        updatedAt: seededAt,
        updated_at: seededAt,
      },
      { merge: true },
    );
  }

  for (const event of events) {
    const eventRef = db.collection('events').doc(event.eventId);
    const chatId = `grp_${event.eventId}`;
    const chatRef = db.collection('chats').doc(chatId);
    const participantRef = db
      .collection('event_participants')
      .doc(event.eventId)
      .collection('users')
      .doc(event.host.id);

    batch.set(
      eventRef,
      {
        eventId: event.eventId,
        hostId: event.host.id,
        hostName: event.host.name,
        host_name: event.host.name,
        title: event.title,
        description: event.description,
        activityType: event.tags[0] ?? 'general',
        location: event.locationName,
        locationName: event.locationName,
        lat: event.lat,
        lng: event.lng,
        locationGeoPoint: new admin.firestore.GeoPoint(event.lat, event.lng),
        approximateLocation: {
          lat: event.lat,
          lng: event.lng,
        },
        startAt: admin.firestore.Timestamp.fromDate(event.startAt),
        endAt: admin.firestore.Timestamp.fromDate(event.endAt),
        timezone: 'Asia/Kolkata',
        ageRange: {
          min: 18,
          max: 35,
        },
        ageRangeLabel: 'Age: 18–35',
        hideExactLocationUntilApproved: false,
        participants: [event.host.id],
        participantsCount: 1,
        maxCapacity: event.maxCapacity,
        maxParticipants: event.maxCapacity,
        visibility: 'public',
        isApprovalRequired: false,
        eventAvatar: event.emoji,
        emoji: event.emoji,
        bannerImagePath: '',
        bannerUrl: '',
        time: event.timeLabel,
        tags: event.tags,
        vibes: event.tags,
        categories: event.tags,
        chatId,
        status: 'active',
        isActive: true,
        isDeleted: false,
        createdAt: seededAt,
        created_at: seededAt,
        updatedAt: seededAt,
        updated_at: seededAt,
      },
      { merge: true },
    );

    batch.set(
      chatRef,
      {
        chatId,
        type: 'group',
        eventId: event.eventId,
        participantIds: [event.host.id],
        createdBy: event.host.id,
        createdAt: seededAt,
        updatedAt: seededAt,
        isActive: true,
        lastMessage: '',
        lastMessageAt: seededAt,
      },
      { merge: true },
    );

    batch.set(
      participantRef,
      {
        userId: event.host.id,
        eventId: event.eventId,
        status: 'active',
        isVisible: true,
        joinedAt: seededAt,
        updatedAt: seededAt,
      },
      { merge: true },
    );
  }

  if (isDryRun) {
    console.log('[Dry run] Prepared batches for Ranchi events:', events.length);
    return;
  }

  await batch.commit();
  console.log(`Seeded ${events.length} Ranchi events.`);
};

writeData().catch((error) => {
  console.error('Failed to seed Ranchi events:', error);
  process.exitCode = 1;
});
