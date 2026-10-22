// In-app runner for libaegisub's upstream gtest suite.
//
// The suite is compiled into the same shared library as the NAPI module.  The
// runner recreates tests/setup.sh's data/ tree inside the app cache, chdirs
// there (many tests use relative "data/..." paths), captures stdout/stderr to
// latest.log and returns a JSON summary + the complete log to ArkTS.

#include "test_runner.h"

#include <gtest/gtest.h>

#include <libaegisub/dispatch.h>
#include <libaegisub/fs.h>
#include <libaegisub/log.h>
#include <libaegisub/util.h>

#include <cerrno>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <dirent.h>
#include <fstream>
#include <fcntl.h>
#include <mutex>
#include <sstream>
#include <string>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

namespace {

std::mutex g_mutex;
bool g_has_run = false;

void mkdir_p(const std::string& path) {
    std::string cur;
    for (char c : path) {
        cur += c;
        if (c == '/')
            mkdir(cur.c_str(), 0777);
    }
    if (!path.empty())
        mkdir(path.c_str(), 0777);
}

void write_file(const std::string& path, const std::string& data) {
    int fd = open(path.c_str(), O_CREAT | O_WRONLY | O_TRUNC, 0666);
    if (fd < 0)
        return;
    const char* p = data.data();
    size_t left = data.size();
    while (left > 0) {
        ssize_t n = write(fd, p, left);
        if (n <= 0)
            break;
        p += n;
        left -= static_cast<size_t>(n);
    }
    close(fd);
}

void rm_rf(const std::string& path) {
    struct stat st {};
    if (lstat(path.c_str(), &st) != 0)
        return;
    if (S_ISDIR(st.st_mode)) {
        DIR* d = opendir(path.c_str());
        if (d) {
            struct dirent* ent;
            while ((ent = readdir(d)) != nullptr) {
                if (strcmp(ent->d_name, ".") == 0 || strcmp(ent->d_name, "..") == 0)
                    continue;
                rm_rf(path + "/" + ent->d_name);
            }
            closedir(d);
        }
        rmdir(path.c_str());
    } else {
        unlink(path.c_str());
    }
}

// Mirrors tests/setup.sh from Aegisub v3.5.1.  Only the writable data/
// subtree is regenerated; the caller-provided fixtures (tests/keyframe, tests/vfr,
// ... and automation/include) are extracted separately and must survive.
void prepare_test_data(const std::string& root) {
    rm_rf(root + "/data");
    mkdir_p(root + "/data/dir");
    mkdir_p(root + "/data/options");
    mkdir_p(root + "/data/dir_iterator");
    mkdir_p(root + "/data/vfr/out");
    mkdir_p(root + "/data/keyframe");

    write_file(root + "/data/file", "");
    write_file(root + "/data/mru_ok.json",
               "{\"Video\" : [\"Entry One\", \"Entry Two\"]}\n");
    write_file(root + "/data/mru_invalid.json", "{\"Video\" : [1, 3]}\n");
    write_file(root + "/data/ten_bytes", "1234567890");
    write_file(root + "/data/touch_mod_time", "");
    write_file(root + "/data/dir_iterator/1.a", "");
    write_file(root + "/data/dir_iterator/2.a", "");
    write_file(root + "/data/dir_iterator/1.b", "");
    write_file(root + "/data/dir_iterator/2.b", "");

    chmod(root.c_str(), 0777);
    chmod((root + "/data").c_str(), 0777);
    chmod((root + "/data/file").c_str(), 0777);
}

std::string json_escape(const std::string& s) {
    std::string out;
    out.reserve(s.size() + 16);
    for (unsigned char c : s) {
        switch (c) {
            case '"':  out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c < 0x20) {
                    char buf[8];
                    snprintf(buf, sizeof buf, "\\u%04x", c);
                    out += buf;
                } else {
                    out += static_cast<char>(c);
                }
        }
    }
    return out;
}

