#ifdef WITH_ULTRALIGHT

#include "uiwebview.h"
#include "ultralightmanager.h"
#include "graphics.h"
#include "texture.h"
#include "image.h"
#include "graph.h"
#include <framework/core/logger.h>
#include <framework/core/eventdispatcher.h>
#include <framework/graphics/painter.h>
#include <framework/platform/platformwindow.h>
#include <Ultralight/Bitmap.h>
#include <mutex>

static std::string toStr(const ultralight::String& str) {
    ultralight::String8 utf8 = str.utf8();
    return std::string(utf8.data(), utf8.size());
}

static ultralight::MouseEvent::Button mapMouseButton(Fw::MouseButton button) {
    switch (button) {
        case Fw::MouseLeftButton:   return ultralight::MouseEvent::kButton_Left;
        case Fw::MouseRightButton:  return ultralight::MouseEvent::kButton_Right;
        case Fw::MouseMidButton:    return ultralight::MouseEvent::kButton_Middle;
        default: return ultralight::MouseEvent::kButton_None;
    }
}

static uint32_t mapModifiers(int modifiers) {
    uint32_t result = 0;
    if (modifiers & Fw::KeyboardShiftModifier) result |= ultralight::KeyEvent::kMod_ShiftKey;
    if (modifiers & Fw::KeyboardCtrlModifier)  result |= ultralight::KeyEvent::kMod_CtrlKey;
    if (modifiers & Fw::KeyboardAltModifier)   result |= ultralight::KeyEvent::kMod_AltKey;
    return result;
}

// ── UIWebView ────────────────────────────────────────────────────────────────

UIWebView::UIWebView() = default;
UIWebView::~UIWebView() { m_view = nullptr; m_texture = nullptr; }

void UIWebView::create(int width, int height) {
    if (m_created) return;

    auto& mgr = UltralightManager::instance();
    if (!mgr.isInitialized()) mgr.init();
    if (!mgr.isInitialized()) { g_logger.error("UIWebView: Ultralight not available!"); return; }

    auto renderer = mgr.getRenderer();
    if (!renderer) { g_logger.error("UIWebView: No renderer!"); return; }

    ultralight::ViewConfig config;
    config.initial_device_scale = 1.0;
    config.is_transparent = m_transparent;
    config.enable_images = true;
    config.enable_javascript = true;
    config.enable_compositor = false;
    config.is_accelerated = false;

    m_view = renderer->CreateView(width, height, config, nullptr);
    if (!m_view) { g_logger.error("UIWebView: Failed to create view!"); return; }

    m_viewWidth = width;
    m_viewHeight = height;
    m_created = true;

    std::vector<unsigned char> white(width * height * 4, 255);
    ImagePtr img(new Image(Size(width, height), 4, white.data()));
    m_texture = TexturePtr(new Texture(img));

    g_logger.info("UIWebView: Created view");
}

void UIWebView::loadHTML(const std::string& html, const std::string& baseUrl) {
    if (!m_view) return;
    m_view->LoadHTML(ultralight::String(html.c_str(), html.size()),
                     ultralight::String(baseUrl.c_str(), baseUrl.size()));
    m_needsTextureUpdate = true;
}

void UIWebView::loadURL(const std::string& url) {
    if (m_view) m_view->LoadURL(ultralight::String(url.c_str(), url.size()));
}

std::string UIWebView::executeScript(const std::string& script) {
    if (!m_view) return "";
    ultralight::String exception;
    return toStr(m_view->EvaluateScript(ultralight::String(script.c_str(), script.size()), &exception));
}

void UIWebView::reload() { if (m_view) m_view->Reload(); }

void UIWebView::resizeView(int width, int height) {
    if (!m_view || width <= 0 || height <= 0) return;
    m_view->Resize(width, height);
    m_viewWidth = width;
    m_viewHeight = height;
    m_needsTextureUpdate = true;
}

