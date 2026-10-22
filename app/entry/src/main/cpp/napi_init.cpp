#include <napi/native_api.h>

#include "ass_lite.h"
#include "ass_render.h"
#include "test_runner.h"

#include <atomic>
#include <cstring>
#include <string>

namespace {

std::atomic<bool> g_running {false};

struct WorkData {
    std::string cache_dir;
    std::string fixture_dir;
    std::string result;
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
};

std::string busy_json() {
    return "{\"ok\":false,\"error\":\"a test run is already in progress\"}";
}

void Execute(napi_env /*env*/, void* data) {
    auto* w = static_cast<WorkData*>(data);
    try {
        w->result = RunAegisubTests(w->cache_dir, w->fixture_dir);
    } catch (const std::exception& e) {
        w->result = std::string("{\"ok\":false,\"error\":\"exception: ") + e.what() + "\"}";
    } catch (...) {
        w->result = "{\"ok\":false,\"error\":\"unknown exception\"}";
    }
}

void Complete(napi_env env, napi_status status, void* data) {
    auto* w = static_cast<WorkData*>(data);
    napi_value result;
    napi_create_string_utf8(env, w->result.c_str(), NAPI_AUTO_LENGTH, &result);
    if (status == napi_ok)
        napi_resolve_deferred(env, w->deferred, result);
    else
        napi_reject_deferred(env, w->deferred, result);
    napi_delete_async_work(env, w->work);
    g_running.store(false);
    delete w;
}

napi_value RunTests(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char cache_dir[1024] = {0};
    char fixture_dir[1024] = {0};
    if (argc < 2 ||
        napi_get_value_string_utf8(env, args[0], cache_dir, sizeof cache_dir, nullptr) != napi_ok ||
        napi_get_value_string_utf8(env, args[1], fixture_dir, sizeof fixture_dir, nullptr) != napi_ok) {
        napi_throw_type_error(env, nullptr, "runTests(cacheDir: string, fixtureDir: string) requires two strings");
        return nullptr;
    }

    napi_value promise;
    napi_deferred deferred;
    napi_create_promise(env, &deferred, &promise);

    if (g_running.exchange(true)) {
        napi_value msg;
        std::string s = busy_json();
        napi_create_string_utf8(env, s.c_str(), NAPI_AUTO_LENGTH, &msg);
        napi_resolve_deferred(env, deferred, msg);
        return promise;
    }

    auto* w = new WorkData;
    w->cache_dir = cache_dir;
    w->fixture_dir = fixture_dir;
    w->deferred = deferred;

    napi_value resource_name;
    napi_create_string_utf8(env, "aegisub-test-run", NAPI_AUTO_LENGTH, &resource_name);
    napi_create_async_work(env, nullptr, resource_name, Execute, Complete, w, &w->work);
    napi_queue_async_work(env, w->work);
    return promise;
}

napi_value Version(napi_env env, napi_callback_info /*info*/) {
    napi_value result;
    const char* version = "Aegisub 3.5.1 / libaegisub core-only / OHOS arm64";
    napi_create_string_utf8(env, version, NAPI_AUTO_LENGTH, &result);
    return result;
}


napi_value LoadAss(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char path[1024] = {0};
    if (argc < 1 || napi_get_value_string_utf8(env, args[0], path, sizeof path, nullptr) != napi_ok) {
        napi_throw_type_error(env, nullptr, "loadAss(path: string) requires a string");
        return nullptr;
    }
    std::string json = LoadAssJson(path);
    napi_value result;
    napi_create_string_utf8(env, json.c_str(), NAPI_AUTO_LENGTH, &result);
    return result;
}

napi_value LoadSrt(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char path[1024] = {0};
    if (argc < 1 || napi_get_value_string_utf8(env, args[0], path, sizeof path, nullptr) != napi_ok) {
        napi_throw_type_error(env, nullptr, "loadSrt(path: string) requires a string");
        return nullptr;
    }
    std::string json = LoadSrtJson(path);
    napi_value result;
    napi_create_string_utf8(env, json.c_str(), NAPI_AUTO_LENGTH, &result);
    return result;
}

napi_value NewAss(napi_env env, napi_callback_info /*info*/) {
    std::string json = NewAssJson();
    napi_value result;
    napi_create_string_utf8(env, json.c_str(), NAPI_AUTO_LENGTH, &result);
    return result;
}

napi_value SrtTime(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char text[256] = {0};
    if (argc < 1 || napi_get_value_string_utf8(env, args[0], text, sizeof text, nullptr) != napi_ok) {
        napi_throw_type_error(env, nullptr, "srtTime(text: string) requires a string");
        return nullptr;
    }
    std::string out = NormalizeSrtTime(text);
    napi_value result;
    napi_create_string_utf8(env, out.c_str(), NAPI_AUTO_LENGTH, &result);
    return result;
}

napi_value TimeToMs(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char text[256] = {0};
    if (argc < 1 || napi_get_value_string_utf8(env, args[0], text, sizeof text, nullptr) != napi_ok) {
        napi_throw_type_error(env, nullptr, "timeToMs(text: string) requires a string");
        return nullptr;
    }
    napi_value result;
    napi_create_int32(env, AssTimeToMs(text), &result);
    return result;
}

napi_value MsToTime(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t ms = 0;
    if (argc < 1 || napi_get_value_int32(env, args[0], &ms) != napi_ok) {
        napi_throw_type_error(env, nullptr, "msToTime(ms: number) requires a number");
        return nullptr;
    }
    std::string out = MsToAssTime(ms);
    napi_value result;
    napi_create_string_utf8(env, out.c_str(), NAPI_AUTO_LENGTH, &result);
    return result;
}

napi_value NormalizeTime(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char text[256] = {0};
    if (argc < 1 || napi_get_value_string_utf8(env, args[0], text, sizeof text, nullptr) != napi_ok) {
        napi_throw_type_error(env, nullptr, "normalizeTime(text: string) requires a string");
        return nullptr;
    }
    std::string out = NormalizeAssTime(text);
    napi_value result;
    napi_create_string_utf8(env, out.c_str(), NAPI_AUTO_LENGTH, &result);
    return result;
}


napi_value ListFonts(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char cfg[1024] = {0};
    if (argc < 1 || napi_get_value_string_utf8(env, args[0], cfg, sizeof cfg, nullptr) != napi_ok) {
        napi_throw_type_error(env, nullptr, "listFonts(fontConfigPath: string) requires a string");
        return nullptr;
    }
    std::string out = ListFontsJson(cfg);
    napi_value result;
    napi_create_string_utf8(env, out.c_str(), NAPI_AUTO_LENGTH, &result);
    return result;
}

napi_value RenderAss(napi_env env, napi_callback_info info) {
    size_t argc = 6;
    napi_value args[6] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    char ass_path[1024] = {0};
    char font_path[1024] = {0};
    char font_config[1024] = {0};
    int32_t time_ms = 0, width = 0, height = 0;
    if (argc < 5 ||
        napi_get_value_string_utf8(env, args[0], ass_path, sizeof ass_path, nullptr) != napi_ok ||
        napi_get_value_int32(env, args[1], &time_ms) != napi_ok ||
        napi_get_value_int32(env, args[2], &width) != napi_ok ||
        napi_get_value_int32(env, args[3], &height) != napi_ok ||
        napi_get_value_string_utf8(env, args[4], font_path, sizeof font_path, nullptr) != napi_ok) {
        napi_throw_type_error(env, nullptr, "renderAss(path, timeMs, width, height, fontPath, fontConfig)");
        return nullptr;
    }
    if (argc >= 6) {
        napi_get_value_string_utf8(env, args[5], font_config, sizeof font_config, nullptr);
    }
    RenderedFrame frame = RenderAssFrame(ass_path, time_ms, width, height, font_path, font_config);
    if (!frame.ok) {
        napi_throw_error(env, nullptr, frame.error.c_str());
        return nullptr;
    }
    void* data = nullptr;
    napi_value buffer;
    if (napi_create_arraybuffer(env, frame.pixels.size(), &data, &buffer) != napi_ok) {
        napi_throw_error(env, nullptr, "cannot allocate pixel buffer");
        return nullptr;
    }
    std::memcpy(data, frame.pixels.data(), frame.pixels.size());
    napi_value obj;
    napi_create_object(env, &obj);
    napi_value v;
    napi_create_int32(env, frame.width, &v);
    napi_set_named_property(env, obj, "width", v);
    napi_create_int32(env, frame.height, &v);
    napi_set_named_property(env, obj, "height", v);
    napi_set_named_property(env, obj, "pixels", buffer);
    return obj;
}

napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"runTests", nullptr, RunTests, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"loadAss", nullptr, LoadAss, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"newAss", nullptr, NewAss, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"loadSrt", nullptr, LoadSrt, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"srtTime", nullptr, SrtTime, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"timeToMs", nullptr, TimeToMs, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"msToTime", nullptr, MsToTime, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"renderAss", nullptr, RenderAss, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"listFonts", nullptr, ListFonts, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"normalizeTime", nullptr, NormalizeTime, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"version", nullptr, Version, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}

} // namespace

static napi_module aegisub_module = {
    1, 0, nullptr, Init, "aegisubtest", nullptr, {0}
};

extern "C" __attribute__((constructor)) void RegisterAegisubModule(void) {
    napi_module_register(&aegisub_module);
}
