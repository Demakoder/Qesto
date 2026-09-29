#ifndef QESTO_PERSISTENT_PROFILE_PATH_H_
#define QESTO_PERSISTENT_PROFILE_PATH_H_

#include <algorithm>
#include <cwctype>
#include <filesystem>
#include <string>

// ChromeBrowserContext::InitializeAsync accepts only a direct child of the
// user-data root. Otherwise CEF silently creates a unique OffTheRecord profile.
// Reject that fallback rather than claiming that banking sessions are saved.
inline std::filesystem::path QestoUtf8Path(const std::string& value) {
  return std::filesystem::path(std::u8string(value.begin(), value.end()));
}

inline std::string QestoNativeProfilePath(const std::string& value) {
  auto path = QestoUtf8Path(value).lexically_normal();
  path.make_preferred();
  const auto utf8 = path.u8string();
  return std::string(utf8.begin(), utf8.end());
}

inline bool QestoIsPersistentProfilePath(const std::string& root,
                                         const std::string& profile) {
  namespace fs = std::filesystem;
  try {
    auto root_path = QestoUtf8Path(root);
    auto profile_path = QestoUtf8Path(profile);
    if (!root_path.is_absolute() || !profile_path.is_absolute()) return false;
    auto key = [](const fs::path& p) {
      auto s = p.lexically_normal().wstring();
#ifdef _WIN32
      std::transform(s.begin(), s.end(), s.begin(), [](wchar_t c) { return std::towlower(c); });
#endif
      return s;
    };
    if (key(profile_path.parent_path()) != key(root_path)) return false;
    // Reject symlink/junction escapes as well as lexical nesting.
    const auto resolved_root = fs::weakly_canonical(root_path);
    const auto resolved_profile = fs::weakly_canonical(profile_path);
    return key(resolved_profile.parent_path()) == key(resolved_root) &&
           key(resolved_profile) != key(resolved_root);
  } catch (...) {
    return false;
  }
}
#endif
