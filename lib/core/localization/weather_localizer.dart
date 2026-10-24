import '../localization/app_strings.dart';

String localizeWeather(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '';
  if (currentAppLanguage != AppLanguage.en) return raw;

  String text = raw;
  // Weather terms mapping
  final map = {
    'Güneşli': 'Sunny',
    'Açık': 'Clear',
    'Parçalı Bulutlu': 'Partly Cloudy',
    'Çok Bulutlu': 'Overcast',
    'Bulutlu': 'Cloudy',
    'Yağmurlu': 'Rainy',
    'Hafif Yağmurlu': 'Light Rain',
    'Sağanak Yağışlı': 'Showers',
    'Gök Gürültülü Sağanak': 'Thunderstorm',
    'Karlı': 'Snowy',
    'Kar Yağışlı': 'Snowing',
    'Sulu Kar': 'Sleet',
    'Sisli': 'Foggy',
    'Puslu': 'Hazy',
    'Rüzgarlı': 'Windy',
    'Fırtına': 'Stormy',
    'Sabah': 'Morning',
    'Öğle': 'Noon',
    'Öğlen': 'Noon',
    'İkindi': 'Afternoon',
    'Akşam': 'Evening',
    'Gece': 'Night',
    'Çisenti': 'Drizzle',
    'Gök Gürültülü': 'Thunderstorm',
    'Yıldızlı': 'Starry',
    'Bilinmiyor': 'Unknown',
  };

  map.forEach((tr, en) {
    text = text.replaceAll(tr, en);
  });
  return text;
}
