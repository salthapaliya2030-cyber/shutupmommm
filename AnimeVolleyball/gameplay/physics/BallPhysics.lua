-- ============================================================
-- BallPhysics.lua  |  gameplay/physics/
-- Server-authoritative ball physics engine.
-- Handles: serve toss, bump, set, spike, net plane intersection,
-- boundary wall surface-normal reflection, net rolling dampener,
-- and ball-to-player hitbox contact detection.
-- ============================================================

local RunService    = game:GetService("RunService")
local GameConstants = require(game.ReplicatedStorage.AnimeVB.shared.constants.GameConstants)
local Remotes       = require(game.ReplicatedStorage.AnimeVB.shared.remotes.RemoteRegistry)

local BallPhysics = {}
BallPhysics.__index = BallPhysics

-- ─────────────────────────────────────────────────────────────
-- CONSTRUCTION
-- ─────────────────────────────────────────────────────────────
function BallPhysics.new(ballPart, matchFSM)
    local self = setmetatable({}, BallPhysics)

    self.ball     = ballPart
    self.matchFSM = matchFSM

    -- Network ownership: server owns the ball
    ballPart:SetNetworkOwner(nil)

    -- Last known ball side (A = negative Z, B = positive Z)
    self.ballSide = "A"

    -- Active serve toss state
    self.serveToss = { active = false, velocity = Vector3.zero }

    -- Floor shadow update connection
    self._shadowConn = nil
    self:_startShadowLoop()

    return self
end

-- ─────────────────────────────────────────────────────────────
-- SERVE TOSS  (server welds ball to hand, then tosses vertically)
-- ─────────────────────────────────────────────────────────────
function BallPhysics:attachToHand(handJoint)
    -- Weld ball to server's hand joint to prevent premature drop
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = handJoint
    weld.Part1 = self.ball
    weld.Name  = "ServeTossWeld"
    weld.Parent = self.ball
    self._serveTossWeld = weld
end

function BallPhysics:releaseToss()
    if self._serveTossWeld then
        self._serveTossWeld:Destroy()
        self._serveTossWeld = nil
    end
    -- Apply pure vertical launch
    self.ball.Velocity = Vector3.new(0, GameConstants.Physics.ServeTossVelocity, 0)
end

function BallPhysics:executeServe(lookVector, power, dirModifier)
    -- power: 0–1 from timing window
    local clampedPower = math.clamp(
        power,
        GameConstants.Physics.ServePowerMin,
        GameConstants.Physics.ServePowerMax
    )

    local baseMag = 45 * clampedPower
    local vel = lookVector * baseMag
    vel = self:_applyWASDModifier(vel, dirModifier)

    self.ball.Velocity = vel

    Remotes.Events.SpawnEffect:FireAllClients({
        effectType    = "Serve",
        worldPosition = self.ball.Position,
        styleRarity   = "Common",
    })
end

-- ─────────────────────────────────────────────────────────────
-- BUMP  (touch 1 – strips incoming momentum, launches high arc)
-- ─────────────────────────────────────────────────────────────
function BallPhysics:executeBump(playerRoot, styleRarity)
    local C = GameConstants.Physics
    local incoming = self.ball.Velocity

    -- Kill incoming horizontal momentum
    local stripped = incoming * C.BumpMomentumKill

    -- Compute new arc vector: high angle toward own-side center
    local angleRad = math.rad(C.BumpLiftAngle)
    local courtCenter = Vector3.new(0, 0, -(playerRoot.Position.Z > 0 and 3 or -3))
    local horizontal  = (courtCenter - playerRoot.Position).Unit * 8

    local newVelocity = Vector3.new(
        horizontal.X,
        math.sin(angleRad) * 22,
        horizontal.Z
    ) + stripped

    self.ball.Velocity = newVelocity

    Remotes.Events.SpawnEffect:FireAllClients({
        effectType    = "Bump",
        worldPosition = self.ball.Position,
        styleRarity   = styleRarity or "Common",
    })
end

-- ─────────────────────────────────────────────────────────────
-- SET  (touch 2 – halts, clean vertical column + directional tilt)
-- ─────────────────────────────────────────────────────────────
function BallPhysics:executeSet(moveDirection, styleRarity)
    local C = GameConstants.Physics

    -- Base: clean vertical column
    local vel = Vector3.new(0, 24, 0)

    -- Directional tilt based on setter's move direction in shiftlock
    if moveDirection and moveDirection.Magnitude > 0.1 then
        local tiltH = moveDirection.Unit * 8
        vel = vel + tiltH
    end

    -- Hard cap on total set velocity magnitude
    if vel.Magnitude > C.SetMaxVelocity then
        vel = vel.Unit * C.SetMaxVelocity
    end

    self.ball.Velocity = vel

    Remotes.Events.SpawnEffect:FireAllClients({
        effectType    = "Set",
        worldPosition = self.ball.Position,
        styleRarity   = styleRarity or "Common",
    })
end

-- ─────────────────────────────────────────────────────────────
-- SPIKE  (touch 3 – camera look-vector × power stats, WASD tilt)
-- ─────────────────────────────────────────────────────────────
function BallPhysics:executeSpike(cameraLookVector, stylePower, dirModifier, styleRarity)
    local spikeBase = cameraLookVector * (60 * stylePower)

    -- Base downward gravity pull
    local vel = Vector3.new(spikeBase.X, spikeBase.Y - 18, spikeBase.Z)

    vel = self:_applyWASDModifier(vel, dirModifier)

    self.ball.Velocity = vel

    -- Broadcast plasma trail effect
    Remotes.Events.SpawnEffect:FireAllClients({
        effectType    = "Spike",
        worldPosition = self.ball.Position,
        styleRarity   = styleRarity or "Common",
    })
