const _months = [
  'jan',
  'feb',
  'mars',
  'apr',
  'maj',
  'juni',
  'juli',
  'aug',
  'sep',
  'okt',
  'nov',
  'dec',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// `10:04`
String formatTime(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// `12 okt`
String formatDay(DateTime t) => '${t.day} ${_months[t.month - 1]}';
