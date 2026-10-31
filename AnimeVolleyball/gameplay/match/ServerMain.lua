-- ============================================================
-- ServerMain.lua  |  gameplay/match/
-- Server-side entry point (ServerScript).
-- Initializes all systems, wires RemoteEvents, manages
-- player join/leave, and runs the matchmaking zone logic.
-- ============================================================

local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local GameConstants = require(game.ReplicatedStorage.AnimeVB.shared.constants.GameConstants)
local Remotes       = require(game.ReplicatedStorage.AnimeVB.shared.remotes.RemoteRegistry)
local GachaEngine   = require(script.Parent.Parent.gacha.GachaEngine)
local MatchFSM      = require(script.Parent.Parent.fsm.MatchStateMachine)
local CharFSM       = require(script.Parent.Parent.fsm.CharacterStateMachine)
local BallPhysics   = require(script.Parent.Parent.physics.BallPhysics)
local BotAI         = require(script.Parent.Parent.bot.BotAI)

-- ─────────────────────────────────────────────────────────────
-- WORLD REFERENCES (set these in Studio)
-- ─────────────────────────────────────────────────────────────
local ball        = workspace:WaitForChild("Volleyball")
local matchZone   = workspace:WaitForChild("MatchZone")   -- cylinder part
local courtFolder = workspace:WaitForChild("Court")

-- ─────────────────────────────────────────────────────────────
-- MATCH SLOT TABLE
-- Tracks pending team/position selections
-- ─────────────────────────────────────────────────────────────
local slotTable = {
    A = { Spiker = nil, Setter = nil, Libero = nil },
    B = { Spiker = nil, Setter = nil, Libero = nil },
}

local function slotCount(team)
    local n = 0
    for _, v in pairs(slotTable[team]) do if v then n = n + 1 end end
    return n
end

-- ─────────────────────────────────────────────────────────────
-- ACTIVE MATCH INSTANCE
-- ─────────────────────────────────────────────────────────────
local activeMatch   = nil
local activeBallPhys = nil
local activeBots     = {}

-- ─────────────────────────────────────────────────────────────
-- MATCHMAKING ZONE  – continuous spatial touch check
-- ─────────────────────────────────────────────────────────────
matchZone.Touched:Connect(function(hit)
    local character = hit.Parent
    local player    = Players:GetPlayerFromCharacter(character)
    if not player then return end

    -- Prevent duplicate triggers
    if player:GetAttribute("InMatchSetup") then return end
    player:SetAttribute("InMatchSetup", true)

    -- Lock character movement
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then humanoid.WalkSpeed = 0 end

    -- Show match setup prompt
    Remotes.Events.ShowMatchSetupPrompt:FireClient(player, {
        availableSlots = slotTable,
    })
end)

-- ─────────────────────────────────────────────────────────────
-- JOIN SLOT REQUEST
-- ─────────────────────────────────────────────────────────────
Remotes.Functions.RequestJoinSlot.OnServerInvoke = function(player, payload)
    local team     = payload.team
    local position = payload.position
    local C        = GameConstants.Match

    -- Validate team
    if team ~= "A" and team ~= "B" then
        return { success = false, errorMsg = "Invalid team" }
    end

    -- Validate position
    if not table.find(C.RolesPerTeam, position) then
        return { success = false, errorMsg = "Invalid position" }
    end

    -- Check slot availability
    if slotTable[team][position] ~= nil then
        return { success = false, errorMsg = "Position Filled" }
    end

    -- Check team capacity
    if slotCount(team) >= C.MaxPlayersPerTeam then
        return { success = false, errorMsg = "Team Full" }
    end

    -- Assign slot
    slotTable[team][position] = player.UserId

    -- Broadcast updated slot status to all players in setup
    Remotes.Events.SlotStatusUpdate:FireAllClients({ slotTable = slotTable })

    -- Spawn player on court
    _spawnOnCourt(player, team, position)

    -- Check if match can start
    _checkMatchStart()

    return { success = true }
