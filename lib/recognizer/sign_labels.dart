/// Map a Learn lesson id (e.g. "months_january", "letters_a",
/// "basic_wheelchair_person") to the recognizer's model label.
String modelLabelForLesson(String lessonId) {
  final i = lessonId.indexOf('_');
  final label = i >= 0 ? lessonId.substring(i + 1) : lessonId;
  // the training data spells this sign "weelchair_person"
  return label == 'wheelchair_person' ? 'weelchair_person' : label;
}

/// Learn category id whose signs are handled by the letters model.
const String lettersCategoryId = 'letters';

/// Signs the model is known to mix up (from cross-validation). Used to pick
/// harder quiz distractors from the same category.
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