end

-- ─────────────────────────────────────────────────────────────
-- WASD DIRECTIONAL MODIFIER
-- ─────────────────────────────────────────────────────────────
function BallPhysics:_applyWASDModifier(vel, dir)
    if not dir then return vel end
    local M = GameConstants.Physics.SpikeModifiers

    if dir == "W" then
        vel = vel + Vector3.new(0, M.W_GravityBoost, 0)
    elseif dir == "S" then
        vel = Vector3.new(vel.X * M.S_HorizBoost, vel.Y * 0.5, vel.Z * M.S_HorizBoost)
    elseif dir == "A" then
        vel = vel + Vector3.new(M.A_LateralForce, 0, 0)
    elseif dir == "D" then
        vel = vel + Vector3.new(M.D_LateralForce, 0, 0)
    end

    return vel
end

-- ─────────────────────────────────────────────────────────────
-- NET PLANE INTERSECTION VALIDATOR
-- Called every Heartbeat frame on the ball
-- ─────────────────────────────────────────────────────────────
function BallPhysics:checkNetPlane(prevPos, currPos)
    local C  = GameConstants.Court
    local ph = GameConstants.Physics
    local prevZ = prevPos.Z
    local currZ = currPos.Z

    -- Did the ball cross Z = 0?
    if (prevZ < 0 and currZ >= 0) or (prevZ > 0 and currZ <= 0) then

        local ballY = currPos.Y

        -- Below net top: ball hit the net structure
        if ballY <= C.NetTopY then
            self:_applyNetRolling()
            return "NetHit"
        else
            -- Clean crossing above net: valid
            self.matchFSM.touchCounter:resetForNetCrossing()
            self.ballSide = currZ > 0 and "B" or "A"
            return "ValidCross"
        end
    end

    return nil
end

-- ─────────────────────────────────────────────────────────────
-- NET ROLLING DAMPENER
-- ─────────────────────────────────────────────────────────────
function BallPhysics:_applyNetRolling()
    local ph  = GameConstants.Physics
    local vel = self.ball.Velocity

    -- Invert horizontal Z component (bounce back)
    local newVel = Vector3.new(
        vel.X * ph.NetFrictionMult,
        vel.Y * ph.NetVertDamp,
        -vel.Z * ph.NetFrictionMult
    )

    self.ball.Velocity = newVel

    -- If nearly stopped, inject absolute drop force to prevent suspension
    if newVel.Magnitude < ph.NetMinVelThresh then
        self.ball.Velocity = Vector3.new(
            newVel.X,
            ph.NetDropForce,
            newVel.Z
        )
    end
end

-- ─────────────────────────────────────────────────────────────
-- NET OVERREACH FOUL CHECK
-- Returns true if hand/root crossed net into opponent territory
-- ─────────────────────────────────────────────────────────────
function BallPhysics:checkNetOverreach(playerRoot, playerTeam)
    local rootZ = playerRoot.Position.Z
    -- Team A is on negative Z, Team B is on positive Z
    if playerTeam == "A" and rootZ > GameConstants.Court.NetPlaneZ then
        return true
    elseif playerTeam == "B" and rootZ < GameConstants.Court.NetPlaneZ then
        return true
    end
    return false
end

-- ─────────────────────────────────────────────────────────────
-- HAND HITBOX CONTACT CHECK
-- Returns true only if ball is inside hand hitbox on contact frame
-- ─────────────────────────────────────────────────────────────
function BallPhysics:isInsideHandHitbox(handPosition, radius)
    radius = radius or 1.2  -- studs
    local dist = (self.ball.Position - handPosition).Magnitude
    return dist <= radius
end

-- ─────────────────────────────────────────────────────────────
-- SURFACE-NORMAL RAYCAST (boundary walls)
-- ─────────────────────────────────────────────────────────────
function BallPhysics:resolveWallBounce(hitNormal)
    local vel = self.ball.Velocity
    -- Reflect: v' = v - 2(v·n)n
    local dot    = vel:Dot(hitNormal)
    local newVel = vel - (hitNormal * (2 * dot))
    -- Apply friction coefficient
    newVel = newVel * 0.6
    self.ball.Velocity = newVel
end

-- ─────────────────────────────────────────────────────────────
-- FLOOR SHADOW LOOP
-- ─────────────────────────────────────────────────────────────
function BallPhysics:_startShadowLoop()
    self._shadowConn = RunService.Heartbeat:Connect(function()
        local pos  = self.ball.Position
        local S    = GameConstants.Shadow

        -- Raycast straight down from ball to floor
        local origin    = pos
        local direction = Vector3.new(0, S.RaycastDown, 0)
        local rayResult = workspace:Raycast(origin, direction,
            RaycastParams.new())  -- exclude ball itself in real impl

        local floorY
        if rayResult then
            floorY = rayResult.Position.Y
        else
            -- Safety backup: use court FloorY to prevent divide-by-zero
            floorY = GameConstants.Court.FloorY
        end

        local altitude = math.max(pos.Y - floorY, 0)

        -- Inverse equation: radius shrinks as ball descends
        local t      = math.clamp(altitude / S.MaxAltitude, 0, 1)
        local radius = S.MinRadius + (S.MaxRadius - S.MinRadius) * t
        local alpha  = S.MaxAlpha - (S.MaxAlpha - S.MinAlpha) * (1 - t)

        Remotes.Events.BallShadowUpdate:FireAllClients({
            x = pos.X, z = pos.Z,
            radius = radius,
            alpha  = alpha,
        })
    end)
end

function BallPhysics:destroy()
    if self._shadowConn then
        self._shadowConn:Disconnect()
    end
end

return BallPhysics