end

-- ─────────────────────────────────────────────────────────────
-- SPAWN ON COURT
-- ─────────────────────────────────────────────────────────────
function _spawnOnCourt(player, team, position)
    local character = player.Character
    if not character then return end

    local spawnCoord = GameConstants.Court.Spawns[team][position]
    character.HumanoidRootPart.CFrame =
        CFrame.new(spawnCoord.x, spawnCoord.y + 1, spawnCoord.z)

    -- Add to match (if active) or queue
    if activeMatch then
        activeMatch:addPlayer(player, team, position)
    end

    -- Transition client to match HUD
    Remotes.Events.TransitionToMatch:FireClient(player, {
        team       = team,
        position   = position,
        spawnCoord = spawnCoord,
    })

    -- Re-enable movement
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        local styleMult = GameConstants.Styles.Rookie.SpeedMult
        humanoid.WalkSpeed = GameConstants.Physics.WalkSpeedBase * styleMult
    end
end

-- ─────────────────────────────────────────────────────────────
-- AUTO-START MATCH CHECK
-- ─────────────────────────────────────────────────────────────
function _checkMatchStart()
    -- Start when at least 1 human player has joined any slot
    local humanCount = 0
    for _, list in pairs(slotTable) do
        for _, uid in pairs(list) do
            if uid then humanCount = humanCount + 1 end
        end
    end

    if humanCount >= 1 and not activeMatch then
        _startMatch()
    end
end

-- ─────────────────────────────────────────────────────────────
-- MATCH INITIALIZATION
-- ─────────────────────────────────────────────────────────────
function _startMatch()
    -- Create match FSM
    activeMatch   = MatchFSM.new(ball)
    activeBallPhys = BallPhysics.new(ball, activeMatch)
    activeMatch.ball = ball

    -- Register human players into match
    for team, positions in pairs(slotTable) do
        for position, uid in pairs(positions) do
            if uid then
                local player = Players:GetPlayerByUserId(uid)
                if player then
                    activeMatch:addPlayer(player, team, position)

                    -- Register character FSM
                    local char = player.Character
                    if char then
                        local fsm = CharFSM.new(
                            player,
                            char.HumanoidRootPart,
                            char:FindFirstChildOfClass("Humanoid")
                        )
                        activeMatch:registerFSM(player.UserId, fsm)
                    end
                end
            end
        end
    end

    -- Fill empty slots with bots
    _spawnBots()

    -- Begin match
    activeMatch:start()

    print("[ServerMain] Match started!")
end

-- ─────────────────────────────────────────────────────────────
-- BOT SPAWNING
-- ─────────────────────────────────────────────────────────────
function _spawnBots()
    local difficulty = "Medium"  -- configurable per lobby

    for team, positions in pairs(slotTable) do
        for _, role in ipairs(GameConstants.Match.RolesPerTeam) do
            if not positions[role] then
                -- Create NPC model (Studio should have a Bot template)
                local botModel = _createBotModel(team, role)
                local bot      = BotAI.new(
                    botModel, team, role, difficulty, activeMatch, activeBallPhys
                )
                table.insert(activeBots, bot)
                -- Register bot FSM placeholder
                activeMatch.characterFSMs[botModel.Name] = {
                    update = function() end,
                    applyStun = function() end,
                    root = botModel.PrimaryPart,
                    States = { IDLE = "IDLE" },
                    transition = function() end,
                }
            end
        end
    end
end

