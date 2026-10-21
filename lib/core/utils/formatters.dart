const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String timeAgo(DateTime then) {
  final diff = DateTime.now().difference(then);
  if (diff.inSeconds < 45) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return shortDate(then);
}

String clockTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String shortDate(DateTime d) => '${_months[d.month - 1]} ${d.day}';

String fmtDuration(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds} s';
  final minutes = d.inMinutes;
  final seconds = d.inSeconds % 60;
  return seconds == 0 ? '$minutes m' : '$minutes m $seconds s';
}
