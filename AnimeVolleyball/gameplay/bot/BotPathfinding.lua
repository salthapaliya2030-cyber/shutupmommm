-- ============================================================
-- BotPathfinding.lua  |  gameplay/bot/
-- Server-side bot movement and spatial routing utilities.
-- Handles: floor shadow tracking, exclusive target lock,
-- cover zone routing, wall avoidance, and court clamping.
-- Imported by BotAI.lua; does NOT run independently.
-- ============================================================

local GameConstants = require(game.ReplicatedStorage.AnimeVB.shared.constants.GameConstants)

local BotPathfinding = {}

-- ─────────────────────────────────────────────────────────────
-- FLOOR SHADOW INTERCEPT POINT
-- Returns the predicted X,Z ground position under the ball
-- accounting for simple parabolic arc prediction.
-- ─────────────────────────────────────────────────────────────
function BotPathfinding.predictLandingXZ(ballPosition, ballVelocity)
    -- Simple kinematic solve: time to floor from current height
    local y0  = ballPosition.Y
    local vy0 = ballVelocity.Y
    local g   = GameConstants.Physics.Gravity  -- negative

    if y0 <= GameConstants.Court.FloorY + GameConstants.Physics.BallRadius then
        return ballPosition.X, ballPosition.Z, 0
    end

    -- Quadratic: y0 + vy0*t + 0.5*g*t^2 = FloorY
    -- 0.5*g*t^2 + vy0*t + (y0 - FloorY) = 0
    local a = 0.5 * g
    local b = vy0
    local c = y0 - GameConstants.Court.FloorY

    local discriminant = b * b - 4 * a * c
    if discriminant < 0 then
        -- Ball is not going to reach the floor (shouldn't happen in normal play)
        return ballPosition.X, ballPosition.Z, 0
    end

    local sqrtD = math.sqrt(discriminant)
    local t1    = (-b - sqrtD) / (2 * a)
    local t2    = (-b + sqrtD) / (2 * a)

    -- Take the positive root (future time)
    local t = math.max(t1, t2)
    if t < 0 then t = math.max(0, math.min(t1, t2)) end

    local landX = ballPosition.X + ballVelocity.X * t
    local landZ = ballPosition.Z + ballVelocity.Z * t

    -- Clamp to court boundary with padding
    local C = GameConstants.Court
    landX = math.clamp(landX, -C.HalfWidth,  C.HalfWidth)
    landZ = math.clamp(landZ, -C.HalfLength, C.HalfLength)

    return landX, landZ, t
end

-- ─────────────────────────────────────────────────────────────
-- SHORTEST PATH DISTANCE  (flat XZ plane, ignoring Y)
-- ─────────────────────────────────────────────────────────────
function BotPathfinding.flatDistance(posA, posB)
    local dx = posA.X - posB.X
    local dz = posA.Z - posB.Z
    return math.sqrt(dx * dx + dz * dz)
end

-- ─────────────────────────────────────────────────────────────
-- EXCLUSIVE TARGET ASSIGNMENT LOCK
-- Iterates bot list; assigns the closest bot as primary receiver.
-- All others routed to distinct cover zones.
-- ─────────────────────────────────────────────────────────────
function BotPathfinding.assignTargets(botList, ballShadowX, ballShadowZ)
    local shadowPos = Vector3.new(ballShadowX, GameConstants.Court.FloorY, ballShadowZ)

    -- Find closest bot
    local bestBot  = nil
    local bestDist = math.huge

    for _, bot in ipairs(botList) do
        if bot.root and bot.root.Parent then
            local d = BotPathfinding.flatDistance(bot.root.Position, shadowPos)
            if d < bestDist then
                bestDist = d
                bestBot  = bot
            end
        end
    end

    -- Generate distinct cover zones for secondary bots
    local coverZones = BotPathfinding.generateCoverZones(shadowPos, botList)
    local coverIdx   = 1

    for _, bot in ipairs(botList) do
        if bot == bestBot then
            bot.isPrimaryReceiver = true
            bot.targetZone        = shadowPos
        else
            bot.isPrimaryReceiver = false
            bot.targetZone        = coverZones[coverIdx] or shadowPos
            coverIdx              = coverIdx + 1
        end

        -- Hard-reset pathfinding latency timer to break current loop
        bot.pathLatencyTimer  = 0
        bot.decisionPending   = false
    end

    return bestBot
end

-- ─────────────────────────────────────────────────────────────
-- COVER ZONE GENERATOR
-- Returns distinct defensive positions spread across the court
-- ─────────────────────────────────────────────────────────────
function BotPathfinding.generateCoverZones(ballShadowPos, botList)
    local C     = GameConstants.Court
    local zones = {}

    -- Spread offsets relative to ball shadow (defensive triangle)
    local offsets = {
        Vector3.new(-3.0, 0,  1.5),
        Vector3.new( 3.0, 0,  1.5),
        Vector3.new( 0.0, 0, -3.0),
        Vector3.new(-3.0, 0, -1.5),
        Vector3.new( 3.0, 0, -1.5),
    }

    for _, offset in ipairs(offsets) do
        local zone = Vector3.new(
            math.clamp(ballShadowPos.X + offset.X, -C.HalfWidth  + 0.5, C.HalfWidth  - 0.5),
            C.FloorY,
            math.clamp(ballShadowPos.Z + offset.Z, -C.HalfLength + 0.5, C.HalfLength - 0.5)
        )
        table.insert(zones, zone)
    end

    return zones
end

-- ─────────────────────────────────────────────────────────────
-- WALL AVOIDANCE
-- Returns a corrected target position pushed away from walls
-- ─────────────────────────────────────────────────────────────
function BotPathfinding.avoidWalls(targetPos, margin)
    margin = margin or 1.0
    local C = GameConstants.Court
    return Vector3.new(
        math.clamp(targetPos.X, -C.HalfWidth  + margin, C.HalfWidth  - margin),
        targetPos.Y,
        math.clamp(targetPos.Z, -C.HalfLength + margin, C.HalfLength - margin)
    )
end

-- ─────────────────────────────────────────────────────────────
-- ATTACK ANGLE CALCULATION
-- Given a bot's position and team, returns the spike look-vector
-- aimed at the weakest defensive zone on the opponent side.
-- (Used by Medium/Godly bots for WASD directional modifier choice)
-- ─────────────────────────────────────────────────────────────
function BotPathfinding.chooseAttackAngle(botPosition, team, opponentPositions)
    -- Build a heat map: divide opponent court into 4 quadrants
    -- Count defenders per quadrant; spike toward emptiest

    local C        = GameConstants.Court
    local quadrantCounts = { LL = 0, LR = 0, RL = 0, RR = 0 }

    for _, pos in ipairs(opponentPositions) do
        local isLeft  = pos.X < 0
        local isFront = math.abs(pos.Z) < C.HalfLength / 2
        local key = (isLeft and "L" or "R") .. (isFront and "L" or "R")
        if quadrantCounts[key] then
            quadrantCounts[key] = quadrantCounts[key] + 1
        end
    end

    -- Find emptiest quadrant
    local minCount = math.huge
    local bestKey  = "RL"
    for key, count in pairs(quadrantCounts) do
        if count < minCount then
            minCount = count
            bestKey  = key
        end
    end

    -- Map quadrant to WASD modifier
    local dirMap = {
        LL = "A",  -- left front
        LR = "A",  -- left back → use A + S combo; return A as primary
        RL = "D",  -- right front
        RR = "D",  -- right back
    }

    return dirMap[bestKey] or nil
end

-- ─────────────────────────────────────────────────────────────
-- IN-BOUNDS CHECK  (for bot target validation)
-- ─────────────────────────────────────────────────────────────
function BotPathfinding.isInBounds(pos)
    local C = GameConstants.Court
    return math.abs(pos.X) <= C.HalfWidth and
           math.abs(pos.Z) <= C.HalfLength
end

-- ─────────────────────────────────────────────────────────────
-- TEAM SIDE CHECK  (ball on this bot's side of the net?)
-- ─────────────────────────────────────────────────────────────
function BotPathfinding.isBallOnBotSide(ballZ, botTeam)
    if botTeam == "A" then return ballZ <= 0 end
    return ballZ >= 0
end

return BotPathfinding