std::string read_file(const std::string& path) {
    std::ifstream in(path, std::ios::binary);
    if (!in)
        return {};
    std::ostringstream ss;
    ss << in.rdbuf();
    return ss.str();
}

std::string error_json(const std::string& msg, const std::string& log_path) {
    std::string out = "{\"ok\":false,\"error\":\"";
    out += json_escape(msg);
    out += "\",\"logPath\":\"";
    out += json_escape(log_path);
    out += "\"}";
    return out;
}

} // namespace

std::string RunAegisubTests(const std::string& cacheDir, const std::string& fixtureDir) {
    std::lock_guard<std::mutex> lock(g_mutex);

    const std::string root = cacheDir + "/aegisub-tests";
    const std::string log_path = root + "/latest.log";

    if (g_has_run)
        return error_json("tests already ran in this process; restart the app to run again", log_path);
    g_has_run = true;

    prepare_test_data(root);
    if (chdir(root.c_str()) != 0)
        return error_json(std::string("chdir failed: ") + strerror(errno), log_path);

    setenv("AEGISUB_TEST_DATA_DIR", fixtureDir.c_str(), 1);
    setenv("TMPDIR", root.c_str(), 1);

    int saved_out = dup(STDOUT_FILENO);
    int saved_err = dup(STDERR_FILENO);
    int fd = open(log_path.c_str(), O_CREAT | O_WRONLY | O_TRUNC, 0600);
    if (fd < 0)
        return error_json(std::string("open log failed: ") + strerror(errno), log_path);
    dup2(fd, STDOUT_FILENO);
    dup2(fd, STDERR_FILENO);
    // Keep the log usable even if a test aborts the process.
    setvbuf(stdout, nullptr, _IONBF, 0);
    setvbuf(stderr, nullptr, _IONBF, 0);

    int rc = -1;
    int total = 0, passed = 0, failed = 0;
    const auto start = std::chrono::steady_clock::now();

    try {
        agi::dispatch::Init([](agi::dispatch::Thunk) {});
        agi::util::InitLocale();

        agi::log::log = new agi::log::LogSink;
        agi::log::log->Subscribe(std::make_unique<agi::log::JsonEmitter>(agi::fs::path(root)));
        srand(static_cast<unsigned>(time(nullptr)));

        char arg0[] = "aegisub-tests";
        char* argv[] = {arg0, nullptr};
        int argc = 1;
        testing::InitGoogleTest(&argc, argv);
        testing::GTEST_FLAG(color) = "no";
        testing::GTEST_FLAG(print_time) = true;

        rc = RUN_ALL_TESTS();

        auto* unit = testing::UnitTest::GetInstance();
        total = unit->total_test_count();
        passed = unit->successful_test_count();
        failed = unit->failed_test_count();
    } catch (const std::exception& e) {
        rc = -2;
        std::fprintf(stderr, "runner exception: %s\n", e.what());
    } catch (...) {
        rc = -3;
        std::fprintf(stderr, "runner exception: unknown\n");
    }

    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - start).count();

    std::fflush(stdout);
    std::fflush(stderr);
    dup2(saved_out, STDOUT_FILENO);
    dup2(saved_err, STDERR_FILENO);
    close(saved_out);
    close(saved_err);
    close(fd);

    if (agi::log::log) {
        delete agi::log::log;
        agi::log::log = nullptr;
    }

    const std::string log = read_file(log_path);
    std::string out = "{\"ok\":true,\"total\":";
    out += std::to_string(total);
    out += ",\"passed\":";
    out += std::to_string(passed);
    out += ",\"failed\":";
    out += std::to_string(failed);
    out += ",\"rc\":";
    out += std::to_string(rc);
    out += ",\"durationMs\":";
    out += std::to_string(static_cast<long long>(elapsed));
    out += ",\"logPath\":\"";
    out += json_escape(log_path);
    out += "\",\"log\":\"";
    out += json_escape(log);
    out += "\"}";

    // Keep the last summary for the next app launch (e.g. after a crash).
    write_file(root + "/latest.json", out);
    return out;
}
