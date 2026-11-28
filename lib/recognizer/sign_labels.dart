String modelLabelForLesson(String lessonId) {
  final i = lessonId.indexOf('_');
  final label = i >= 0 ? lessonId.substring(i + 1) : lessonId;
  return label == 'wheelchair_person' ? 'weelchair_person' : label;
}

const String lettersCategoryId = 'letters';

const Map<String, List<String>> confusableSigns = {
  'january': ['february'], 'february': ['march', 'january'], 'march': ['february'],
  'april': ['august'], 'may': ['june', 'july'], 'june': ['july', 'may'],
  'july': ['june', 'may'], 'august': ['april', 'july'],
  'september': ['october', 'november'], 'october': ['september', 'december'],
  'november': ['december', 'october'], 'december': ['november'],
  'parents': ['uncle'], 'uncle': ['parents'], 'three': ['wednesday'],
  'four': ['seven'], 'seven': ['four'],
  'e': ['i', 'n', 'y'], 'i': ['j', 'y'], 'n': ['m', 's'], 'm': ['n'],
  'y': ['i'], 'r': ['h', 'u'], 'p': ['q'], 'q': ['p'],
};
