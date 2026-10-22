#include "video_probe.h"

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <vector>

namespace {

uint32_t be32(const uint8_t* p) {
    return (static_cast<uint32_t>(p[0]) << 24) | (static_cast<uint32_t>(p[1]) << 16) |
           (static_cast<uint32_t>(p[2]) << 8) | p[3];
}
uint64_t be64(const uint8_t* p) {
    return (static_cast<uint64_t>(be32(p)) << 32) | be32(p + 4);
}
bool is(const uint8_t* p, const char* s) { return std::memcmp(p, s, 4) == 0; }

struct BoxRef {
    uint64_t size = 0;
    uint64_t payload = 0;
    uint64_t end = 0;
    uint32_t type = 0;
};

bool nextBox(const std::vector<uint8_t>& d, size_t& pos, size_t end, BoxRef& b) {
    if (pos + 8 > end) return false;
    uint64_t size = be32(&d[pos]);
    size_t payload = pos + 8;
    if (size == 1) {
        if (pos + 16 > end) return false;
        size = be64(&d[pos + 8]);
        payload = pos + 16;
    } else if (size == 0) {
        size = end - pos;
    }
    if (size < payload - pos || pos + size > end) return false;
    b.size = size;
    b.payload = payload;
    b.end = pos + size;
    b.type = be32(&d[pos + 4]);
    pos += size;
    return true;
}

struct Track {
    bool video = false;
    uint32_t timescale = 0;
    uint64_t samples = 0;
    uint64_t ticks = 0;
};

void parseStbl(const std::vector<uint8_t>& d, size_t begin, size_t end, Track& t) {
    size_t pos = begin;
    BoxRef b;
    while (nextBox(d, pos, end, b)) {
        if (b.payload + 8 > b.end) continue;
        if (b.type == 0x73747473) { // stts
            uint32_t entries = be32(&d[b.payload + 4]);
            size_t p = b.payload + 8;
            for (uint32_t i = 0; i < entries && p + 8 <= b.end; ++i, p += 8) {
                uint32_t count = be32(&d[p]);
                uint32_t delta = be32(&d[p + 4]);
                t.samples += count;
                t.ticks += static_cast<uint64_t>(count) * delta;
            }
        }
    }
}

void parseMdia(const std::vector<uint8_t>& d, size_t begin, size_t end, Track& t) {
    size_t pos = begin;
    BoxRef b;
    while (nextBox(d, pos, end, b)) {
        if (b.type == 0x68646c72 && b.payload + 12 <= b.end) { // hdlr
            if (is(&d[b.payload + 8], "vide")) t.video = true;
        } else if (b.type == 0x6d646864 && b.payload + 20 <= b.end) { // mdhd
            const uint8_t version = d[b.payload];
            if (version == 0) {
                t.timescale = be32(&d[b.payload + 12]);
            } else if (b.payload + 28 <= b.end) {
                t.timescale = be32(&d[b.payload + 20]);
            }
        } else if (b.type == 0x6d696e66) { // minf
            size_t p = b.payload;
            BoxRef c;
            while (nextBox(d, p, b.end, c)) {
                if (c.type == 0x7374626c) parseStbl(d, c.payload, c.end, t); // stbl
            }
        }
    }
}

bool parseMoov(const std::vector<uint8_t>& moov, double& fps) {
    size_t pos = 0;
    BoxRef b;
    while (nextBox(moov, pos, moov.size(), b)) {
        if (b.type != 0x7472616b) continue; // trak
        Track t;
        size_t p = b.payload;
        BoxRef c;
        while (nextBox(moov, p, b.end, c)) {
            if (c.type == 0x6d646961) parseMdia(moov, c.payload, c.end, t); // mdia
        }
        if (t.video && t.timescale > 0 && t.ticks > 0 && t.samples > 0) {
            fps = static_cast<double>(t.samples) * t.timescale / t.ticks;
            return fps > 1.0 && fps < 240.0;
        }
    }
    return false;
}

std::string err(const char* msg) {
    return std::string("{\"ok\":false,\"error\":\"") + msg + "\"}";
}

} // namespace

std::string VideoProbeJson(const std::string& path) {
    std::ifstream in(path, std::ios::binary);
    if (!in) return err("cannot open");
    in.seekg(0, std::ios::end);
    const std::streamoff size = in.tellg();
    if (size < 16) return err("too small");
    in.seekg(0);

    uint64_t pos = 0;
    std::vector<uint8_t> moov;
    while (pos + 8 <= static_cast<uint64_t>(size)) {
        in.seekg(static_cast<std::streamoff>(pos));
        uint8_t h[16] = {0};
        in.read(reinterpret_cast<char*>(h), 8);
        if (!in) break;
        uint64_t box_size = be32(h);
        size_t header = 8;
        if (box_size == 1) {
            if (pos + 16 > static_cast<uint64_t>(size)) break;
            in.read(reinterpret_cast<char*>(h + 8), 8);
            box_size = be64(h + 8);
            header = 16;
        } else if (box_size == 0) {
            box_size = static_cast<uint64_t>(size) - pos;
        }
        if (box_size < header || pos + box_size > static_cast<uint64_t>(size)) break;
        if (is(h + 4, "moov")) {
            if (box_size > 64ULL * 1024 * 1024) return err("moov too large");
            moov.resize(static_cast<size_t>(box_size - header));
            in.seekg(static_cast<std::streamoff>(pos + header));
            in.read(reinterpret_cast<char*>(moov.data()), moov.size());
            if (!in) return err("cannot read moov");
            break;
        }
        pos += box_size;
    }
    if (moov.empty()) return err("no moov");
    double fps = 0;
    if (!parseMoov(moov, fps)) return err("no video stts");
    char buf[128];
    std::snprintf(buf, sizeof buf,
                  "{\"ok\":true,\"fps\":%.3f,\"width\":0,\"height\":0}", fps);
    return buf;
}
