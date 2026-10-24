class QuestionCard {
  final String id;
  final String category;
  final String questionTr;
  final String questionEn;
  final String emoji;

  const QuestionCard({
    required this.id,
    required this.category,
    required this.questionTr,
    required this.questionEn,
    required this.emoji,
  });

  String getQuestion(bool isTurkish) => isTurkish ? questionTr : questionEn;
}

class QuestionCategory {
  final String id;
  final String titleTr;
  final String titleEn;
  final String emoji;
  final int colorHex;

  const QuestionCategory({
    required this.id,
    required this.titleTr,
    required this.titleEn,
    required this.emoji,
    required this.colorHex,
  });

  String getTitle(bool isTurkish) => isTurkish ? titleTr : titleEn;
}

class QuestionBank {
  static const List<QuestionCategory> categories = [
    QuestionCategory(
      id: 'love',
      titleTr: 'Romantizm & Kalp',
      titleEn: 'Romance & Heart',
      emoji: '💖',
      colorHex: 0xFFF43F5E,
    ),
    QuestionCategory(
      id: 'firsts',
      titleTr: 'İlkler & Hatıralar',
      titleEn: 'Firsts & Memories',
      emoji: '✨',
      colorHex: 0xFFEC4899,
    ),
    QuestionCategory(
      id: 'deep',
      titleTr: 'Derin & Duygusal',
      titleEn: 'Deep & Soulful',
      emoji: '🌌',
      colorHex: 0xFF8B5CF6,
    ),
    QuestionCategory(
      id: 'fun',
      titleTr: 'Eğlence & Gülmece',
      titleEn: 'Fun & Laughter',
      emoji: '🎉',
      colorHex: 0xFFF59E0B,
    ),
    QuestionCategory(
      id: 'future',
      titleTr: 'Gelecek & Hayaller',
      titleEn: 'Future & Dreams',
      emoji: '🚀',
      colorHex: 0xFF06B6D4,
    ),
    QuestionCategory(
      id: 'spicy',
      titleTr: 'Cesur & Samimi',
      titleEn: 'Bold & Intimate',
      emoji: '🔥',
      colorHex: 0xFFEF4444,
    ),
  ];