function _createBotModel(team, role)
    -- Clone from ServerStorage template
    local template = game.ServerStorage:FindFirstChild("BotTemplate")
    if not template then
        -- Minimal fallback
        local model     = Instance.new("Model")
        local rootPart  = Instance.new("Part")
        rootPart.Name   = "HumanoidRootPart"
        rootPart.Size   = Vector3.new(2, 2, 1)
        rootPart.Parent = model
        model.PrimaryPart = rootPart
        local h        = Instance.new("Humanoid")
        h.Parent       = model
        model.Name     = team .. "_Bot_" .. role
        model.Parent   = workspace

        local spawnCoord = GameConstants.Court.Spawns[team][role]
        rootPart.CFrame = CFrame.new(spawnCoord.x, spawnCoord.y + 1, spawnCoord.z)
        return model
    end

    local bot   = template:Clone()
    bot.Name    = team .. "_Bot_" .. role
    bot.Parent  = workspace
    local spawnCoord = GameConstants.Court.Spawns[team][role]
    bot:SetPrimaryPartCFrame(
        CFrame.new(spawnCoord.x, spawnCoord.y + 1, spawnCoord.z)
    )
    return bot
end

-- ─────────────────────────────────────────────────────────────
-- PLAYER INPUT HANDLER (server receives minimal signal)
-- ─────────────────────────────────────────────────────────────
Remotes.Events.PlayerInput.OnServerEvent:Connect(function(player, payload)
    if not activeMatch then return end

    local fsm        = activeMatch.characterFSMs[player.UserId]
    if not fsm then return end

    -- Block all input if character is in locked state
    if fsm.canInput == false then return end

    local actionType  = payload.actionType
    local dirModifier = payload.dirModifier  -- "W"/"A"/"S"/"D" or nil
    local timestamp   = payload.timestamp

    local character = player.Character
    if not character then return end
    local root       = character.HumanoidRootPart
    local team       = activeMatch:_getPlayerTeam(player)

    -- ── JUMP
    if actionType == "Jump" then
        fsm:executeJump()

    -- ── BUMP (left click, touch 1)
    elseif actionType == "Bump" then
        if not fsm:isInputBlocked() then
            -- Check hand hitbox contact at animation contact frame
            local handPos = character:FindFirstChild("RightHand") and
                            character.RightHand.Position or root.Position + Vector3.new(0,1,1)

            task.delay(GameConstants.AnimMarkers.Bump.ContactFrame, function()
                if activeBallPhys:isInsideHandHitbox(handPos, 1.5) then
                    if activeMatch:registerTouch(player, "Bump", ball.Velocity) then
                        activeBallPhys:executeBump(root, "Common")
                        -- Add energy
                        local energyGain = GameConstants.Ability.GainPerBump
                        Remotes.Events.EnergyUpdate:FireClient(player,
                            { playerID = player.UserId, newEnergy = energyGain })
                    end
                else
                    fsm:applyStun()
                end
            end)

            -- Play bump animation on all clients
            Remotes.Events.PlayAnimation:FireAllClients({
                playerID          = player.UserId,
                animationName     = "Bump",
                contactFrameTime  = GameConstants.AnimMarkers.Bump.ContactFrame,
            })
        end

    -- ── SET (Q or E, touch 2)
    elseif actionType == "Set" then
        if not fsm:isInputBlocked() then
            local moveDir = payload.moveDirection or Vector3.zero

            task.delay(GameConstants.AnimMarkers.Set.ContactFrame, function()
                local handPos = character:FindFirstChild("RightHand") and
                    character.RightHand.Position or root.Position + Vector3.new(0,2,0)

                if activeBallPhys:isInsideHandHitbox(handPos, 1.8) then
                    if activeMatch:registerTouch(player, "Set", ball.Velocity) then
                        activeBallPhys:executeSet(moveDir, "Common")
                    end
                else
                    fsm:applyStun()
                end
            end)

            Remotes.Events.PlayAnimation:FireAllClients({
                playerID         = player.UserId,
                animationName    = "Set",
                contactFrameTime = GameConstants.AnimMarkers.Set.ContactFrame,
            })
        end

    -- ── SPIKE (left click while airborne, touch 3)
    elseif actionType == "Spike" then
        if fsm:isAirborne() and not fsm:isInputBlocked() then

            -- Net overreach check
            if activeBallPhys:checkNetOverreach(root, team) then
                Remotes.Events.FoulTriggered:FireAllClients({
                    foulType        = "NetOverreachFoul",
                    offendingPlayer = player.UserId,
                    pointAwardedTo  = team == "A" and "B" or "A",
                })
                activeMatch:_awardPoint(team == "A" and "B" or "A", "NetOverreachFoul")
                return
            end

            local lookVector = payload.lookVector or Vector3.new(0, -1, 1).Unit
            local stylePower = (fsm.style and fsm.style.SpikeMult or 1.0)

            task.delay(GameConstants.AnimMarkers.Spike.ContactFrame, function()
                local handPos = character:FindFirstChild("RightHand") and
                    character.RightHand.Position or root.Position + Vector3.new(0,2,1)

                if activeBallPhys:isInsideHandHitbox(handPos, 1.4) then
                    if activeMatch:registerTouch(player, "Spike", ball.Velocity) then
                        activeBallPhys:executeSpike(
                            lookVector, stylePower, dirModifier,
                            fsm.style and fsm.style.rarity or "Common"
                        )
                        -- Screen shake + flash on spike
                        Remotes.Events.ScreenShake:FireAllClients({
                            magnitude = GameConstants.Camera.ShakeMagnitude,
                            frequency = GameConstants.Camera.ShakeFreq,
                            decay     = GameConstants.Camera.ShakeDecay,
                        })
                    end
                else
                    fsm:applyStun()
                end
            end)

            Remotes.Events.PlayAnimation:FireAllClients({
                playerID         = player.UserId,
                animationName    = "Spike",
                contactFrameTime = GameConstants.AnimMarkers.Spike.ContactFrame,
            })
        end

    -- ── DIVE
    elseif actionType == "Dive" then
        if fsm:executeDive() then
            Remotes.Events.PlayAnimation:FireAllClients({
                playerID         = player.UserId,
                animationName    = "Dive",
                contactFrameTime = GameConstants.AnimMarkers.Dive.ContactFrame,
            })
        end
    end
end)

