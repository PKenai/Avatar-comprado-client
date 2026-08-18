#ifdef WITH_ULTRALIGHT

#include "ultralightmanager.h"
#include <framework/graphics/graphics.h>
#include <framework/platform/platform.h>
#include <framework/core/logger.h>

#include <Ultralight/Ultralight.h>
#include <Ultralight/Platform/Platform.h>
#include <Ultralight/Platform/FileSystem.h>
#include <Ultralight/Platform/FontLoader.h>
#include <Ultralight/Platform/Surface.h>
#include <GL/glew.h>

#include <algorithm>
#include <cstdio>
#include <vector>

static std::string toStdString(const ultralight::String& str) {
    ultralight::String8 utf8 = str.utf8();
    return std::string(utf8.data(), utf8.size());
}

static ultralight::String fromStdString(const std::string& str) {
    return ultralight::String(str.c_str(), str.size());
}

// ── UltralightFileSystem ─────────────────────────────────────────────────────

bool UltralightFileSystem::FileExists(const ultralight::String& file_path) {
    std::string path = toStdString(file_path);
    FILE* fp = fopen(path.c_str(), "rb");
    if (fp) { fclose(fp); return true; }
    return false;
}

ultralight::String UltralightFileSystem::GetFileMimeType(const ultralight::String& file_path) {
    std::string p = toStdString(file_path);
    std::transform(p.begin(), p.end(), p.begin(), ::tolower);
    if (p.find(".html") != std::string::npos || p.find(".htm") != std::string::npos) return "text/html";
    if (p.find(".css") != std::string::npos) return "text/css";
    if (p.find(".js") != std::string::npos) return "application/javascript";
    if (p.find(".json") != std::string::npos) return "application/json";
    if (p.find(".png") != std::string::npos) return "image/png";
    if (p.find(".jpg") != std::string::npos || p.find(".jpeg") != std::string::npos) return "image/jpeg";
    if (p.find(".gif") != std::string::npos) return "image/gif";
    if (p.find(".svg") != std::string::npos) return "image/svg+xml";
    if (p.find(".woff") != std::string::npos) return "font/woff";
    if (p.find(".woff2") != std::string::npos) return "font/woff2";
    if (p.find(".ttf") != std::string::npos) return "font/ttf";
    if (p.find(".otf") != std::string::npos) return "font/otf";
    if (p.find(".dat") != std::string::npos) return "application/octet-stream";
    if (p.find(".pem") != std::string::npos) return "application/x-pem-file";
    return "application/octet-stream";
}

ultralight::String UltralightFileSystem::GetFileCharset(const ultralight::String& file_path) {
    return "utf-8";
}

ultralight::RefPtr<ultralight::Buffer> UltralightFileSystem::OpenFile(const ultralight::String& file_path) {
    std::string path = toStdString(file_path);

    // Use native file I/O (not PhysFS) since Ultralight needs its own resources
    FILE* fp = fopen(path.c_str(), "rb");
    if (!fp) return nullptr;

    fseek(fp, 0, SEEK_END);
    long fileSize = ftell(fp);
    fseek(fp, 0, SEEK_SET);
    if (fileSize <= 0) { fclose(fp); return nullptr; }

    std::vector<unsigned char> data(static_cast<size_t>(fileSize));
    size_t bytesRead = fread(data.data(), 1, static_cast<size_t>(fileSize), fp);
    fclose(fp);

    if (bytesRead == 0) return nullptr;
    return ultralight::Buffer::CreateFromCopy(data.data(), bytesRead);
}

// ── UltralightFontLoader ─────────────────────────────────────────────────────

ultralight::String UltralightFontLoader::fallback_font() const { return "Arial"; }
ultralight::String UltralightFontLoader::fallback_font_for_characters(const ultralight::String&, int, bool) const { return "Arial"; }

ultralight::RefPtr<ultralight::FontFile> UltralightFontLoader::Load(const ultralight::String& family, int weight, bool italic) {
    std::string dir = "C:\\Windows\\Fonts\\";
    std::string f = toStdString(family);
    std::string ext = italic ? ".itf" : ".ttf";
    std::vector<std::string> candidates = {
        dir + f + ext, dir + f + ".ttf", dir + f + ".TTF",
        dir + f + ".otf", dir + f + ".OTF"
    };
    if (weight >= 700) {
        candidates.push_back(dir + f + "bd" + ext);
        candidates.push_back(dir + f + "Bold.ttf");
        candidates.push_back(dir + f + "-Bold.ttf");
    }
    for (const auto& path : candidates) {
        FILE* fp = fopen(path.c_str(), "rb");
        if (fp) { fclose(fp); return ultralight::FontFile::Create(fromStdString(path)); }
    }
    return nullptr;
}

// ── UltralightManager ────────────────────────────────────────────────────────

UltralightManager g_ultralightManager;

UltralightManager::UltralightManager() = default;
UltralightManager::~UltralightManager() { terminate(); }
UltralightManager& UltralightManager::instance() { return g_ultralightManager; }

void UltralightManager::init() {
    if (m_initialized) return;

    g_logger.info("Ultralight: initializing...");

    try {
        ultralight::Platform& platform = ultralight::Platform::instance();

        ultralight::Config config;
        config.resource_path_prefix = "resources/";
        config.face_winding = ultralight::FaceWinding::Clockwise;
        config.font_hinting = ultralight::FontHinting::Smooth;
        config.font_gamma = 1.8;
        config.force_repaint = false;
        platform.set_config(config);

        m_fileSystem = std::make_unique<UltralightFileSystem>();
        platform.set_file_system(m_fileSystem.get());

        m_fontLoader = std::make_unique<UltralightFontLoader>();
        platform.set_font_loader(m_fontLoader.get());

        g_logger.info("Ultralight: creating renderer...");

        m_renderer = ultralight::Renderer::Create();
        if (!m_renderer) {
            g_logger.info("Ultralight: failed to create renderer!");
            return;
        }

        m_initialized = true;
        g_logger.info("Ultralight: initialized successfully");

        // Clear any GL errors that Ultralight initialization may have caused
        while (glGetError() != GL_NO_ERROR) {}
    } catch (...) {
        g_logger.info("Ultralight: exception during initialization");
    }
}

void UltralightManager::terminate() {
    if (!m_initialized) return;
    try {
        m_renderer = nullptr;
        m_fileSystem.reset();
        m_fontLoader.reset();
        m_initialized = false;
        g_logger.info("Ultralight: terminated");
    } catch (...) {
    }
}

void UltralightManager::update() {
    if (!m_initialized || !m_renderer) return;
    try { m_renderer->Update(); } catch (...) { }
}

void UltralightManager::render() {
    if (!m_initialized || !m_renderer) return;
    try {
        m_renderer->RefreshDisplay(0);
        m_renderer->Render();
    } catch (...) { }
}

#endif // WITH_ULTRALIGHT
