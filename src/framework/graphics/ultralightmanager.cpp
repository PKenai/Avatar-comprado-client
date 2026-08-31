#ifdef WITH_ULTRALIGHT

#include "ultralightmanager.h"
#include <framework/core/logger.h>
#include <framework/platform/platformwindow.h>
#include <Ultralight/Ultralight.h>
#include <Ultralight/Platform/Platform.h>
#include <Ultralight/Platform/Surface.h>
#include <AppCore/Platform.h>
#include <windows.h>
#include <memory>
#include <string>
#include <algorithm>

UltralightManager g_ultralightManager;

UltralightManager::UltralightManager() = default;
UltralightManager::~UltralightManager() { terminate(); }
UltralightManager& UltralightManager::instance() { return g_ultralightManager; }

class UltralightLogHandler : public ultralight::Logger {
public:
    void LogMessage(ultralight::LogLevel log_level, const ultralight::String& message) override {
        ultralight::String8 utf8 = message.utf8();
        std::string msg(utf8.data(), utf8.size());
        if (log_level == ultralight::LogLevel::Error) {
            g_logger.error("[Ultralight Core] " + msg);
        } else if (log_level == ultralight::LogLevel::Warning) {
            g_logger.warning("[Ultralight Core] " + msg);
        } else {
            g_logger.info("[Ultralight Core] " + msg);
        }
    }
};
static UltralightLogHandler g_ultralightLogger;

void UltralightManager::init() {
    if (m_initialized) return;

    g_logger.info("Ultralight: === STARTING INIT ===");

    try {
        char exePath[MAX_PATH] = {0};
        GetModuleFileNameA(NULL, exePath, MAX_PATH);
        std::string currentDir(exePath);
        size_t lastSlash = currentDir.find_last_of("\\/");
        if (lastSlash != std::string::npos) {
            currentDir = currentDir.substr(0, lastSlash + 1);
        }
        std::replace(currentDir.begin(), currentDir.end(), '\\', '/');
        g_logger.info("Ultralight: base directory is " + currentDir);

        ultralight::Platform& platform = ultralight::Platform::instance();
        platform.set_logger(&g_ultralightLogger);

        ultralight::Config config;
        config.resource_path_prefix = "resources/";
        config.force_repaint = false;
        platform.set_config(config);
        g_logger.info("Ultralight: config set (resource_path_prefix: resources/)");

        ultralight::FontLoader* fl = ultralight::GetPlatformFontLoader();
        if (fl) {
            platform.set_font_loader(fl);
            g_logger.info("Ultralight: font loader set OK");
        } else {
            g_logger.error("Ultralight: GetPlatformFontLoader() returned null");
        }

        ultralight::FileSystem* fs = ultralight::GetPlatformFileSystem(ultralight::String(currentDir.c_str()));
        if (fs) {
            platform.set_file_system(fs);
            g_logger.info("Ultralight: file system set OK with base " + currentDir);
        } else {
            g_logger.error("Ultralight: GetPlatformFileSystem() returned null");
        }

        m_renderer = ultralight::Renderer::Create();
        if (!m_renderer) {
            g_logger.error("Ultralight: Renderer::Create() returned null");
            return;
        }
        g_logger.info("Ultralight: renderer created OK");

        // Warm up test View
        g_logger.info("Ultralight: testing 100x100 view creation...");
        ultralight::ViewConfig testCfg;
        testCfg.initial_device_scale = 1.0;
        testCfg.is_transparent = false;
        testCfg.enable_images = false;
        testCfg.enable_javascript = false;
        testCfg.is_accelerated = false;

        auto testView = m_renderer->CreateView(100, 100, testCfg, nullptr);
        if (testView) {
            g_logger.info("Ultralight: 100x100 test view created OK!");
            testView = nullptr;
        } else {
            g_logger.error("Ultralight: 100x100 test view returned null");
        }

        m_renderer->Update();
        g_logger.info("Ultralight: initial Update() OK");

        m_initialized = true;
        g_logger.info("Ultralight: === INIT COMPLETE ===");
    } catch (const std::exception& e) {
        g_logger.error("Ultralight: exception during init: " + std::string(e.what()));
    } catch (...) {
        g_logger.error("Ultralight: unknown exception during init");
    }
}

void UltralightManager::terminate() {
    if (!m_initialized) return;
    try {
        m_renderer = nullptr;
        m_initialized = false;
        g_logger.info("Ultralight: terminated");
    } catch (...) {}
}

void UltralightManager::update() {
    if (!m_initialized || !m_renderer) return;
    try {
        m_renderer->Update();
    } catch (...) {}
}

void UltralightManager::render() {
    if (!m_initialized || !m_renderer) return;
    try {
        m_renderer->RefreshDisplay(0);
        m_renderer->Render();
    } catch (...) {}
}

#endif // WITH_ULTRALIGHT
