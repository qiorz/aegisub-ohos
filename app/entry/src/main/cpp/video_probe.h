#pragma once
#include <string>

// Read MP4/MOV metadata and return {"ok":true,"fps":...,"width":...,"height":...}
// or {"ok":false,"error":"..."}. MKV/TS are intentionally unsupported.
std::string VideoProbeJson(const std::string& path);
