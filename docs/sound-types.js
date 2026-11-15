// Les clés correspondent aux types français de data/data.json.
const englishSoundTypes = {
  'ailes': 'Wings', 'alarme': 'Alarm', 'appel': 'Call',
  'appel chant': 'Call and song', 'appel en vol': 'Flight call',
  'autre chant': 'Other song', 'chant': 'Song', "chant de l'aube": 'Dawn song',
  'immitation': 'Imitation', 'interactions': 'Interactions',
  'tambourinement': 'Drumming', 'tok': 'Tok'
};

function translateSoundType(type, locale) {
  if (!type || (locale !== 'US' && locale !== 'en')) return type || '';
  const key = type.trim().toLocaleLowerCase('fr');
  return Object.prototype.hasOwnProperty.call(englishSoundTypes, key) ? englishSoundTypes[key] : type;
}
