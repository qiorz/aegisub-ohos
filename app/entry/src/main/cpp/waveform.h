#pragma once

#include <string>

// Return a JSON object: {"ok":true,"peaks":[0..1,...]} for PCM WAV, or
// {"ok":false,"error":"..."} for unsupported/corrupt files.
std::string WaveformJson(const std::string& path, int buckets);
