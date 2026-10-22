#include "waveform.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <vector>

namespace {

uint16_t rd16(const std::vector<uint8_t>& b, size_t p) {
    return static_cast<uint16_t>(b[p] | (b[p + 1] << 8));
}
uint32_t rd32(const std::vector<uint8_t>& b, size_t p) {
    return static_cast<uint32_t>(b[p]) | (static_cast<uint32_t>(b[p + 1]) << 8) |
           (static_cast<uint32_t>(b[p + 2]) << 16) |
           (static_cast<uint32_t>(b[p + 3]) << 24);
}

std::string err(const char* msg) {
    return std::string("{\"ok\":false,\"error\":\"") + msg + "\"}";
}

} // namespace

std::string WaveformJson(const std::string& path, int buckets) {
    std::ifstream in(path, std::ios::binary | std::ios::ate);
    if (!in)
        return err("cannot open file");
    const std::streamoff size = in.tellg();
    if (size <= 0 || size > 512LL * 1024 * 1024)
        return err("unsupported file size");
    std::vector<uint8_t> data(static_cast<size_t>(size));
    in.seekg(0);
    in.read(reinterpret_cast<char*>(data.data()), size);
    if (!in)
        return err("cannot read file");
    if (data.size() < 12 || std::memcmp(data.data(), "RIFF", 4) != 0 ||
        std::memcmp(data.data() + 8, "WAVE", 4) != 0)
        return err("not a WAV file");

    uint16_t format = 0, channels = 0, bits = 0;
    uint32_t sample_rate = 0;
    size_t data_off = 0, data_size = 0;
    size_t pos = 12;
    while (pos + 8 <= data.size()) {
        const char* id = reinterpret_cast<const char*>(data.data() + pos);
        const uint32_t sz = rd32(data, pos + 4);
        pos += 8;
        if (pos + sz > data.size())
            break;
        if (std::memcmp(id, "fmt ", 4) == 0 && sz >= 16) {
            format = rd16(data, pos);
            channels = rd16(data, pos + 2);
            sample_rate = rd32(data, pos + 4);
            bits = rd16(data, pos + 14);
            if (format == 0xFFFE && sz >= 26) {
                // WAVE_FORMAT_EXTENSIBLE: SubFormat GUID starts with the tag.
                format = rd16(data, pos + 24);
            }
        } else if (std::memcmp(id, "data", 4) == 0) {
            data_off = pos;
            data_size = sz;
            if (data_off + data_size > data.size())
                data_size = data.size() - data_off;
        }
        pos += sz + (sz & 1);
    }
    if (format != 1 && format != 3)
        return err("only PCM/float WAV is supported");
    if (channels == 0 || (bits != 8 && bits != 16 && bits != 24 && bits != 32))
        return err("unsupported WAV format");
    if (data_size == 0)
        return err("empty WAV data");

    const int bytes = bits / 8;
    const size_t block_align = static_cast<size_t>(channels) * bytes;
    const size_t frames = data_size / block_align;
    if (frames == 0)
        return err("empty WAV data");
    if (buckets < 16) buckets = 16;
    if (buckets > 2000) buckets = 2000;

    std::vector<float> peaks(static_cast<size_t>(buckets), 0.0f);
    for (int b = 0; b < buckets; ++b) {
        const size_t begin = frames * static_cast<size_t>(b) / buckets;
        const size_t end = frames * static_cast<size_t>(b + 1) / buckets;
        const size_t step = std::max<size_t>(1, (end - begin) / 2000);
        float peak = 0.0f;
        for (size_t f = begin; f < end; f += step) {
            for (uint16_t c = 0; c < channels; ++c) {
                const size_t off = data_off + f * block_align + c * bytes;
                float v = 0.0f;
                if (bits == 8) {
                    v = std::fabs((static_cast<int>(data[off]) - 128) / 128.0f);
                } else if (bits == 16) {
                    int16_t s;
                    std::memcpy(&s, data.data() + off, 2);
                    v = std::fabs(s / 32768.0f);
                } else if (bits == 24) {
                    int32_t s = data[off] | (data[off + 1] << 8) | (data[off + 2] << 16);
                    if (s & 0x800000) s |= ~0xFFFFFF;
                    v = std::fabs(s / 8388608.0f);
                } else {
                    if (format == 3) {
                        float s;
                        std::memcpy(&s, data.data() + off, 4);
                        v = std::fabs(s);
                    } else {
                        int32_t s;
                        std::memcpy(&s, data.data() + off, 4);
                        v = std::fabs(static_cast<float>(s) / 2147483648.0f);
                    }
                }
                if (v > peak) peak = v;
            }
        }
        peaks[static_cast<size_t>(b)] = std::min(1.0f, peak);
    }

    std::string out = "{\"ok\":true,\"sampleRate\":" + std::to_string(sample_rate) +
                      ",\"channels\":" + std::to_string(channels) +
                      ",\"peaks\":[";
    char buf[32];
    for (int i = 0; i < buckets; ++i) {
        if (i) out += ',';
        std::snprintf(buf, sizeof buf, "%.3f", peaks[static_cast<size_t>(i)]);
        out += buf;
    }
    out += "]}";
    return out;
}
