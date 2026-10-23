#pragma once
#include <string>

// Decode the first audio stream of a video/audio container and return
// {"ok":true,"peaks":[0..1,...]} or {"ok":false,"error":"..."}.
std::string VideoWaveformJson(const std::string& path, int buckets);
