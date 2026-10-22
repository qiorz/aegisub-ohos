// Local qemu harness for the same test_runner.cpp used by the HAP.
// Not part of the HAP build; see scripts/build-test-runner-qemu.sh.
#include "test_runner.h"

#include <cstdio>
#include <string>

int main(int argc, char** argv) {
    const std::string cache = argc > 1 ? argv[1] : "/tmp/aegisub-app-cache";
    const std::string fixtures = argc > 2 ? argv[2] : "/tmp/aegisub-fixtures";
    const std::string result = RunAegisubTests(cache, fixtures);
    std::fwrite(result.data(), 1, result.size(), stdout);
    std::fputc('\n', stdout);
    return 0;
}