  static const List<QuestionCard> allQuestions = [
    // --- 1. ROMANTİZM & KALP ---
    QuestionCard(
      id: 'q_love_1',
      category: 'love',
      questionTr: 'Bana baktığında içinde beliren ilk hissi tek bir kelimeyle anlatabilir misin?',
      questionEn: 'Can you describe the first feeling that comes to you when you look at me in a single word?',
      emoji: '👀',
    ),
    QuestionCard(
      id: 'q_love_2',
      category: 'love',
      questionTr: 'Sence beni en çok ne zaman veya hangi halimle seviyorsun?',
      questionEn: 'When or in what state do you think you love me the most?',
      emoji: '🥰',
    ),
    QuestionCard(
      id: 'q_love_3',
      category: 'love',
      questionTr: 'Bana duyduğun sevgiyi bir şarkıya veya melodiye benzetsen hangisi olurdu?',
      questionEn: 'If you compared your love for me to a song or melody, which one would it be?',
      emoji: '🎵',
    ),
    QuestionCard(
      id: 'q_love_4',
      category: 'love',
      questionTr: 'Birlikteyken zamanın nasıl geçtiğini unuttuğun en son an hangisiydi?',
      questionEn: 'What was the last moment together when you completely forgot how time passed?',
      emoji: '⏳',
    ),
    QuestionCard(
      id: 'q_love_5',
      category: 'love',
      questionTr: 'Benimle ilgili asla değişmesini istemediğin en tatlı özelliğim ne?',
      questionEn: 'What is the sweetest thing about me that you never want to change?',
      emoji: '🌸',
    ),
    QuestionCard(
      id: 'q_love_6',
      category: 'love',
      questionTr: 'Bana sarıldığında kalbinde ne hissediyorsun?',
      questionEn: 'What do you feel in your heart when you hug me?',
      emoji: '🫂',
    ),
    QuestionCard(
      id: 'q_love_7',
      category: 'love',
      questionTr: 'Beni sevdiğini ilk tam olarak anladığın an ne yapıyorduk?',
      questionEn: 'What were we doing the exact moment you first realized you loved me?',
      emoji: '💘',
    ),
    QuestionCard(
      id: 'q_love_8',
      category: 'love',
      questionTr: 'Günün en yorucu anında sana beni hatırlatan şey genellikle ne olur?',
      questionEn: 'What usually reminds you of me in the most tiring moment of your day?',
      emoji: '☕',
    ),
    QuestionCard(
      id: 'q_love_9',
      category: 'love',
      questionTr: 'Birlikte yaptığımız en sade şey bile neden seninle bu kadar güzel?',
      questionEn: 'Why does even the simplest thing we do together feel so special with you?',
      emoji: '🌙',
    ),
    QuestionCard(
      id: 'q_love_10',
      category: 'love',
      questionTr: 'Şu an bana söylemek istediğin ama ertelediğin en içten cümlen nedir?',
      questionEn: 'What is the most heartfelt sentence you want to say to me right now but postponed?',
      emoji: '💌',
    ),

    // --- 2. İLKLER & HATIRALAR ---
    QuestionCard(
      id: 'q_first_1',
      category: 'firsts',
      questionTr: 'İlk buluştuğumuz gün üzerimde ne vardı ve ilk ne düşündün?',
      questionEn: 'What was I wearing on our very first date and what was your first thought?',
      emoji: '👗',
    ),
    QuestionCard(
      id: 'q_first_2',
      category: 'firsts',
      questionTr: 'İlk el ele tutuştuğumuz andaki heyecanını 1 ile 10 arasında puanla ve anlat.',
      questionEn: 'Rate your excitement on a scale of 1 to 10 when we first held hands, and explain.',
      emoji: '🤝',
    ),
    QuestionCard(
      id: 'q_first_3',
      category: 'firsts',
      questionTr: 'İlk kez benimle baş başa kaldığında en çok neyden çekinmiştin?',
      questionEn: 'What were you most nervous about when you were first alone with me?',
      emoji: '🙈',
    ),
    QuestionCard(
      id: 'q_first_4',
      category: 'firsts',
      questionTr: 'İlişkimizin ilk 1 ayında arkadaşlarına benden bahsederken ne söylüyordun?',
      questionEn: 'What did you tell your friends about me during the first month of our relationship?',
      emoji: '🗣️',
    ),
    QuestionCard(
      id: 'q_first_5',
      category: 'firsts',
      questionTr: 'Birlikte geçirdiğimiz en unutulmaz gün hangisiydi ve neden?',
      questionEn: 'Which was the most unforgettable day we spent together, and why?',
      emoji: '📸',
    ),
    QuestionCard(
      id: 'q_first_6',
      category: 'firsts',
      questionTr: 'Bana aldığın ya da benden aldığın ilk hediye sende ne hissettirmişti?',
      questionEn: 'How did the very first gift you gave or received from me make you feel?',
      emoji: '🎁',
    ),
    QuestionCard(
      id: 'q_first_7',
      category: 'firsts',
      questionTr: 'Birlikte ilk defa güldüğümüz o komik anı hatırlıyor musun?',
      questionEn: 'Do you remember the very first time we burst out laughing together?',
      emoji: '😂',
    ),
    QuestionCard(
      id: 'q_first_8',
      category: 'firsts',
      questionTr: 'İlk öpücüğümüzden hemen sonra aklından geçen ilk cümle neydi?',
      questionEn: 'What was the first thought that crossed your mind right after our first kiss?',
      emoji: '💋',
    ),
    QuestionCard(
      id: 'q_first_9',
      category: 'firsts',
      questionTr: 'İkimizin ilk çektiği fotoğrafı gördüğünde şu an ne hissediyorsun?',
      questionEn: 'How do you feel right now when looking at the very first photo we took together?',
      emoji: '🖼️',
    ),
    QuestionCard(
      id: 'q_first_10',
      category: 'firsts',
      questionTr: 'Bana ilk kez "seni seviyorum" dediğinde ortam nasıldı?',
      questionEn: 'What was the atmosphere like when you first said "I love you" to me?',
      emoji: '🕯️',
    ),

    // --- 3. DERİN & DUYGUSAL ---
    QuestionCard(
      id: 'q_deep_1',
      category: 'deep',
      questionTr: 'Zor bir gün geçirdiğinde sana nasıl sarılsam veya yaklaşsam bütün yorgunluğun gider?',
      questionEn: 'When you have a tough day, how can I hug or support you to take all exhaustion away?',
      emoji: '🛡️',
    ),
    QuestionCard(
      id: 'q_deep_2',
      category: 'deep',
      questionTr: 'İlişkimizin hayatında değiştirdiği en büyük ve en güzel şey nedir?',
      questionEn: 'What is the biggest and most beautiful thing our relationship has changed in your life?',
      emoji: '🌱',
    ),
    QuestionCard(
      id: 'q_deep_3',
      category: 'deep',
      questionTr: 'Benim yanımda kendini en çok güvende hissettiren an hangi andı?',
      questionEn: 'In which moment did you feel safest beside me?',
      emoji: '⚓',
    ),
    QuestionCard(
      id: 'q_deep_4',
      category: 'deep',
      questionTr: 'Kelimelerle anlatamadığın ama kalbinde çok iyi bildiğin bir duygumuzu tarif et.',
      questionEn: 'Describe a feeling between us that words fail to capture, but you know deeply in your heart.',
      emoji: '🌌',
    ),
    QuestionCard(
      id: 'q_deep_5',
      category: 'deep',
      questionTr: 'Bana şimdiye kadar itiraf etmekten utandığın tatlı bir zaafın var mı?',
      questionEn: 'Do you have a sweet vulnerability regarding me that you were shy to admit until now?',
      emoji: '🥺',
    ),
    QuestionCard(
      id: 'q_deep_6',
      category: 'deep',
      questionTr: 'Birlikte sessizce yan yana otururken aklından neler geçer?',
      questionEn: 'What goes through your mind when we sit silently side by side?',
      emoji: '🧘',
    ),
    QuestionCard(
      id: 'q_deep_7',
      category: 'deep',
      questionTr: 'Sence bizim aşkımızın diğer ilişkilerden en ayırt edici gücü nedir?',
      questionEn: 'What do you think is the most distinctive strength of our love compared to others?',
      emoji: '💎',
    ),
    QuestionCard(
      id: 'q_deep_8',
      category: 'deep',
      questionTr: 'Korktuğun veya endişelendiğin anlarda benim sesim sana ne ifade ediyor?',
      questionEn: 'What does my voice mean to you when you feel scared or anxious?',
      emoji: '🕊️',
    ),
    QuestionCard(
      id: 'q_deep_9',
      category: 'deep',
      questionTr: 'Benim farkında olmadığım ama senin çok değer verdiğin küçük bir hareketim var mı?',
      questionEn: 'Is there a small gesture I do without realizing that you cherish deeply?',
      emoji: '✨',
    ),
    QuestionCard(
      id: 'q_deep_10',
      category: 'deep',
      questionTr: 'Birbirimizin hayatında olmasaydık sence şu an nasıl biri olurdun?',
      questionEn: 'What kind of person do you think you would be today if we were not in each other\'s lives?',
      emoji: '🧩',
    ),

    // --- 4. EĞLENCE & GÜLMECE ---
    QuestionCard(
      id: 'q_fun_1',
      category: 'fun',
      questionTr: 'Eğer bir çizgi film karakteri olsaydım sence hangisi olurdum ve neden?',
      questionEn: 'If I were a cartoon character, who would I be and why?',
      emoji: '🎨',
    ),
    QuestionCard(
      id: 'q_fun_2',
      category: 'fun',
      questionTr: 'Beni en çok güldüren komik taklidim veya huyum hangisi?',
      questionEn: 'What is my funniest habit or impression that makes you laugh the most?',
      emoji: '🤪',
    ),
    QuestionCard(
      id: 'q_fun_3',
      category: 'fun',
      questionTr: 'Issız bir adaya düşsek sence hangimiz ilk önce paniklerdi?',
      questionEn: 'If we were stranded on a deserted island, who would panic first?',
      emoji: '🏝️',
    ),
    QuestionCard(
      id: 'q_fun_4',
      category: 'fun',
      questionTr: 'Beni sinir etmek istediğinde kullandığın gizli bir numaran var mı?',
      questionEn: 'Do you have a secret trick you use when you playfully want to annoy me?',
      emoji: '😈',
    ),
    QuestionCard(
      id: 'q_fun_5',
      category: 'fun',
      questionTr: 'Sabahları uyandığımdaki halimi 3 kelimeyle dürüstçe özetle!',
      questionEn: 'Honestly summarize the way I look when I wake up in the morning in 3 words!',
      emoji: '🥱',
    ),
    QuestionCard(
      id: 'q_fun_6',
      category: 'fun',
      questionTr: 'Bir zombi istilasında beni kurtarmak için neyi feda ederdin?',
      questionEn: 'What would you sacrifice to save me in a zombie apocalypse?',
      emoji: '🧟',
    ),
    QuestionCard(
      id: 'q_fun_7',
      category: 'fun',
      questionTr: 'Benim hakkımda bilmediğim komik bir takıntım var mı?',
      questionEn: 'Do I have a funny quirk or obsession that I might not even realize?',
      emoji: '🔍',
    ),
    QuestionCard(
      id: 'q_fun_8',
      category: 'fun',
      questionTr: 'Görünmez olsan ilk olarak beni gizlice izlerken ne yapardın?',
      questionEn: 'If you were invisible, what is the first thing you would do watching me secretly?',
      emoji: '👻',
    ),
    QuestionCard(
      id: 'q_fun_9',
      category: 'fun',
      questionTr: 'Hangimiz trafikte veya açken daha çekilmez oluyor?',
      questionEn: 'Which of us is more unbearable in traffic or when hungry?',
      emoji: '🍔',
    ),
    QuestionCard(
      id: 'q_fun_10',
      category: 'fun',
      questionTr: 'Bana şu an komik bir lakap takacak olsan bu ne olurdu?',
      questionEn: 'If you were to give me a funny nickname right now, what would it be?',
      emoji: '🏷️',
    ),

    // --- 5. GELECEK & HAYALLER ---
    QuestionCard(
      id: 'q_future_1',
      category: 'future',
      questionTr: 'Gelecekteki ortak evimizin balkonunda pazar sabahı ne yapıyor olacağız?',
      questionEn: 'What will we be doing on a Sunday morning on the balcony of our future home?',
      emoji: '🏡',
    ),
    QuestionCard(
      id: 'q_future_2',
      category: 'future',
      questionTr: 'Birlikte mutlaka gitmemiz gereken dünyadaki o tek özel yer neresi?',
      questionEn: 'What is that one special place in the world that we absolutely must visit together?',
      emoji: '✈️',
    ),
    QuestionCard(
      id: 'q_future_3',
      category: 'future',
      questionTr: '80 yaşına geldiğimizde el ele otururken birbirimize ne fısıldayacağız?',
      questionEn: 'When we are 80 years old sitting hand in hand, what will we whisper to each other?',
      emoji: '👵👴',
    ),
    QuestionCard(
      id: 'q_future_4',
      category: 'future',
      questionTr: 'Gelecekte ortak bir evcil hayvanımız olsa adı ve türü ne olmalı?',
      questionEn: 'If we had a pet together in the future, what should its name and breed be?',
      emoji: '🐾',
    ),
    QuestionCard(
      id: 'q_future_5',
      category: 'future',
      questionTr: 'Önümüzdeki 5 yıl içinde birlikte başarmayı en çok istediğin çılgın hedef ne?',
      questionEn: 'What is the craziest goal you most want to achieve together in the next 5 years?',
      emoji: '🎯',
    ),
    QuestionCard(
      id: 'q_future_6',
      category: 'future',
      questionTr: 'Hayalindeki düğün/evlilik veya kutlama anımızın en özel detayı nasıl olmalı?',
      questionEn: 'What should be the most special detail of our dream celebration or wedding moment?',
      emoji: '💍',
    ),
    QuestionCard(
      id: 'q_future_7',
      category: 'future',
      questionTr: 'Birlikte yaşlanmanın sende uyandırdığı en huzurlu his nedir?',
      questionEn: 'What is the most peaceful feeling that growing old together evokes in you?',
      emoji: '🌅',
    ),
    QuestionCard(
      id: 'q_future_8',
      category: 'future',
      questionTr: 'Gelecekteki çocuklarımıza veya sevdiklerimize aşkımızı nasıl anlatacağız?',
      questionEn: 'How will we describe our love story to our future kids or loved ones?',
      emoji: '📖',
    ),
    QuestionCard(
      id: 'q_future_9',
      category: 'future',
      questionTr: 'Birlikte yağmurlu bir gecede geleceğe dair kurduğumuz en güzel hayal hangisi?',
      questionEn: 'What is the most beautiful dream we shared for our future on a rainy night?',
      emoji: '🌧️',
    ),
    QuestionCard(
      id: 'q_future_10',
      category: 'future',
      questionTr: 'Hayatın boyunca bana her sabah söylemekten bıkmayacağın tek bir cümle?',
      questionEn: 'The one sentence you would never get tired of saying to me every morning for life?',
      emoji: '☀️',
    ),

    // --- 6. CESUR & SAMİMİ ---
    QuestionCard(
      id: 'q_spicy_1',
      category: 'spicy',
      questionTr: 'Beni gördüğünde kalbini en çok hızlandıran kıyafetim veya görüntüm hangisi?',
      questionEn: 'Which outfit or look of mine makes your heart race the fastest when you see me?',
      emoji: '👗',
    ),
    QuestionCard(
      id: 'q_spicy_2',
      category: 'spicy',
      questionTr: 'Yalnızken kulağıma fısıldamak istediğin en çekici veya cesur söz nedir?',
      questionEn: 'What is the most attractive or bold thing you want to whisper in my ear when alone?',
      emoji: '👄',
    ),
    QuestionCard(
      id: 'q_spicy_3',
      category: 'spicy',
      questionTr: 'Sence aramızdaki ten ve göz temasının en karşı konulmaz anı hangisi?',
      questionEn: 'When is the most irresistible moment of eye and physical contact between us?',
      emoji: '⚡',
    ),
    QuestionCard(
      id: 'q_spicy_4',
      category: 'spicy',
      questionTr: 'Beni öperken zamanın durmasını istediğin en özel yer neresiydi?',
      questionEn: 'Where was the most special place you kissed me where you wished time stopped?',
      emoji: '💋',
    ),
    QuestionCard(
      id: 'q_spicy_5',
      category: 'spicy',
      questionTr: 'Gözlerimin içine 10 saniye baktığında içinde uyanan en yoğun his ne?',
      questionEn: 'What is the most intense feeling that awakes in you when you look into my eyes for 10s?',
      emoji: '🔥',
    ),
    QuestionCard(
      id: 'q_spicy_6',
      category: 'spicy',
      questionTr: 'Bana karşı koyamadığın, seni benden alan en zayıf noktan neresi/hangisi?',
      questionEn: 'What is your weakest spot that you cannot resist when it comes to me?',
      emoji: '🧲',
    ),
    QuestionCard(
      id: 'q_spicy_7',
      category: 'spicy',
      questionTr: 'Sadece ikimizin olduğu bir odada şu an yapabileceğimiz en tatlı şey ne olurdu?',
      questionEn: 'What would be the sweetest thing we could do right now in a room with just the two of us?',
      emoji: '🚪',
    ),
    QuestionCard(
      id: 'q_spicy_8',
      category: 'spicy',
      questionTr: 'Sana dokunduğumda vücudunda beliren o ilk ürpertiyi tarif eder misin?',
      questionEn: 'Can you describe that first shiver that appears when I gently touch you?',
      emoji: '✨',
    ),
    QuestionCard(
      id: 'q_spicy_9',
      category: 'spicy',
      questionTr: 'Birlikte baş başa geçireceğimiz en büyüleyici akşamın planı nasıl başlar?',
      questionEn: 'How does the plan for our most enchanting private evening together begin?',
      emoji: '🍷',
    ),
    QuestionCard(
      id: 'q_spicy_10',
      category: 'spicy',
      questionTr: 'Benimle ilgili gördüğün ve uyanmak istemediğin en etkileyici rüya nasıldı?',
      questionEn: 'What was the most striking dream you had about me where you didn\'t want to wake up?',
      emoji: '🌙',
    ),
  ];

  static QuestionCard? getById(String id) {
    try {
      return allQuestions.firstWhere((q) => q.id == id);
    } catch (_) {
      return null;
    }
  }

  static List<QuestionCard> getByCategory(String categoryId) {
    return allQuestions.where((q) => q.category == categoryId).toList();
  }
}
