-- ============================================================
-- GachaEngine.lua  |  gameplay/gacha/
-- Server-side gacha drop table processor.
-- Runs probability weight matrix, enforces Level-Gate Validation
-- Lock, pity system, mutex-protected data store writes.
-- ============================================================

local DataStoreService = game:GetService("DataStoreService")
local GameConstants    = require(game.ReplicatedStorage.AnimeVB.shared.constants.GameConstants)
local Remotes          = require(game.ReplicatedStorage.AnimeVB.shared.remotes.RemoteRegistry)

-- ─────────────────────────────────────────────────────────────
-- DATA STORE
-- ─────────────────────────────────────────────────────────────
local profileStore = DataStoreService:GetDataStore(
    GameConstants.DataStore.ProfileStore
)

-- In-memory profile cache (mutex protected)
local profileCache = {}   -- [userId] = profileData
local mutexLocks   = {}   -- [userId] = boolean (true = locked)

local GachaEngine = {}

-- ─────────────────────────────────────────────────────────────
-- PROFILE LOAD (on player join)
-- ─────────────────────────────────────────────────────────────
function GachaEngine.loadProfile(player)
    local userId = tostring(player.UserId)

    -- Wait if mutex is held (another save in progress)
    local timeout = GameConstants.DataStore.MutexTimeout
    local elapsed = 0
    while mutexLocks[userId] and elapsed < timeout do
        task.wait(0.1)
        elapsed = elapsed + 0.1
    end

    if mutexLocks[userId] then
        -- Mutex timed out – release and warn
        warn("[GachaEngine] Mutex timeout on load for " .. userId)
        mutexLocks[userId] = false
    end

    mutexLocks[userId] = true

    local success, data = pcall(function()
        return profileStore:GetAsync(userId)
    end)

    mutexLocks[userId] = false

    if success and data then
        profileCache[userId] = data
    else
        -- Default profile
        profileCache[userId] = {
            yen          = 1000,
            gems         = 10,
            accountLevel = 1,
            style        = "Rookie",
            inventory    = { "Rookie" },
            spinCount    = 0,        -- for pity tracking
            stats        = { totalSpikes = 0, totalBlocks = 0 },
        }
    end

    GachaEngine.syncCurrencyToClient(player)
    return profileCache[userId]
end

-- ─────────────────────────────────────────────────────────────
-- PROFILE SAVE (on player leave or match end)
-- ─────────────────────────────────────────────────────────────
function GachaEngine.saveProfile(player)
    local userId  = tostring(player.UserId)
    local profile = profileCache[userId]
    if not profile then return end

    -- Mutex acquire
    while mutexLocks[userId] do task.wait(0.05) end
    mutexLocks[userId] = true

    local success, err = pcall(function()
        profileStore:SetAsync(userId, profile)
    end)

    mutexLocks[userId] = false

    if not success then
        warn("[GachaEngine] Save failed for " .. userId .. ": " .. tostring(err))
    else
        print("[GachaEngine] Profile saved for " .. player.Name)
    end
end

-- ─────────────────────────────────────────────────────────────
-- SPIN REQUEST
-- ─────────────────────────────────────────────────────────────
function GachaEngine.requestSpin(player, currency)
    local userId  = tostring(player.UserId)
    local profile = profileCache[userId]
    if not profile then
        return { success = false, error = "Profile not loaded" }
    end

    local C = GameConstants.Gacha

    -- Check currency
    if currency == "Yen" then
        if profile.yen < C.SpinCostYen then
            return { success = false, error = "Insufficient Yen" }
        end
        profile.yen = profile.yen - C.SpinCostYen
    elseif currency == "Gem" then
        if profile.gems < C.SpinCostGem then
            return { success = false, error = "Insufficient Gems" }
        end
        profile.gems = profile.gems - C.SpinCostGem
    else
        return { success = false, error = "Invalid currency" }
    end

    -- Build effective drop table with Level-Gate Validation Lock
    local effectiveTable = GachaEngine._buildEffectiveTable(profile.accountLevel)

    -- Pity override: if spinCount >= pityThreshold, force Legendary+
    profile.spinCount = profile.spinCount + 1
    local forcePity = profile.spinCount >= C.PityThreshold

    -- Roll
    local rarity, styleName = GachaEngine._rollRarity(effectiveTable, forcePity,
        profile.accountLevel)

    if rarity ~= "Common" and rarity ~= "Rare" then
        profile.spinCount = 0  -- reset pity on Legendary+
    end

    -- Award style
    if not table.find(profile.inventory, styleName) then
        table.insert(profile.inventory, styleName)
    end

    -- Async save
    task.spawn(function()
        GachaEngine.saveProfile(player)
    end)

    -- Notify client
    Remotes.Events.SpinResult:FireClient(player, {
        rarity           = rarity,
        styleName        = styleName,
        currencyBalances = { yen = profile.yen, gems = profile.gems },
    })

    GachaEngine.syncCurrencyToClient(player)

    return { success = true, rarity = rarity, styleName = styleName }
