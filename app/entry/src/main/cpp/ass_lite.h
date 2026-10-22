#pragma once

#include <string>

// Lightweight ASS reader for the ArkUI editor shell.  It preserves the
// untouched header/footer text and parses the [Events] table using the file's
// own Format line; time fields are interpreted with libaegisub's agi::Time.
std::string LoadAssJson(const std::string& path);
std::string NewAssJson();
