#pragma once

#include <cstdint>
#include <string>
#include <vector>

struct RenderedFrame {
    bool ok = false;
    std::string error;
    int width = 0;
    int height = 0;
    std::vector<uint8_t> pixels; // RGBA8
};

// Render one ASS frame at timeMs using libass. fontPath must point to a real
// TTF/OTF; libass is built without fontconfig, so all styles use this font.
RenderedFrame RenderAssFrame(const std::string& assPath, int timeMs,
                             int width, int height, const std::string& fontPath,
                             const std::string& fontConfigPath);

// Enumerate font families through fontconfig. Returns a JSON object:
// {"ok":true,"fonts":["..."]} or {"ok":false,"error":"..."}.
std::string ListFontsJson(const std::string& fontConfigPath);
