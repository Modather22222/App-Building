/// Download-link trust rules (Phase 7 — the `apkUrl` comes from a server row
/// and is handed to the OS launcher; only GitHub release hosts may be opened).
library;

/// True when [url] is an https URL on a host App Building is allowed to hand
/// to the OS (GitHub release downloads — github.com and the GitHub CDN).
bool isTrustedDownloadUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  if (uri.scheme != 'https') return false;
  final host = uri.host.toLowerCase();
  return host == 'github.com' ||
      host.endsWith('.github.com') ||
      host.endsWith('.githubusercontent.com');
}
