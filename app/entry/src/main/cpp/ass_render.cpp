#include "ass_render.h"

#include <ass/ass.h>
#include <fontconfig/fontconfig.h>

#include <algorithm>
#include <cstdio>
#include <set>
#include <cstdlib>
#include <cstring>
#include <mutex>

namespace {

std::mutex g_render_mutex;

} // namespace

RenderedFrame RenderAssFrame(const std::string& assPath, int timeMs,
                             int width, int height, const std::string& fontPath,
                             const std::string& fontConfigPath) {
    RenderedFrame out;
    out.width = width;
    out.height = height;
    if (width <= 0 || height <= 0) {
        out.error = "invalid frame size";
        return out;
    }
    std::lock_guard<std::mutex> lock(g_render_mutex);

    ASS_Library* lib = ass_library_init();
    if (!lib) {
        out.error = "ass_library_init failed";
        return out;
    }
    ASS_Renderer* ren = ass_renderer_init(lib);
    if (!ren) {
        ass_library_done(lib);
        out.error = "ass_renderer_init failed";
        return out;
    }
    ass_set_frame_size(ren, width, height);
    ass_set_pixel_aspect(ren, 1.0);
    const bool use_fontconfig = !fontConfigPath.empty();
    if (use_fontconfig) {
        setenv("FONTCONFIG_FILE", fontConfigPath.c_str(), 1);
        ass_set_fonts(ren, nullptr, "sans-serif", ASS_FONTPROVIDER_FONTCONFIG, nullptr, 1);
    } else {
        ass_set_fonts(ren, fontPath.c_str(), "Sans", 0, nullptr, 1);
    }

    ASS_Track* track = ass_read_file(lib, assPath.c_str(), nullptr);
    if (!track) {
        ass_renderer_done(ren);
        ass_library_done(lib);
        out.error = "ass_read_file failed";
        return out;
    }

    int changed = 0;
    ASS_Image* img = ass_render_frame(ren, track, timeMs, &changed);
    if (use_fontconfig && !img) {
        // No font matched; fall back to the bundled font.
        ass_set_fonts(ren, fontPath.c_str(), "Sans", 0, nullptr, 1);
        img = ass_render_frame(ren, track, timeMs, &changed);
    }
    out.pixels.assign(static_cast<size_t>(width) * height * 4, 0);

    for (ASS_Image* im = img; im; im = im->next) {
        if (im->w <= 0 || im->h <= 0 || !im->bitmap)
            continue;
        const int r = (im->color >> 24) & 0xff;
        const int g = (im->color >> 16) & 0xff;
        const int b = (im->color >> 8) & 0xff;
        // ASS alpha is inverted: 0 = opaque, 255 = transparent.
        const int alpha = 255 - (im->color & 0xff);
        for (int y = 0; y < im->h; ++y) {
            int dy = im->dst_y + y;
            if (dy < 0 || dy >= height)
                continue;
            const uint8_t* src = im->bitmap + y * im->stride;
            for (int x = 0; x < im->w; ++x) {
                int dx = im->dst_x + x;
                if (dx < 0 || dx >= width)
                    continue;
                int cov = src[x];
                if (!cov)
                    continue;
                int sa = cov * alpha / 255;
                uint8_t* p = &out.pixels[(static_cast<size_t>(dy) * width + dx) * 4];
                p[0] = static_cast<uint8_t>((p[0] * (255 - sa) + r * sa) / 255);
                p[1] = static_cast<uint8_t>((p[1] * (255 - sa) + g * sa) / 255);
                p[2] = static_cast<uint8_t>((p[2] * (255 - sa) + b * sa) / 255);
                p[3] = static_cast<uint8_t>(p[3] + sa - p[3] * sa / 255);
            }
        }
    }

    ass_free_track(track);
    ass_renderer_done(ren);
    ass_library_done(lib);
    out.ok = true;
    return out;
}

static std::string json_escape_font(const std::string& in) {
    std::string out;
    out.reserve(in.size() + 8);
    for (unsigned char c : in) {
        switch (c) {
        case '"': out += "\\\""; break;
        case '\\': out += "\\\\"; break;
        case '\n': out += "\\n"; break;
        case '\r': out += "\\r"; break;
        case '\t': out += "\\t"; break;
        default:
            if (c < 0x20) {
                char buf[8];
                std::snprintf(buf, sizeof buf, "\\u%04x", c);
                out += buf;
            } else {
                out += static_cast<char>(c);
            }
        }
    }
    return out;
}

std::string ListFontsJson(const std::string& fontConfigPath) {
    if (fontConfigPath.empty()) {
        return "{\"ok\":false,\"error\":\"no fontconfig path\"}";
    }
    setenv("FONTCONFIG_FILE", fontConfigPath.c_str(), 1);
    if (!FcInit()) {
        return "{\"ok\":false,\"error\":\"FcInit failed\"}";
    }
    FcObjectSet* os = FcObjectSetBuild(FC_FAMILY, nullptr);
    if (!os) {
        return "{\"ok\":false,\"error\":\"FcObjectSetBuild failed\"}";
    }
    FcPattern* pat = FcPatternCreate();
    FcFontSet* set = FcFontList(nullptr, pat, os);
    FcPatternDestroy(pat);
    FcObjectSetDestroy(os);
    if (!set) {
        return "{\"ok\":false,\"error\":\"FcFontList failed\"}";
    }
    std::set<std::string> families;
    for (int i = 0; i < set->nfont; ++i) {
        FcChar8* family = nullptr;
        if (FcPatternGetString(set->fonts[i], FC_FAMILY, 0, &family) == FcResultMatch && family) {
            families.emplace(reinterpret_cast<const char*>(family));
        }
    }
    FcFontSetDestroy(set);

    std::string out = "{\"ok\":true,\"fonts\":[";
    bool first = true;
    for (const auto& family : families) {
        if (!first) out += ',';
        first = false;
        out += '"';
        out += json_escape_font(family);
        out += '"';
    }
    out += "]}";
    return out;
}