void UIWebView::setTransparent(bool t) { m_transparent = t; }
void UIWebView::setJavaScriptEnabled(bool) {}
std::string UIWebView::getURL() { return m_view ? toStr(m_view->url()) : ""; }
std::string UIWebView::getTitle() { return m_view ? toStr(m_view->title()) : ""; }
bool UIWebView::isLoading() { return m_view ? m_view->is_loading() : false; }
void UIWebView::setOnURLChange(const std::string& cb) { m_jsCallbackName = cb; }

// ── CPU pixel copy ───────────────────────────────────────────────────────────

void UIWebView::copyPixelsFromSurface() {
    if (!m_view || !m_needsTextureUpdate) return;
    auto* surface = m_view->surface();
    if (!surface || surface->dirty_bounds().IsEmpty()) return;

    auto* bs = static_cast<ultralight::BitmapSurface*>(surface);
    auto bmp = bs->bitmap();
    if (!bmp) return;

    uint32_t bmpW = bmp->width(), bmpH = bmp->height();
    if (bmpW == 0 || bmpH == 0) return;

    const void* raw = bmp->LockPixels();
    if (!raw) return;

    std::lock_guard<std::mutex> lock(m_pixelMutex);
    m_pendingPixels.resize(bmpW * bmpH * 4);
    m_pendingWidth = bmpW;
    m_pendingHeight = bmpH;
    const unsigned char* src = static_cast<const unsigned char*>(raw);
    for (uint32_t i = 0; i < bmpW * bmpH; i++) {
        m_pendingPixels[i*4+0] = src[i*4+2];
        m_pendingPixels[i*4+1] = src[i*4+1];
        m_pendingPixels[i*4+2] = src[i*4+0];
        m_pendingPixels[i*4+3] = src[i*4+3];
    }
    m_hasPendingPixels = true;
    bmp->UnlockPixels();
    surface->ClearDirtyBounds();
    m_needsTextureUpdate = false;
}

void UIWebView::pendingTextureUpdate() {
    if (!m_view || !m_needsTextureUpdate) return;
    copyPixelsFromSurface();
}

// ── Rendering ────────────────────────────────────────────────────────────────

void UIWebView::drawSelf(Fw::DrawPane drawPane) {
    if (drawPane != Fw::ForegroundPane) return;
    UIWidget::drawSelf(drawPane);
    if (!m_created || !m_texture || m_texture->isEmpty()) return;

    // NO texture updates at all — just draw the initial white texture
    // This proves the widget renders without GL errors

    Rect screenCoords = getPaddingRect();
    Rect srcRect(0, 0, m_viewWidth, m_viewHeight);
    g_painter->drawTexturedRect(screenCoords, m_texture, srcRect);
}

// ── Input Events ─────────────────────────────────────────────────────────────

bool UIWebView::onMousePress(const Point& mousePos, Fw::MouseButton button) {
    if (!m_view) return false;
    Rect r = getPaddingRect();
    ultralight::MouseEvent evt;
    evt.type = ultralight::MouseEvent::kType_MouseDown;
    evt.x = mousePos.x - r.left(); evt.y = mousePos.y - r.top();
    evt.button = mapMouseButton(button);
    m_view->FireMouseEvent(evt);
    focus();
    return true;
}

bool UIWebView::onMouseRelease(const Point& mousePos, Fw::MouseButton button) {
    if (!m_view) return false;
    Rect r = getPaddingRect();
    ultralight::MouseEvent evt;
    evt.type = ultralight::MouseEvent::kType_MouseUp;
    evt.x = mousePos.x - r.left(); evt.y = mousePos.y - r.top();
    evt.button = mapMouseButton(button);
    m_view->FireMouseEvent(evt);
    return true;
}

