#include "ass_lite.h"

#include <libaegisub/ass/time.h>

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <strings.h>
#include <vector>

namespace {

const char* kDefaultFormat =
    "Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text";

struct Event {
    std::string kind;
    std::vector<std::string> fields;
    int start_ms = 0;
    int end_ms = 0;
};

struct Doc {
    std::string header;
    std::string footer;
    std::string eol = "\n";
    bool bom = false;
    std::vector<std::string> format;
    std::vector<std::string> styles;
    std::vector<Event> events;
    int start_index = 1;
    int end_index = 2;
    int text_index = 9;
};

std::string trim(const std::string& s) {
    size_t a = 0, b = s.size();
    while (a < b && std::isspace(static_cast<unsigned char>(s[a])))
        ++a;
    while (b > a && std::isspace(static_cast<unsigned char>(s[b - 1])))
        --b;
    return s.substr(a, b - a);
}

bool istarts(const std::string& s, const char* prefix) {
    size_t n = std::strlen(prefix);
    return s.size() >= n && strncasecmp(s.c_str(), prefix, n) == 0;
}

bool is_section(const std::string& line, const char* name) {
    std::string t = trim(line);
    if (t.size() < 3 || t.front() != '[' || t.back() != ']')
        return false;
    return strcasecmp(t.c_str(), name) == 0;
}

std::vector<std::string> split_lines(const std::string& content, std::string& eol) {
    eol = content.find("\r\n") != std::string::npos ? "\r\n" : "\n";
    std::vector<std::string> lines;
    size_t start = 0;
    while (start <= content.size()) {
        size_t pos = content.find('\n', start);
        if (pos == std::string::npos) {
            if (start < content.size())
                lines.push_back(content.substr(start));
            break;
        }
        std::string line = content.substr(start, pos - start);
        if (!line.empty() && line.back() == '\r')
            line.pop_back();
        lines.push_back(std::move(line));
        start = pos + 1;
    }
    return lines;
}

std::string join_lines(const std::vector<std::string>& lines, size_t begin, size_t end,
                       const std::string& eol) {
    std::string out;
    for (size_t i = begin; i < end; ++i) {
        out += lines[i];
        out += eol;
    }
    return out;
}

std::vector<std::string> split_fields(const std::string& s, char delim, size_t limit) {
    std::vector<std::string> out;
    if (limit == 0)
        limit = 1;
    size_t start = 0;
    while (out.size() + 1 < limit) {
        size_t pos = s.find(delim, start);
        if (pos == std::string::npos)
            break;
        out.push_back(s.substr(start, pos - start));
        start = pos + 1;
    }
    out.push_back(s.substr(start));
    return out;
}

std::vector<std::string> split_format(const std::string& line) {
    size_t colon = line.find(':');
    std::string payload = colon == std::string::npos ? line : line.substr(colon + 1);
    std::vector<std::string> out;
    for (auto& f : split_fields(payload, ',', 256))
        out.push_back(trim(f));
    return out;
}

int index_of(const std::vector<std::string>& fields, const char* name) {
    for (size_t i = 0; i < fields.size(); ++i)
        if (strcasecmp(fields[i].c_str(), name) == 0)
            return static_cast<int>(i);
    return -1;
}

std::string json_escape(const std::string& s) {
    std::string out;
    out.reserve(s.size() + 16);
    for (unsigned char c : s) {
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

void json_string_array(std::string& out, const std::vector<std::string>& v) {
    out += '[';
    for (size_t i = 0; i < v.size(); ++i) {
        if (i) out += ',';
        out += '"';
        out += json_escape(v[i]);
        out += '"';
    }
    out += ']';
}

std::string to_json(const Doc& d) {
    std::string out;
    out.reserve(d.header.size() + d.footer.size() + 4096);
    out += "{\"ok\":true,\"header\":\"";
    out += json_escape(d.header);
    out += "\",\"footer\":\"";
    out += json_escape(d.footer);
    out += "\",\"eol\":\"";
    out += json_escape(d.eol);
    out += "\",\"bom\":";
    out += d.bom ? "true" : "false";
    out += ",\"format\":";
    json_string_array(out, d.format);
    out += ",\"startIndex\":";
    out += std::to_string(d.start_index);
    out += ",\"endIndex\":";
    out += std::to_string(d.end_index);
    out += ",\"textIndex\":";
    out += std::to_string(d.text_index);
    out += ",\"styles\":";
    json_string_array(out, d.styles);
    out += ",\"events\":[";
    for (size_t i = 0; i < d.events.size(); ++i) {
        if (i) out += ',';
        const auto& e = d.events[i];
        out += "{\"kind\":\"";
        out += json_escape(e.kind);
        out += "\",\"fields\":";
        json_string_array(out, e.fields);
        out += ",\"startMs\":";
        out += std::to_string(e.start_ms);
        out += ",\"endMs\":";
        out += std::to_string(e.end_ms);
        out += '}';
    }
    out += "]}";
    return out;
}

std::string error_json(const std::string& msg) {
    return "{\"ok\":false,\"error\":\"" + json_escape(msg) + "\"}";
}

void parse_event_line(const std::string& line, size_t format_size,
                      const std::vector<std::string>& format,
                      int start_idx, int end_idx, Doc& doc) {
    size_t colon = line.find(':');
    if (colon == std::string::npos)
        return;
    Event e;
    e.kind = trim(line.substr(0, colon));
    std::string payload = line.substr(colon + 1);
    if (!payload.empty() && payload.front() == ' ')
        payload.erase(payload.begin());
    e.fields = split_fields(payload, ',', format_size);
    while (e.fields.size() < format_size)
        e.fields.emplace_back();
    if (start_idx >= 0 && static_cast<size_t>(start_idx) < e.fields.size())
        e.start_ms = static_cast<int>(agi::Time(e.fields[start_idx]));
    else
        e.start_ms = 0;
    if (end_idx >= 0 && static_cast<size_t>(end_idx) < e.fields.size())
        e.end_ms = static_cast<int>(agi::Time(e.fields[end_idx]));
    else
        e.end_ms = 0;
    (void)format;
    doc.events.push_back(std::move(e));
}

Doc parse_ass(const std::string& content_in) {
    Doc d;
    std::string content = content_in;
    if (content.size() >= 3 &&
        static_cast<unsigned char>(content[0]) == 0xEF &&
        static_cast<unsigned char>(content[1]) == 0xBB &&
        static_cast<unsigned char>(content[2]) == 0xBF) {
        d.bom = true;
        content.erase(0, 3);
    }

    auto lines = split_lines(content, d.eol);

    int events_idx = -1;
    int events_end = static_cast<int>(lines.size());
    for (size_t i = 0; i < lines.size(); ++i) {
        if (is_section(lines[i], "[events]")) {
            events_idx = static_cast<int>(i);
            break;
        }
    }
    if (events_idx >= 0) {
        for (size_t i = events_idx + 1; i < lines.size(); ++i) {
            std::string t = trim(lines[i]);
            if (t.size() >= 2 && t.front() == '[' && t.back() == ']') {
                events_end = static_cast<int>(i);
                break;
            }
        }
        d.header = join_lines(lines, 0, static_cast<size_t>(events_idx), d.eol);
        d.footer = join_lines(lines, static_cast<size_t>(events_end), lines.size(), d.eol);
    } else {
        d.header = join_lines(lines, 0, lines.size(), d.eol);
    }

    // Style names from the header (preserved verbatim on save).
    for (size_t i = 0; i < lines.size(); ++i) {
        std::string t = trim(lines[i]);
        if (!istarts(t, "Style:"))
            continue;
        auto fields = split_fields(t.substr(6), ',', 2);
        std::string name = trim(fields[0]);
        if (!name.empty())
            d.styles.push_back(name);
    }

    std::vector<std::string> format;
    if (events_idx >= 0) {
        for (int i = events_idx + 1; i < events_end; ++i) {
            std::string t = trim(lines[static_cast<size_t>(i)]);
            if (istarts(t, "Format:")) {
                format = split_format(t);
                break;
            }
        }
    }
    if (format.empty()) {
        format = split_format(std::string("Format: ") + kDefaultFormat);
    }
    d.format = format;
    d.start_index = index_of(format, "Start");
    d.end_index = index_of(format, "End");
    d.text_index = index_of(format, "Text");

    if (events_idx >= 0) {
        for (int i = events_idx + 1; i < events_end; ++i) {
            std::string t = trim(lines[static_cast<size_t>(i)]);
            if (istarts(t, "Dialogue:") || istarts(t, "Comment:")) {
                parse_event_line(t, format.size(), format,
                                 d.start_index, d.end_index, d);
            }
        }
    }
    return d;
}

} // namespace

std::string LoadAssJson(const std::string& path) {
    std::ifstream in(path, std::ios::binary);
    if (!in)
        return error_json("cannot open " + path);
    std::ostringstream ss;
    ss << in.rdbuf();
    if (!in.good() && !in.eof())
        return error_json("cannot read " + path);
    return to_json(parse_ass(ss.str()));
}

std::string NormalizeAssTime(const std::string& text) {
    bool has_digit = false;
    for (unsigned char c : text)
        if (std::isdigit(c)) { has_digit = true; break; }
    if (!has_digit)
        return text;
    return agi::Time(text).GetAssFormatted();
}

std::string NewAssJson() {
    Doc d;
    d.eol = "\n";
    d.header =
        "[Script Info]\n"
        "ScriptType: v4.00+\n"
        "PlayResX: 1920\n"
        "PlayResY: 1080\n"
        "WrapStyle: 0\n"
        "ScaledBorderAndShadow: yes\n"
        "\n"
        "[V4+ Styles]\n"
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n"
        "Style: Default,Arial,48,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,2,2,10,10,10,1\n"
        "\n";
    d.format = split_format(std::string("Format: ") + kDefaultFormat);
    d.styles = {"Default"};
    d.start_index = 1;
    d.end_index = 2;
    d.text_index = 9;

    Event e;
    e.kind = "Dialogue";
    e.fields = {
        "0",
        agi::Time(0).GetAssFormatted(),
        agi::Time(2000).GetAssFormatted(),
        "Default", "", "0", "0", "0", "",
        "New line"
    };
    e.start_ms = 0;
    e.end_ms = 2000;
    d.events.push_back(std::move(e));
    return to_json(d);
}
