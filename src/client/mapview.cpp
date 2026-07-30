/*
 * Copyright (c) 2010-2017 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "mapview.h"

#include "creature.h"
#include "map.h"
#include "tile.h"
#include "statictext.h"
#include "animatedtext.h"
#include "missile.h"
#include "lightview.h"
#include "localplayer.h"
#include "game.h"
#include "spritemanager.h"

#include <framework/graphics/graphics.h>
#include <framework/graphics/image.h>
#include <framework/graphics/framebuffermanager.h>
#include <framework/core/eventdispatcher.h>
#include <framework/core/application.h>
#include <framework/core/resourcemanager.h>
#include <framework/graphics/texturemanager.h>
#include <framework/graphics/atlas.h>
#include <framework/graphics/shadermanager.h>

#include <framework/util/extras.h>
#include <framework/core/adaptiverenderer.h>
#include <framework/core/clock.h>
#include <algorithm>
#include <cmath>

MapView::MapView()
{
    m_lockedFirstVisibleFloor = -1;
    m_cachedFirstVisibleFloor = 7;
    m_cachedLastVisibleFloor = 7;
    m_minimumAmbientLight = 0;
    m_optimizedSize = Size(g_map.getAwareRange().horizontal(), g_map.getAwareRange().vertical()) * g_sprites.spriteSize();

    setVisibleDimension(Size(15, 11));
}

MapView::~MapView()
{
    VALIDATE(!g_app.isTerminated());
}

void MapView::drawTileTexts(const Rect& rect, const Rect& srcRect)
{
    Position cameraPosition = getCameraPosition();
    Point drawOffset = srcRect.topLeft();
    float horizontalStretchFactor = rect.width() / (float)srcRect.width();
    float verticalStretchFactor = rect.height() / (float)srcRect.height();

    auto player = g_game.getLocalPlayer();
    auto floor = player->getPosition().z;
    for (auto& tile : m_cachedVisibleTiles[floor]) {
        Position tilePos = tile->getPosition();
        Point p = transformPositionTo2D(tilePos, cameraPosition) - drawOffset;
        p.x *= horizontalStretchFactor;
        p.y *= verticalStretchFactor;
        p += rect.topLeft();
        p.y += 5;

        tile->drawTexts(p);
    }
}

void MapView::drawTileWidget(const Rect& rect, const Rect& srcRect)
{
    Position cameraPosition = getCameraPosition();
    Point drawOffset = srcRect.topLeft();
    float horizontalStretchFactor = rect.width() / (float)srcRect.width();
    float verticalStretchFactor = rect.height() / (float)srcRect.height();

    auto player = g_game.getLocalPlayer();
    auto floor = player->getPosition().z;
    for (auto& tile : m_cachedVisibleTiles[floor]) {
        Position tilePos = tile->getPosition();
        if (tilePos.z != player->getPosition().z) continue;

        Point p = transformPositionTo2D(tilePos, cameraPosition) - drawOffset;
        p.x *= horizontalStretchFactor;
        p.y *= verticalStretchFactor;
        p += rect.topLeft();

        size_t drawQueueStart = g_drawQueue->size();
        tile->drawWidget(p);
        g_drawQueue->setClip(drawQueueStart, rect);
    }
}

void MapView::drawMapBackground(const Rect& rect, const TilePtr& crosshairTile) {
    Position cameraPosition = getCameraPosition();
    if (m_mustUpdateVisibleTilesCache) {
        updateVisibleTilesCache();
    }

    if (g_game.getFeature(Otc::GameForceLight)) {
        m_drawLight = true;
        m_minimumAmbientLight = 0.05f;
    }

    Rect srcRect = calcFramebufferSource(rect.size());
    g_drawQueue->setFrameBuffer(rect, m_optimizedSize, srcRect);

    if (m_drawLight) {
        Light ambientLight;
        if (cameraPosition.z <= Otc::SEA_FLOOR)
            ambientLight = g_map.getLight();
        if (!m_lightTexture || m_lightTexture->getSize() != m_drawDimension)
            m_lightTexture = TexturePtr(new Texture(m_drawDimension, false, true));
        m_lightView = std::make_unique<LightView>(m_lightTexture, m_drawDimension, rect, srcRect, ambientLight.color,
                                                  std::max<int>(m_minimumAmbientLight * 255, ambientLight.intensity));
    }

    for (int z = m_cachedLastVisibleFloor; z >= m_cachedFirstFadingFloor; --z) {
        float fading = 1.0;
        if (m_floorFading > 0) {
            fading = 0.;
            if (m_floorFading > 0) {
                fading = stdext::clamp<float>((float)m_fadingFloorTimers[z].elapsed_millis() / (float)m_floorFading, 0.f, 1.f);
                if (z < m_cachedFirstVisibleFloor)
                    fading = 1.0 - fading;
            }
            if (fading == 0) break;
        }

        size_t floorStart = g_drawQueue->size();
        if (g_game.getFeature(Otc::GameDrawFloorShadow)) {
            if (cameraPosition.z >= Otc::UNDERGROUND_FLOOR && cameraPosition.z == z) {
                g_drawQueue->addFilledRect(srcRect, m_floorShadow);
            }
        }
        drawFloor(z, cameraPosition, crosshairTile);

        if (m_drawSkyClouds && g_game.getFeature(Otc::GameDrawSkyClouds)
            && cameraPosition.z <= Otc::SEA_FLOOR && z == cameraPosition.z) {
            drawSkyCloudBodies(cameraPosition);
        }

        if (fading < 0.99)
            g_drawQueue->setOpacity(floorStart, fading);
    }

} 

void MapView::drawFloor(short floor, const Position& cameraPosition, const TilePtr& crosshairTile)
{
    if (floor < 0 || floor > Otc::MAX_Z)
        return;

    auto& tiles = m_cachedVisibleTiles[floor];
    size_t lightFloorStart = m_lightView ? m_lightView->size() : 0;

    // light
    if (m_lightView) {
        for (auto& tile : tiles) {
            Point tileDrawPos = transformPositionTo2D(tile->getPosition(), cameraPosition);
            ItemPtr ground = tile->getGround();
            if (ground && ground->isGround() && !ground->isTranslucent()) {
                m_lightView->setFieldBrightness(tileDrawPos, lightFloorStart, 0);
            }
        }
    }

    if (g_game.getFeature(Otc::GameMapDrawGroundFirst)) {
        // ground
        for (auto& tile : tiles) {
            Point tileDrawPos = transformPositionTo2D(tile->getPosition(), cameraPosition);
            tile->drawGround(tileDrawPos, m_lightView.get());
        }

        drawCloudShadows(floor, cameraPosition);

        // bottom, creatures, top
        for (auto& tile : tiles) {
            Point tileDrawPos = transformPositionTo2D(tile->getPosition(), cameraPosition);

            tile->drawBottom(tileDrawPos, m_lightView.get());

            if (m_crosshair && tile == crosshairTile) {
                g_drawQueue->addTexturedRect(Rect(tileDrawPos, tileDrawPos + g_sprites.spriteSize() - 1),
                                             m_crosshair, Rect(0, 0, m_crosshair->getSize()));
            }

            tile->drawCreatures(tileDrawPos, m_lightView.get());
            tile->drawTop(tileDrawPos, m_lightView.get());
        }
    } else {
        // ground first so cloud shadows sit on terrain
        for (auto& tile : tiles) {
            Point tileDrawPos = transformPositionTo2D(tile->getPosition(), cameraPosition);

            if (m_lightView) {
                ItemPtr ground = tile->getGround();
                if (ground && ground->isGround() && !ground->isTranslucent()) {
                    m_lightView->setFieldBrightness(tileDrawPos, lightFloorStart, 0);
                }
            }

            tile->drawGround(tileDrawPos, m_lightView.get());
        }

        drawCloudShadows(floor, cameraPosition);

        for (auto& tile : tiles) {
            Point tileDrawPos = transformPositionTo2D(tile->getPosition(), cameraPosition);

            tile->drawBottom(tileDrawPos, m_lightView.get());

            if (m_crosshair && tile == crosshairTile) {
                g_drawQueue->addTexturedRect(Rect(tileDrawPos, tileDrawPos + g_sprites.spriteSize() - 1),
                                             m_crosshair, Rect(0, 0, m_crosshair->getSize()));
            }

            tile->drawCreatures(tileDrawPos, m_lightView.get());
            tile->drawTop(tileDrawPos, m_lightView.get());
        }
    }

    for (const MissilePtr& missile : g_map.getFloorMissiles(floor)) {
        missile->draw(transformPositionTo2D(missile->getPosition(), cameraPosition), true, m_lightView.get());
    }
}

void MapView::ensureSkyClouds(const Position& cameraPosition)
{
    if (m_skyCloudsReady && m_skyCloudsAnchor.isValid()
        && m_skyCloudsAnchor.z == cameraPosition.z
        && m_skyCloudsAnchor.distance(cameraPosition) < 60) {
        return;
    }

    m_skyClouds.clear();
    m_skyClouds.reserve(10);

    // Deterministic layout so reconnects look similar
    static const float seeds[][6] = {
        { -18.f, -8.f, 6.5f, 3.2f, 0.06f, 0.018f },
        { -6.f,  12.f, 5.0f, 2.6f, 0.05f, 0.022f },
        {  10.f, -14.f, 7.2f, 3.8f, 0.045f, 0.015f },
        {  16.f,  4.f, 4.8f, 2.4f, 0.07f, 0.02f },
        { -22.f,  6.f, 5.6f, 2.9f, 0.04f, 0.025f },
        {  2.f, -22.f, 6.0f, 3.1f, 0.055f, 0.012f },
        {  22.f, -6.f, 5.4f, 2.7f, 0.048f, 0.019f },
        { -12.f, -18.f, 4.4f, 2.2f, 0.062f, 0.016f },
        {  8.f,  18.f, 6.8f, 3.5f, 0.042f, 0.021f },
        { -2.f,  -2.f, 5.2f, 2.8f, 0.058f, 0.014f },
    };

    for (const auto& s : seeds) {
        SkyCloud cloud;
        cloud.x = cameraPosition.x + s[0];
        cloud.y = cameraPosition.y + s[1];
        cloud.radiusX = s[2];
        cloud.radiusY = s[3];
        cloud.vx = s[4];
        cloud.vy = s[5];
        cloud.density = 0.55f + (std::fabs(s[0]) + std::fabs(s[1])) * 0.004f;
        if (cloud.density > 0.9f)
            cloud.density = 0.9f;
        m_skyClouds.push_back(cloud);
    }

    m_skyCloudsReady = true;
    m_skyCloudsAnchor = cameraPosition;
    m_skyCloudsLastSeconds = g_clock.seconds();
}

void MapView::updateSkyClouds(const Position& cameraPosition)
{
    ensureSkyClouds(cameraPosition);

    const float now = g_clock.seconds();
    float dt = now - m_skyCloudsLastSeconds;
    m_skyCloudsLastSeconds = now;
    if (dt < 0.f)
        dt = 0.f;
    if (dt > 0.1f)
        dt = 0.1f;

    const float wrap = 36.f;
    for (SkyCloud& cloud : m_skyClouds) {
        cloud.x += cloud.vx * dt;
        cloud.y += cloud.vy * dt;

        float dx = cloud.x - cameraPosition.x;
        float dy = cloud.y - cameraPosition.y;
        if (dx > wrap) cloud.x -= wrap * 2.f;
        else if (dx < -wrap) cloud.x += wrap * 2.f;
        if (dy > wrap) cloud.y -= wrap * 2.f;
        else if (dy < -wrap) cloud.y += wrap * 2.f;
    }
}

float MapView::sampleCloudShadow(float tileX, float tileY) const
{
    float sum = 0.f;
    for (const SkyCloud& cloud : m_skyClouds) {
        const float nx = (tileX - cloud.x) / cloud.radiusX;
        const float ny = (tileY - cloud.y) / cloud.radiusY;
        const float d2 = nx * nx + ny * ny;
        if (d2 >= 1.f)
            continue;
        float falloff = 1.f - d2;
        falloff *= falloff;
        sum += falloff * cloud.density;
    }
    return std::min(1.f, sum);
}

bool MapView::canReceiveCloudShadow(const Position& pos) const
{
    // Outdoor top surfaces only: roofs (andar de cima) and open ground below.
    // Tiles under a full floor above are covered and skip the shadow.
    if (g_map.isCovered(pos, 0))
        return false;

    const TilePtr& tile = g_map.getTile(pos);
    return tile && tile->getGround();
}

void MapView::drawCloudShadows(short floor, const Position& cameraPosition)
{
    if (!m_drawSkyClouds || !g_game.getFeature(Otc::GameDrawSkyClouds))
        return;
    if (cameraPosition.z > Otc::SEA_FLOOR || floor > Otc::SEA_FLOOR)
        return;

    updateSkyClouds(cameraPosition);

    const int sprSize = g_sprites.spriteSize();
    for (const TilePtr& tile : m_cachedVisibleTiles[floor]) {
        const Position& pos = tile->getPosition();
        if (!canReceiveCloudShadow(pos))
            continue;

        const float intensity = sampleCloudShadow(pos.x + 0.5f, pos.y + 0.5f);
        if (intensity < 0.04f)
            continue;

        // Stronger on upper floors (roofs), softer on the ground below.
        const float floorBoost = (floor < cameraPosition.z) ? 1.15f : 0.9f;
        const int alpha = std::min(110, static_cast<int>(intensity * floorBoost * 95.f));
        if (alpha < 4)
            continue;

        const Point tileDrawPos = transformPositionTo2D(pos, cameraPosition);
        g_drawQueue->addFilledRect(Rect(tileDrawPos, Size(sprSize, sprSize)), Color(20, 24, 36, alpha));
    }
}

void MapView::drawSkyCloudBodies(const Position& cameraPosition)
{
    if (!m_drawSkyClouds || !g_game.getFeature(Otc::GameDrawSkyClouds))
        return;
    if (cameraPosition.z > Otc::SEA_FLOOR)
        return;

    updateSkyClouds(cameraPosition);

    const int sprSize = g_sprites.spriteSize();
    // Draw as if clouds sit one floor above the camera (isometric lift).
    const int cloudZ = std::max(0, cameraPosition.z - 1);
    const float dz = static_cast<float>(cameraPosition.z - cloudZ);

    for (const SkyCloud& cloud : m_skyClouds) {
        const float sx = (m_virtualCenterOffset.x + (cloud.x - cameraPosition.x) - dz) * sprSize;
        const float sy = (m_virtualCenterOffset.y + (cloud.y - cameraPosition.y) - dz) * sprSize;

        for (int layer = 3; layer >= 1; --layer) {
            const float t = layer / 3.0f;
            const int w = std::max(sprSize, static_cast<int>(cloud.radiusX * sprSize * 2.f * t));
            const int h = std::max(sprSize / 2, static_cast<int>(cloud.radiusY * sprSize * 2.f * t * 0.62f));
            const int alpha = std::min(120, static_cast<int>(cloud.density * 70.f * (1.15f - t * 0.45f)));
            if (alpha < 3)
                continue;

            const Rect rect(Point(static_cast<int>(sx) - w / 2, static_cast<int>(sy) - h / 2), Size(w, h));
            g_drawQueue->addFilledRect(rect, Color(236, 242, 250, alpha));
        }
    }
}


void MapView::drawMapForeground(const Rect& rect)
{
    // this could happen if the player position is not known yet
    Position cameraPosition = getCameraPosition();
    if (!cameraPosition.isValid())
        return;

    Rect srcRect = calcFramebufferSource(rect.size());
    Point drawOffset = srcRect.topLeft();
    float horizontalStretchFactor = rect.width() / (float)srcRect.width();
    float verticalStretchFactor = rect.height() / (float)srcRect.height();

    // creatures
    std::vector<std::pair<CreaturePtr, Point>> creatures;
    for (const CreaturePtr& creature : g_map.getSpectatorsInRangeEx(cameraPosition, false, m_visibleDimension.width() / 2, m_visibleDimension.width() / 2 + 1, m_visibleDimension.height() / 2, m_visibleDimension.height() / 2 + 1)) {
        if (!creature->canBeSeen())
            continue;

        PointF jumpOffset = creature->getJumpOffset();
        Point creatureOffset = Point(16 * g_sprites.getOffsetFactor() - creature->getDisplacementX(), -creature->getDisplacementY() - 2 * g_sprites.getOffsetFactor());
        Position pos = creature->getPrewalkingPosition();
        Point p = transformPositionTo2D(pos, cameraPosition) - drawOffset;
        p += (creature->getDrawOffset() + creatureOffset) - Point(jumpOffset.x, jumpOffset.y);
        p.x = p.x * horizontalStretchFactor;
        p.y = p.y * verticalStretchFactor;
        p += rect.topLeft();
        creatures.push_back(std::make_pair(creature, p));
    }

    for (auto& c : creatures) {
        int flags = Otc::DrawIcons;
        if (m_drawNames) { flags |= Otc::DrawNames; }
        if ((!c.first->isLocalPlayer() || m_drawPlayerBars) && !m_drawHealthBarsOnTop) {
            if (m_drawHealthBars) { flags |= Otc::DrawBars; }
            if (m_drawManaBar) { flags |= Otc::DrawManaBar; }
        }
        c.first->drawInformation(c.second, g_map.isCovered(c.first->getPrewalkingPosition(), m_cachedFirstVisibleFloor), rect, flags);
    }

    if (m_lightView) {
        g_drawQueue->add(m_lightView.release());
    }

    // texts
    int limit = g_adaptiveRenderer.textsLimit();
    for (int i = 0; i < 2; ++i) {
        for (const StaticTextPtr& staticText : g_map.getStaticTexts()) {
            Position pos = staticText->getPosition();

            if (pos.z != cameraPosition.z && staticText->getMessageMode() == Otc::MessageNone)
                continue;
            if ((staticText->getMessageMode() != Otc::MessageSay && staticText->getMessageMode() != Otc::MessageYell)) {
                if (i == 0)
                    continue;
            } else if (i == 1)
                continue;

            Point p = transformPositionTo2D(pos, cameraPosition) - drawOffset + Point(8, 0) * g_sprites.getOffsetFactor();
            p.x *= horizontalStretchFactor;
            p.y *= verticalStretchFactor;
            p += rect.topLeft();
            staticText->drawText(p, rect);
            if (--limit == 0)
                break;
        }
    }

    limit = g_adaptiveRenderer.textsLimit();
    for (const AnimatedTextPtr& animatedText : g_map.getAnimatedTexts()) {
        Position pos = animatedText->getPosition();

        if (pos.z != cameraPosition.z)
            continue;

        Point p = transformPositionTo2D(pos, cameraPosition) - drawOffset + Point(16, 8) * g_sprites.getOffsetFactor();
        p.x *= horizontalStretchFactor;
        p.y *= verticalStretchFactor;
        p += rect.topLeft();
        animatedText->drawText(p, rect);
        if (--limit == 0)
            break;
    }

    // tile texts
    drawTileTexts(rect, srcRect);

    // bars on top
    if (m_drawHealthBarsOnTop) {
        for (auto& c : creatures) {
            int flags = 0;
            if ((!c.first->isLocalPlayer() || m_drawPlayerBars)) {
                if (m_drawHealthBars) { flags |= Otc::DrawBars; }
                if (m_drawManaBar) { flags |= Otc::DrawManaBar; }
            }
            c.first->drawInformation(c.second, g_map.isCovered(c.first->getPrewalkingPosition(), m_cachedFirstVisibleFloor), rect, flags);
        }
    }
	
	drawTileWidget(rect, srcRect);
}


void MapView::updateVisibleTilesCache()
{
    int prevFirstVisibleFloor = m_cachedFirstVisibleFloor;
    m_cachedFirstVisibleFloor = calcFirstVisibleFloor(false);
    m_cachedFirstFadingFloor = calcFirstVisibleFloor(true);
    m_cachedLastVisibleFloor = calcLastVisibleFloor();

    VALIDATE(m_cachedFirstVisibleFloor >= 0 && m_cachedLastVisibleFloor >= 0 &&
            m_cachedFirstVisibleFloor <= Otc::MAX_Z && m_cachedLastVisibleFloor <= Otc::MAX_Z);

    if(m_cachedLastVisibleFloor < m_cachedFirstVisibleFloor)
        m_cachedLastVisibleFloor = m_cachedFirstVisibleFloor;

    m_mustUpdateVisibleTilesCache = false;

    // there is no tile to render on invalid positions
    Position cameraPosition = getCameraPosition();
    if (!cameraPosition.isValid()) {
        return;
    }

    // fading
    if (!m_lastCameraPosition.isValid() || m_lastCameraPosition.z != cameraPosition.z || m_lastCameraPosition.distance(cameraPosition) >= 3) { 
        for (int iz = m_cachedLastVisibleFloor; iz >= m_cachedFirstFadingFloor; --iz) {
            m_fadingFloorTimers[iz].restart(m_floorFading * 1000);
        }
    } else if (prevFirstVisibleFloor < m_cachedFirstVisibleFloor) { // showing new floor
        for (int iz = prevFirstVisibleFloor; iz < m_cachedFirstVisibleFloor; ++iz) {
            int shift = std::max<int>(0, m_floorFading - m_fadingFloorTimers[iz].elapsed_millis());
            m_fadingFloorTimers[iz].restart(shift * 1000);
        }
    } else if (prevFirstVisibleFloor > m_cachedFirstVisibleFloor) { // hiding floor
        for (int iz = m_cachedFirstVisibleFloor; iz < prevFirstVisibleFloor; ++iz) {
            int shift = std::max<int>(0, m_floorFading - m_fadingFloorTimers[iz].elapsed_millis());
            m_fadingFloorTimers[iz].restart(shift * 1000);
        }
    }

    m_lastCameraPosition = cameraPosition;

    const int numDiagonals = m_drawDimension.width() + m_drawDimension.height() - 1;
    for (auto& cachedVisibleTiles : m_cachedVisibleTiles) {
        cachedVisibleTiles.clear();
    }

    // draw from last floor (the lower) to first floor (the higher)
    for(int iz = m_cachedLastVisibleFloor; iz >= (m_floorFading ? m_cachedFirstFadingFloor : m_cachedFirstVisibleFloor); --iz) {
        for (int diagonal = 0; diagonal < numDiagonals; ++diagonal) {
            // loop current diagonal tiles
            int advance = std::max<int>(diagonal - m_drawDimension.height(), 0);
            for (int iy = diagonal - advance, ix = advance; iy >= 0 && ix < m_drawDimension.width(); --iy, ++ix) {
                // position on current floor
                //TODO: check position limits
                Position tilePos = cameraPosition.translated(ix - m_virtualCenterOffset.x, iy - m_virtualCenterOffset.y);
                // adjust tilePos to the wanted floor
                tilePos.coveredUp(cameraPosition.z - iz);
                if (const TilePtr& tile = g_map.getTile(tilePos)) {
                    if (!tile->isDrawable())
                        continue;
                    m_cachedVisibleTiles[tilePos.z].push_back(tile);
                    tile->calculateCorpseCorrection();
                }
            }
        }
    }
}

void MapView::updateGeometry(const Size& visibleDimension, const Size& optimizedSize)
{
    m_multifloor = true;
    m_visibleDimension = visibleDimension;
    m_drawDimension = visibleDimension + Size(3, 3);
    m_virtualCenterOffset = (m_drawDimension / 2 - Size(1, 1)).toPoint();
    m_visibleCenterOffset = m_virtualCenterOffset;
    m_optimizedSize = m_drawDimension * g_sprites.spriteSize();
    requestVisibleTilesCacheUpdate();
}

void MapView::onTileUpdate(const Position& pos)
{
    requestVisibleTilesCacheUpdate();
}

void MapView::onMapCenterChange(const Position& pos)
{
    requestVisibleTilesCacheUpdate();
}

void MapView::lockFirstVisibleFloor(int firstVisibleFloor)
{
    m_lockedFirstVisibleFloor = firstVisibleFloor;
    requestVisibleTilesCacheUpdate();
}

void MapView::unlockFirstVisibleFloor()
{
    m_lockedFirstVisibleFloor = -1;
    requestVisibleTilesCacheUpdate();
}

void MapView::setVisibleDimension(const Size& visibleDimension)
{
    //if(visibleDimension == m_visibleDimension)
    //    return;

    if(visibleDimension.width() % 2 != 1 || visibleDimension.height() % 2 != 1) {
        g_logger.traceError("visible dimension must be odd");
        return;
    }

    if(visibleDimension < Size(3,3)) {
        g_logger.traceError("reach max zoom in");
        return;
    }

    updateGeometry(visibleDimension, m_optimizedSize);
}

void MapView::optimizeForSize(const Size& visibleSize)
{
    updateGeometry(m_visibleDimension, visibleSize);
}

void MapView::followCreature(const CreaturePtr& creature)
{
    m_follow = true;
    m_followingCreature = creature;
    requestVisibleTilesCacheUpdate();
}

void MapView::setCameraPosition(const Position& pos)
{
    m_follow = false;
    m_customCameraPosition = pos;
    requestVisibleTilesCacheUpdate();
}

Position MapView::getPosition(const Point& point, const Size& mapSize)
{
    Position cameraPosition = getCameraPosition();

    // if we have no camera, its impossible to get the tile
    if(!cameraPosition.isValid())
        return Position();

    Rect srcRect = calcFramebufferSource(mapSize);
    float sh = srcRect.width() / (float)mapSize.width();
    float sv = srcRect.height() / (float)mapSize.height();

    Point framebufferPos = Point(point.x * sh, point.y * sv);
    Point realPos = (framebufferPos + srcRect.topLeft());
    Point centerOffset = realPos / g_sprites.spriteSize();

    Point tilePos2D = getVisibleCenterOffset() - m_drawDimension.toPoint() + centerOffset + Point(2,2);
    if(tilePos2D.x + cameraPosition.x < 0 && tilePos2D.y + cameraPosition.y < 0)
        return Position();

    Position position = Position(tilePos2D.x, tilePos2D.y, 0) + cameraPosition;

    if(!position.isValid())
        return Position();

    return position;
}

Point MapView::getPositionOffset(const Point& point, const Size& mapSize)
{
    Position cameraPosition = getCameraPosition();

    // if we have no camera, its impossible to get the tile
    if (!cameraPosition.isValid())
        return Point(0, 0);

    Rect srcRect = calcFramebufferSource(mapSize);
    float sh = srcRect.width() / (float)mapSize.width();
    float sv = srcRect.height() / (float)mapSize.height();

    Point framebufferPos = Point(point.x * sh, point.y * sv);
    Point realPos = (framebufferPos + srcRect.topLeft());
    return Point(realPos.x % g_sprites.spriteSize(), realPos.y % g_sprites.spriteSize());
}

void MapView::move(int x, int y)
{
    m_moveOffset.x += x;
    m_moveOffset.y += y;

    int32_t tmp = m_moveOffset.x / g_sprites.spriteSize();
    bool requestTilesUpdate = false;
    if(tmp != 0) {
        m_customCameraPosition.x += tmp;
        m_moveOffset.x %= g_sprites.spriteSize();
        requestTilesUpdate = true;
    }

    tmp = m_moveOffset.y / g_sprites.spriteSize();
    if(tmp != 0) {
        m_customCameraPosition.y += tmp;
        m_moveOffset.y %= g_sprites.spriteSize();
        requestTilesUpdate = true;
    }

    if(requestTilesUpdate)
        requestVisibleTilesCacheUpdate();
}

Rect MapView::calcFramebufferSource(const Size& destSize, bool inNextFrame)
{
    float scaleFactor = g_sprites.spriteSize()/(float)g_sprites.spriteSize();
    Point drawOffset = ((m_drawDimension - m_visibleDimension - Size(1,1)).toPoint()/2) * g_sprites.spriteSize();
    if(isFollowingCreature())
        drawOffset += m_followingCreature->getWalkOffset(inNextFrame) * scaleFactor;

    Size srcSize = destSize;
    Size srcVisible = m_visibleDimension * g_sprites.spriteSize();
    srcSize.scale(srcVisible, Fw::KeepAspectRatio);
    drawOffset.x += (srcVisible.width() - srcSize.width()) / 2;
    drawOffset.y += (srcVisible.height() - srcSize.height()) / 2;

    return Rect(drawOffset, srcSize);
}

int MapView::calcFirstVisibleFloor(bool forFading)
{
    int z = 7;
    // return forced first visible floor
    if(m_lockedFirstVisibleFloor != -1) {
        z = m_lockedFirstVisibleFloor;
    } else {
        Position cameraPosition = getCameraPosition();

        // this could happens if the player is not known yet
        if(cameraPosition.isValid()) {
            // avoid rendering multifloors in far views
            if(!m_multifloor) {
                z = cameraPosition.z;
            } else {
                // if nothing is limiting the view, the first visible floor is 0
                int firstFloor = 0;

                // limits to underground floors while under sea level
                if(cameraPosition.z > Otc::SEA_FLOOR)
                    firstFloor = std::max<int>(cameraPosition.z - Otc::AWARE_UNDEGROUND_FLOOR_RANGE, (int)Otc::UNDERGROUND_FLOOR);

                // loop in 3x3 tiles around the camera
                for(int ix = -1; ix <= 1 && firstFloor < cameraPosition.z && !forFading; ++ix) {
                    for(int iy = -1; iy <= 1 && firstFloor < cameraPosition.z; ++iy) {
                        Position pos = cameraPosition.translated(ix, iy);

                        // process tiles that we can look through, e.g. windows, doors
                        if((ix == 0 && iy == 0) || ((std::abs(ix) != std::abs(iy)) && g_map.isLookPossible(pos))) {
                            Position upperPos = pos;
                            Position coveredPos = pos;

                            while(coveredPos.coveredUp() && upperPos.up() && upperPos.z >= firstFloor) {
                                // check tiles physically above
                                TilePtr tile = g_map.getTile(upperPos);
                                if(tile && tile->limitsFloorsView(!g_map.isLookPossible(pos))) {
                                    firstFloor = upperPos.z + 1;
                                    break;
                                }

                                // check tiles geometrically above
                                tile = g_map.getTile(coveredPos);
                                if(tile && tile->limitsFloorsView(g_map.isLookPossible(pos))) {
                                    firstFloor = coveredPos.z + 1;
                                    break;
                                }
                            }
                        }
                    }
                }
                z = firstFloor;
            }
        }
    }

    // just ensure the that the floor is in the valid range
    z = stdext::clamp<int>(z, 0, (int)Otc::MAX_Z);
    return z;
}

int MapView::calcLastVisibleFloor()
{
    if(!m_multifloor)
        return calcFirstVisibleFloor();

    int z = 7;

    Position cameraPosition = getCameraPosition();
    // this could happens if the player is not known yet
    if(cameraPosition.isValid()) {
        // view only underground floors when below sea level
        if(cameraPosition.z > Otc::SEA_FLOOR)
            z = cameraPosition.z + Otc::AWARE_UNDEGROUND_FLOOR_RANGE;
        else
            z = Otc::SEA_FLOOR;
    }

    if(m_lockedFirstVisibleFloor != -1)
        z = std::max<int>(m_lockedFirstVisibleFloor, z);

    // just ensure the that the floor is in the valid range
    z = stdext::clamp<int>(z, 0, (int)Otc::MAX_Z);
    return z;
}

Point MapView::transformPositionTo2D(const Position& position, const Position& relativePosition) {
    return Point((m_virtualCenterOffset.x + (position.x - relativePosition.x) - (relativePosition.z - position.z)) * g_sprites.spriteSize(),
        (m_virtualCenterOffset.y + (position.y - relativePosition.y) - (relativePosition.z - position.z)) * g_sprites.spriteSize());
}


Position MapView::getCameraPosition()
{
    if (isFollowingCreature()) {
        return m_followingCreature->getPrewalkingPosition();
    }

    return m_customCameraPosition;
}

void MapView::setDrawLights(bool enable)
{
    m_drawLight = enable;
}

void MapView::setCrosshair(const std::string& file)     
{
    if (file == "")
        m_crosshair = nullptr;
    else
        m_crosshair = g_textures.getTexture(file);
}

/* vim: set ts=4 sw=4 et: */
