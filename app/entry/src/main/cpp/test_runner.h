#pragma once

#include <string>

// Runs the full libaegisub gtest suite inside the app sandbox.
// `cacheDir` is the app's cache directory; test data and logs are created there.
// Returns a JSON string; see test_runner.cpp for the schema.
std::string RunAegisubTests(const std::string& cacheDir, const std::string& fixtureDir);