bool UIWebView::onMouseMove(const Point& mousePos, const Point& mouseMoved) {
    if (!m_view) return false;
    Rect r = getPaddingRect();
    ultralight::MouseEvent evt;
    evt.type = ultralight::MouseEvent::kType_MouseMoved;
    evt.x = mousePos.x - r.left(); evt.y = mousePos.y - r.top();
    evt.button = ultralight::MouseEvent::kButton_None;
    m_view->FireMouseEvent(evt);
    return true;
}

bool UIWebView::onMouseWheel(const Point& mousePos, Fw::MouseWheelDirection direction) {
    if (!m_view) return false;
    ultralight::ScrollEvent evt;
    evt.type = ultralight::ScrollEvent::kType_ScrollByPixel;
    evt.delta_x = 0;
    evt.delta_y = (direction == Fw::MouseWheelUp) ? -100 : 100;
    m_view->FireScrollEvent(evt);
    return true;
}

bool UIWebView::onKeyPress(uchar keyCode, int keyboardModifiers, int autoRepeatTicks) {
    if (!m_view) return false;
    ultralight::KeyEvent evt;
    evt.type = ultralight::KeyEvent::kType_RawKeyDown;
    evt.virtual_key_code = static_cast<int>(keyCode);
    evt.modifiers = mapModifiers(keyboardModifiers);
    evt.native_key_code = keyCode;
    evt.is_keypad = false;
    evt.is_auto_repeat = (autoRepeatTicks > 0);
    evt.is_system_key = false;
    m_view->FireKeyEvent(evt);
    return true;
}

bool UIWebView::onKeyDown(uchar keyCode, int keyboardModifiers) {
    if (!m_view) return false;
    ultralight::KeyEvent evt;
    evt.type = ultralight::KeyEvent::kType_RawKeyDown;
    evt.virtual_key_code = static_cast<int>(keyCode);
    evt.modifiers = mapModifiers(keyboardModifiers);
    evt.native_key_code = keyCode;
    evt.is_keypad = false;
    evt.is_auto_repeat = false;
    evt.is_system_key = false;
    m_view->FireKeyEvent(evt);
    return true;
}

bool UIWebView::onKeyUp(uchar keyCode, int keyboardModifiers) {
    if (!m_view) return false;
    ultralight::KeyEvent evt;
    evt.type = ultralight::KeyEvent::kType_KeyUp;
    evt.virtual_key_code = static_cast<int>(keyCode);
    evt.modifiers = mapModifiers(keyboardModifiers);
    evt.native_key_code = keyCode;
    evt.is_keypad = false;
    evt.is_auto_repeat = false;
    evt.is_system_key = false;
    m_view->FireKeyEvent(evt);
    return true;
}

bool UIWebView::onKeyText(const std::string& keyText) {
    if (!m_view || keyText.empty()) return false;
    ultralight::KeyEvent evt;
    evt.type = ultralight::KeyEvent::kType_Char;
    evt.text = ultralight::String(keyText.c_str(), keyText.size());
    evt.unmodified_text = evt.text;
    evt.modifiers = 0;
    evt.is_keypad = false;
    evt.is_auto_repeat = false;
    evt.is_system_key = false;
    m_view->FireKeyEvent(evt);
    return true;
}

void UIWebView::onGeometryChange(const Rect& oldRect, const Rect& newRect) {
    UIWidget::onGeometryChange(oldRect, newRect);
    if (m_created && m_view) {
        Size sz = newRect.size();
        if (sz.width() != m_viewWidth || sz.height() != m_viewHeight)
            resizeView(sz.width(), sz.height());
    }
}

void UIWebView::onStyleApply(const std::string& styleName, const OTMLNodePtr& styleNode) {
    UIWidget::onStyleApply(styleName, styleNode);
    for (const OTMLNodePtr& node : styleNode->children()) {
        const std::string& tag = node->tag();
        if (tag == "html-content") loadHTML(node->value<std::string>());
        else if (tag == "url") loadURL(node->value<std::string>());
        else if (tag == "transparent") setTransparent(node->value<bool>());
    }
}

#endif // WITH_ULTRALIGHT