-- ─────────────────────────────────────────────────────────────
-- ABILITY REQUEST
-- ─────────────────────────────────────────────────────────────
Remotes.Functions.RequestAbility.OnServerInvoke = function(player)
    if not activeMatch then return { success = false } end
    -- Ability energy check handled by energy tracker module (extend here)
    return { success = true }
end

-- ─────────────────────────────────────────────────────────────
-- PLAYER JOIN / LEAVE
-- ─────────────────────────────────────────────────────────────
Players.PlayerAdded:Connect(function(player)
    GachaEngine.loadProfile(player)

    player.CharacterAdded:Connect(function(character)
        -- Configure humanoid walk speed on spawn
        local humanoid = character:WaitForChild("Humanoid")
        humanoid.WalkSpeed = GameConstants.Physics.WalkSpeedBase
    end)
end)

Players.PlayerRemoving:Connect(function(player)
    -- Flush touch cache if in active match
    if activeMatch then
        activeMatch:onPlayerDisconnect(player)
    end

    -- Persist profile
    GachaEngine.saveProfile(player)

    -- Clear match setup flag
    player:SetAttribute("InMatchSetup", nil)

    -- Free slot
    for team, positions in pairs(slotTable) do
        for pos, uid in pairs(positions) do
            if uid == player.UserId then
                slotTable[team][pos] = nil
            end
        end
    end
end)

-- ─────────────────────────────────────────────────────────────
-- MATCH END → LOBBY TRANSITION
-- ─────────────────────────────────────────────────────────────
Remotes.Events.MatchWon.OnServerEvent = nil  -- MatchWon is server → client only
-- Instead, listen via MatchFSM callback:
-- When MatchFSM calls _checkMatchWin() and fires MatchWon,
-- the reward routine runs, then we teleport everyone back.

game:GetService("MessagingService")  -- placeholder for cross-server if needed

print("[ServerMain] Anime Volleyball Server initialized.")
