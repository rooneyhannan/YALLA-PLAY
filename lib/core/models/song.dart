class Song {
  final String id;
  final String title;
  final String artist;
  final String category;
  final String image;
  final String difficulty;
  final bool isPremium;
  const Song({required this.id, required this.title, required this.artist,
    required this.category, required this.image, this.difficulty = 'مبتدئ', this.isPremium = false});
  bool get hasChart => id == 'badak';
}

const songs = <Song>[
  Song(id: 'badak', title: 'Ba’dak Ala Bali', artist: 'فيروز', category: 'طرب', image: 's1_2.png'),
  Song(id: 'life', title: 'Life by the Drop', artist: 'Stevie Ray Vaughan & Double Trouble', category: 'البلوز', image: 's2_1.png', isPremium: true),
  Song(id: 'house', title: 'House Of Memories', artist: 'Panic! At The Disco', category: 'بوب', image: 's2_2.png', difficulty: 'متوسط', isPremium: true),
  Song(id: 'snow', title: 'Snow', artist: 'Zach Bryan', category: 'كونتري', image: 's2_3.png', isPremium: true),
  Song(id: 'taxman', title: 'Taxman', artist: 'The Beatles', category: 'روك', image: 's2_4.png', difficulty: 'متقدم', isPremium: true),
  Song(id: 'tamally', title: 'تملي معاك', artist: 'عمرو دياب', category: 'بوب', image: 's2_1.png', difficulty: 'متوسط'),
  Song(id: 'nassam', title: 'نسم علينا الهوى', artist: 'فيروز', category: 'طرب', image: 's1_5.png'),
  Song(id: 'kadim', title: 'زيديني عشقاً', artist: 'كاظم الساهر', category: 'طرب', image: 's2_0.png', difficulty: 'متقدم'),
  Song(id: '3daqat', title: '3 Daqat', artist: 'Abu ft. Yousra', category: 'بوب', image: 's1_3.png'),
  Song(id: 'cest', title: "C’est La Vie", artist: 'Cheb Khaled', category: 'راي', image: 's1_7.png', isPremium: true),
  Song(id: 'shape', title: 'Shape of You', artist: 'Ed Sheeran', category: 'بوب', image: 's2_2.png', isPremium: true),
  Song(id: 'nothing', title: 'Nothing Else Matters', artist: 'Metallica', category: 'روك', image: 's1_6.png', difficulty: 'متوسط', isPremium: true),
  Song(id: 'blinding', title: 'Blinding Lights', artist: 'The Weeknd', category: 'بوب', image: 's1_3.png', difficulty: 'متوسط'),
  Song(id: 'birthday', title: 'Happy Birthday', artist: 'Traditional', category: 'كلاسيكي', image: 's2_7.png'),
  Song(id: 'rayah', title: 'Ya Rayah', artist: 'Rachid Taha', category: 'راي', image: 's1_5.png', isPremium: true),
  Song(id: 'clapton', title: 'Wonderful Tonight', artist: 'إريك كلابتون', category: 'روك', image: 's2_3.png'),
];
