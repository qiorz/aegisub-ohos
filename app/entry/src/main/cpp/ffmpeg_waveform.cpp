#include "ffmpeg_waveform.h"

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/channel_layout.h>
#include <libavutil/samplefmt.h>
}

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

namespace {

std::string err(const char* msg) {
    return std::string("{\"ok\":false,\"error\":\"") + msg + "\"}";
}

double sampleAt(const AVFrame* frame, int ch, int i) {
    const int channels = frame->ch_layout.nb_channels > 0 ? frame->ch_layout.nb_channels : 1;
    const int fmt = frame->format;
    auto planar = [&](int bytes) -> const uint8_t* {
        return frame->extended_data[ch] + static_cast<size_t>(i) * bytes;
    };
    auto packed = [&](int bytes) -> const uint8_t* {
        return frame->extended_data[0] + (static_cast<size_t>(i) * channels + ch) * bytes;
    };
    switch (fmt) {
    case AV_SAMPLE_FMT_U8: {
        return std::fabs((static_cast<int>(*packed(1)) - 128) / 128.0);
    }
    case AV_SAMPLE_FMT_U8P: {
        return std::fabs((static_cast<int>(*planar(1)) - 128) / 128.0);
    }
    case AV_SAMPLE_FMT_S16: {
        int16_t v; std::memcpy(&v, packed(2), 2); return std::fabs(v / 32768.0);
    }
    case AV_SAMPLE_FMT_S16P: {
        int16_t v; std::memcpy(&v, planar(2), 2); return std::fabs(v / 32768.0);
    }
    case AV_SAMPLE_FMT_S32: {
        int32_t v; std::memcpy(&v, packed(4), 4); return std::fabs(v / 2147483648.0);
    }
    case AV_SAMPLE_FMT_S32P: {
        int32_t v; std::memcpy(&v, planar(4), 4); return std::fabs(v / 2147483648.0);
    }
    case AV_SAMPLE_FMT_FLT: {
        float v; std::memcpy(&v, packed(4), 4); return std::fabs(v);
    }
    case AV_SAMPLE_FMT_FLTP: {
        float v; std::memcpy(&v, planar(4), 4); return std::fabs(v);
    }
    case AV_SAMPLE_FMT_DBL: {
        double v; std::memcpy(&v, packed(8), 8); return std::fabs(v);
    }
    case AV_SAMPLE_FMT_DBLP: {
        double v; std::memcpy(&v, planar(8), 8); return std::fabs(v);
    }
    default:
        return 0.0;
    }
}

bool addFrame(const AVFrame* frame, double startTime, double duration, int buckets,
              std::vector<float>& peaks, int sampleRate) {
    if (frame->nb_samples <= 0 || !frame->extended_data) return false;
    const int channels = frame->ch_layout.nb_channels > 0 ? frame->ch_layout.nb_channels : 1;
    for (int i = 0; i < frame->nb_samples; ++i) {
        double peak = 0.0;
        for (int ch = 0; ch < channels; ++ch) {
            peak = std::max(peak, sampleAt(frame, ch, i));
        }
        const double sampleTime = startTime + (sampleRate > 0 ? static_cast<double>(i) / sampleRate : 0.0);
        int bucket = duration > 0 ? static_cast<int>(sampleTime / duration * buckets) : 0;
        bucket = std::max(0, std::min(buckets - 1, bucket));
        peaks[static_cast<size_t>(bucket)] =
            std::max(peaks[static_cast<size_t>(bucket)], static_cast<float>(std::min(1.0, peak)));
    }
    return true;
}

} // namespace

std::string VideoWaveformJson(const std::string& path, int buckets) {
    if (buckets < 16) buckets = 16;
    if (buckets > 2000) buckets = 2000;
    av_log_set_level(AV_LOG_ERROR);

    AVFormatContext* fmt = nullptr;
    if (avformat_open_input(&fmt, path.c_str(), nullptr, nullptr) < 0) return err("open failed");
    if (avformat_find_stream_info(fmt, nullptr) < 0) {
        avformat_close_input(&fmt);
        return err("stream info failed");
    }
    const int idx = av_find_best_stream(fmt, AVMEDIA_TYPE_AUDIO, -1, -1, nullptr, 0);
    if (idx < 0) {
        avformat_close_input(&fmt);
        return err("no audio stream");
    }
    AVStream* stream = fmt->streams[idx];
    const AVCodec* codec = avcodec_find_decoder(stream->codecpar->codec_id);
    if (!codec) {
        avformat_close_input(&fmt);
        return err("audio codec unsupported");
    }
    AVCodecContext* ctx = avcodec_alloc_context3(codec);
    if (!ctx) {
        avformat_close_input(&fmt);
        return err("decoder alloc failed");
    }
    if (avcodec_parameters_to_context(ctx, stream->codecpar) < 0 ||
        avcodec_open2(ctx, codec, nullptr) < 0) {
        avcodec_free_context(&ctx);
        avformat_close_input(&fmt);
        return err("decoder open failed");
    }
    ctx->pkt_timebase = stream->time_base;

    double duration = 0.0;
    if (fmt->duration > 0) {
        duration = static_cast<double>(fmt->duration) / AV_TIME_BASE;
    } else if (stream->duration > 0) {
        duration = stream->duration * av_q2d(stream->time_base);
    }
    if (duration <= 0.0) {
        avcodec_free_context(&ctx);
        avformat_close_input(&fmt);
        return err("unknown duration");
    }

    std::vector<float> peaks(static_cast<size_t>(buckets), 0.0f);
    AVPacket* packet = av_packet_alloc();
    AVFrame* frame = av_frame_alloc();
    int64_t decoded = 0;
    auto handle = [&](AVFrame* f) {
        double t = 0.0;
        if (f->best_effort_timestamp != AV_NOPTS_VALUE) {
            t = f->best_effort_timestamp * av_q2d(stream->time_base);
        } else if (ctx->sample_rate > 0) {
            t = static_cast<double>(decoded) / ctx->sample_rate;
        }
        addFrame(f, t, duration, buckets, peaks, ctx->sample_rate);
        decoded += f->nb_samples;
    };
    while (av_read_frame(fmt, packet) >= 0) {
        if (packet->stream_index == idx && avcodec_send_packet(ctx, packet) >= 0) {
            while (avcodec_receive_frame(ctx, frame) >= 0) {
                handle(frame);
                av_frame_unref(frame);
            }
        }
        av_packet_unref(packet);
    }
    avcodec_send_packet(ctx, nullptr);
    while (avcodec_receive_frame(ctx, frame) >= 0) {
        handle(frame);
        av_frame_unref(frame);
    }
    av_frame_free(&frame);
    av_packet_free(&packet);
    avcodec_free_context(&ctx);
    avformat_close_input(&fmt);

    std::string out = "{\"ok\":true,\"peaks\":[";
    char buf[32];
    for (int i = 0; i < buckets; ++i) {
        if (i) out += ',';
        std::snprintf(buf, sizeof buf, "%.3f", peaks[static_cast<size_t>(i)]);
        out += buf;
    }
    out += "]}";
    return out;
}