end

-- ─────────────────────────────────────────────────────────────
-- LEVEL-GATE TABLE BUILDER
-- Overwrites high-tier weights to zero and redistributes
-- ─────────────────────────────────────────────────────────────
function GachaEngine._buildEffectiveTable(accountLevel)
    local G     = GameConstants.Gacha
    local gates = G.LevelGates

    -- Clone base table
    local effective = {}
    local redistrib = 0  -- weight to redistribute from locked tiers

    for _, entry in ipairs(G.DropTable) do
        local row = { rarity = entry.rarity, weight = entry.weight }

        -- Lock check
        if (entry.rarity == "Secret"    and accountLevel < gates.Secret) or
           (entry.rarity == "Godly"     and accountLevel < gates.Godly)  or
           (entry.rarity == "Legendary" and accountLevel < gates.Legendary) then
            redistrib = redistrib + entry.weight
            row.weight = 0
        end

        table.insert(effective, row)
    end

    -- Redistribute locked weight into Common proportionally
    if redistrib > 0 then
        for _, row in ipairs(effective) do
            if row.rarity == "Common" then
                row.weight = row.weight + redistrib
                break
            end
        end
    end

    -- Rebuild cumulative bounds
    local cumul = 0
    for _, row in ipairs(effective) do
        cumul = cumul + row.weight
        row.cumulative = cumul
    end

    return effective
end

-- ─────────────────────────────────────────────────────────────
-- ROLL RARITY  (random float through cumulative bounds)
-- ─────────────────────────────────────────────────────────────
function GachaEngine._rollRarity(effectiveTable, forcePity, accountLevel)
    local roll
    if forcePity then
        -- Force at least Legendary (cumulative bound of Legendary entry)
        local legendaryCumul = 0
        for _, row in ipairs(effectiveTable) do
            if row.rarity == "Legendary" then
                legendaryCumul = row.cumulative
                break
            end
        end
        -- Roll in range [legendaryStart, 1.0]
        local legendaryStart = 0
        for _, row in ipairs(effectiveTable) do
            if row.rarity == "Legendary" then
                legendaryStart = row.cumulative - row.weight
                break
            end
        end
        roll = legendaryStart + math.random() * (1.0 - legendaryStart)
    else
        roll = math.random()  -- [0, 1)
    end

    -- Iterate cumulative bounds to assign rarity
    local assignedRarity = "Common"
    for _, row in ipairs(effectiveTable) do
        if roll <= row.cumulative and row.weight > 0 then
            assignedRarity = row.rarity
            break
        end
    end

    -- Pick a style from that rarity tier
    local styleName = GachaEngine._pickStyle(assignedRarity)
    return assignedRarity, styleName
end

-- ─────────────────────────────────────────────────────────────
-- STYLE PICKER  (selects a specific style from rarity tier)
-- ─────────────────────────────────────────────────────────────
function GachaEngine._pickStyle(rarity)
    local matches = {}
    for name, def in pairs(GameConstants.Styles) do
        if def.rarity == rarity then
            table.insert(matches, name)
        end
    end
    if #matches == 0 then return "Rookie" end
    return matches[math.random(1, #matches)]
end

-- ─────────────────────────────────────────────────────────────
-- CURRENCY SYNC
-- ─────────────────────────────────────────────────────────────
function GachaEngine.syncCurrencyToClient(player)
    local userId  = tostring(player.UserId)
    local profile = profileCache[userId]
    if not profile then return end

    Remotes.Events.CurrencyUpdate:FireClient(player, {
        yen  = profile.yen,
        gems = profile.gems,
    })
end

-- ─────────────────────────────────────────────────────────────
-- REWARD APPEND (called from MatchStateMachine on match end)
-- ─────────────────────────────────────────────────────────────
function GachaEngine.appendReward(player, yenAmount)
    local userId  = tostring(player.UserId)
    local profile = profileCache[userId]
    if not profile then return end

    profile.yen = profile.yen + yenAmount

    task.spawn(function()
        GachaEngine.saveProfile(player)
    end)

    GachaEngine.syncCurrencyToClient(player)
end

-- ─────────────────────────────────────────────────────────────
-- REMOTE FUNCTION WIRING
-- ─────────────────────────────────────────────────────────────
Remotes.Functions.RequestSpin.OnServerInvoke = function(player, payload)
    return GachaEngine.requestSpin(player, payload.currency)
end

Remotes.Functions.GetProfile.OnServerInvoke = function(player)
    local userId  = tostring(player.UserId)
    local profile = profileCache[userId]
    if not profile then return {} end
    return {
        yen       = profile.yen,
        gems      = profile.gems,
        level     = profile.accountLevel,
        style     = profile.style,
        inventory = profile.inventory,
    }
end

return GachaEngine
