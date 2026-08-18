#ifndef ULTRALIGHT_MANAGER_H
#define ULTRALIGHT_MANAGER_H

#ifdef WITH_ULTRALIGHT

#include <string>
#include <memory>
#include <Ultralight/Ultralight.h>
#include <Ultralight/Platform/FileSystem.h>
#include <Ultralight/Platform/FontLoader.h>
#include <framework/luaengine/luaobject.h>
#include <framework/graphics/declarations.h>

// FileSystem implementation that reads from the OTClient resource system (PhysFS)
class UltralightFileSystem : public ultralight::FileSystem {
public:
    bool FileExists(const ultralight::String& file_path) override;
    ultralight::String GetFileMimeType(const ultralight::String& file_path) override;
    ultralight::String GetFileCharset(const ultralight::String& file_path) override;
    ultralight::RefPtr<ultralight::Buffer> OpenFile(const ultralight::String& file_path) override;
};

// FontLoader implementation that loads system fonts from disk
class UltralightFontLoader : public ultralight::FontLoader {
public:
    ultralight::String fallback_font() const override;
    ultralight::String fallback_font_for_characters(const ultralight::String& characters, int weight, bool italic) const override;
    ultralight::RefPtr<ultralight::FontFile> Load(const ultralight::String& family, int weight, bool italic) override;
};

class UltralightManager : public LuaObject {
public:
    UltralightManager();
    ~UltralightManager();

    void init();
    void terminate();

    ultralight::RefPtr<ultralight::Renderer> getRenderer() { return m_renderer; }

    // Update timers and dispatch callbacks — call every frame
    void update();

    // Refresh display and render all views — call each frame after update()
    void render();

    bool isInitialized() { return m_initialized; }

    static UltralightManager& instance();

private:
    ultralight::RefPtr<ultralight::Renderer> m_renderer;
    std::unique_ptr<UltralightFileSystem> m_fileSystem;
    std::unique_ptr<UltralightFontLoader> m_fontLoader;
    bool m_initialized = false;
};

extern UltralightManager g_ultralightManager;

#endif // WITH_ULTRALIGHT
#endif // ULTRALIGHT_MANAGER_H
