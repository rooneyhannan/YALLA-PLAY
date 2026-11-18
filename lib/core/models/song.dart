class Song {
  final String id;
  final String title;
  final String artist;
  final String category;
  final String image;
  final String difficulty;
  final bool isPremium;

  /// Name of the song's chart in assets/songs/, when it has one.
  final String? chart;

  /// The chart itself, a `yalla-song/1` JSON text, for a song added from
  /// Yalla Studio on this device.
  final String? source;
  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.category,
    required this.image,
    this.difficulty = 'مبتدئ',
    this.isPremium = false,
    this.chart,
    this.source,
  });
  bool get hasChart => chart != null || source != null;
}

/// [entries] with the songs that have a chart of their own first, and
/// otherwise in their order: the others are not available yet.
List<Song> playableFirst(Iterable<Song> entries) => [
  ...entries.where((s) => s.hasChart),
  ...entries.where((s) => !s.hasChart),
];

/// The app's songs, all Arabic. Only those with a chart can be played; the
/// others say that they are not available yet.
const songs = <Song>[
  Song(
    id: 'badak',
    title: 'بعدك على بالي',
    artist: 'فيروز',
    category: 'طرب',
    image: 's1_2.png',
    chart: 'badak',
  ),
  Song(
    id: 'enta-omri',
    title: 'إنت عمري',
    artist: 'أم كلثوم',
    category: 'طرب',
    image: 's2_1.png',
    isPremium: true,
  ),
  Song(
    id: 'lamma-bada',
    title: 'لما بدا يتثنى',
    artist: 'موشح تراثي',
    category: 'كلاسيكي',
    image: 's2_2.png',
    difficulty: 'متوسط',
    isPremium: true,
    chart: 'lamma-bada',
  ),
  Song(
    id: 'ahwak',
    title: 'أهواك',
    artist: 'عبد الحليم حافظ',
    category: 'طرب',
    image: 's2_3.png',
    isPremium: true,
  ),
  Song(
    id: 'zourouni',
    title: 'زوروني كل سنة مرة',
    artist: 'سيد درويش',
    category: 'كلاسيكي',
    image: 's2_4.png',
    difficulty: 'متقدم',
    isPremium: true,
  ),
  Song(
    id: 'tamally',
    title: 'تملي معاك',
    artist: 'عمرو دياب',
    category: 'بوب',
    image: 's2_1.png',
    difficulty: 'متوسط',
  ),
  Song(
    id: 'nassam',
    title: 'نسم علينا الهوى',
    artist: 'فيروز',
    category: 'طرب',
    image: 's1_5.png',
  ),
  Song(
    id: 'kadim',
    title: 'زيديني عشقاً',
    artist: 'كاظم الساهر',
    category: 'طرب',
    image: 's2_0.png',
    difficulty: 'متقدم',
  ),
  Song(
    id: '3daqat',
    title: 'ثلاث دقات',
    artist: 'أبو ويسرا',
    category: 'بوب',
    image: 's1_3.png',
  ),
  Song(
    id: 'abdelkader',
    title: 'عبد القادر',
    artist: 'الشاب خالد',
    category: 'راي',
    image: 's1_7.png',
    isPremium: true,
  ),
  Song(
    id: 'nour-el-ein',
    title: 'نور العين',
    artist: 'عمرو دياب',
    category: 'بوب',
    image: 's2_2.png',
    isPremium: true,
  ),
  Song(
    id: 'qariat',
    title: 'قارئة الفنجان',
    artist: 'عبد الحليم حافظ',
    category: 'طرب',
    image: 's1_6.png',
    difficulty: 'متوسط',
    isPremium: true,
  ),
  Song(
    id: 'ana-lahabibi',
    title: 'أنا لحبيبي',
    artist: 'فيروز',
    category: 'طرب',
    image: 's1_3.png',
    difficulty: 'متوسط',
  ),
  Song(
    id: 'sana-helwa',
    title: 'سنة حلوة يا جميل',
    artist: 'محمد فوزي',
    category: 'كلاسيكي',
    image: 's2_7.png',
  ),
  Song(
    id: 'rayah',
    title: 'يا رايح',
    artist: 'رشيد طه',
    category: 'راي',
    image: 's1_5.png',
    isPremium: true,
  ),
  Song(
    id: 'ya-msafer',
    title: 'يا مسافر وحدك',
    artist: 'محمد عبد الوهاب',
    category: 'طرب',
    image: 's2_3.png',
  ),
];
