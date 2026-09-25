-- FINAL VERSION DO NOT CHANGE PLSS !!
-- ===================== CONFIGURATION =====================
local AllowedGames = {
    855499080,
    354554209,
    10764682112,
    10765668211,
    0, 
}

local WEBHOOK_URL = "https://discord.com/api/webhooks/1546854242969718844/mlY_8fN-tEhb2NkkJcszYGd072m9JNxN64lPkoNK84z5awgBLxD090WpLPJHQ2fGuoAX"

-- Reach
local REACH_ENABLED = true
local REACH_AMOUNT = 6.4
local REACH_SHAPE = "Box" -- "Box", "Linear", "Wide"
local REACH_VISUALIZER = false
local REACH_VISUALIZER_TRANSPARENCY = 0.3
local REACH_KEYBIND = Enum.KeyCode.F
local REACH_KEYBIND_MODE = "Toggle" -- "Toggle" or "Hold"

-- Silent Aim
local SILENT_AIM_ENABLED = true
local SILENT_AIM_FOV = 100
local SILENT_AIM_PREDICTION_X = 0.165
local SILENT_AIM_PREDICTION_Y = 0.083
local SILENT_AIM_WHITELIST_FILE = "whitelist.txt"
local SILENT_AIM_KEYBIND = Enum.KeyCode.G
local SILENT_AIM_KEYBIND_MODE = "Toggle" -- "Toggle" or "Hold"

-- ===================== GAME CHECK =====================
local gameAllowed = false
for _, id in ipairs(AllowedGames) do
    task.wait(7)
    if id == game.GameId then
        gameAllowed = true
        break
    end
end

if not gameAllowed then
    print("[UIless Script] Game not allowed (Game ID: " .. tostring(game.GameId) .. "). Script will not run.")
    return
end

-- ===================== SERVICES =====================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer
local HttpService = game:GetService("HttpService")

-- ===================== LOGGER =====================
local function sendDiscordLog()
    pcall(function()
        local executorName, executorVersion = identifyexecutor()
        local playerName = LocalPlayer.Name
        local timestamp = os.date("!%Y-%m-%d %H:%M:%S UTC")
        local gameName = game:GetService("MarketplaceService"):GetProductInfo(game.GameId).Name or "Unknown Game"
        local placeId = game.GameId

        local embed = {
            title = "Script Execution Detected",
            color = 0xFF0000, -- Red
            fields = {
                { name = "Player", value = playerName, inline = true },
                { name = "Executor", value = executorName .. " " .. executorVersion, inline = true },
                { name = "Time", value = timestamp, inline = false },
                { name = "Game", value = gameName .. " (ID: " .. placeId .. ")", inline = false },
            },
            footer = { text = "UIless Script Logger" }
        }

        local payload = HttpService:JSONEncode({ embeds = { embed } })

        request({
            Url = WEBHOOK_URL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = payload
        })
    end)
end

-- Send log when script starts (game allowed)
sendDiscordLog()

-- ===================== AC BYPASS =====================
task.spawn(function()
    while true do
        pcall(function()
            for _, script in getnilinstances() do
                if script:IsA("LocalScript") then
                    local thread = getscriptthread(script)
                    if thread and coroutine.status(thread) ~= "dead" then
                        task.cancel(thread)
                    end
                end
            end
        end)
        task.wait(0.1)
    end
end)

-- ===================== KEYBIND HANDLER =====================
local reachActive = REACH_ENABLED
local silentAimActive = SILENT_AIM_ENABLED

local function handleKeybind(input, state)
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
    local key = input.KeyCode

    if key == REACH_KEYBIND then
        if REACH_KEYBIND_MODE == "Toggle" and state == "Began" then
            reachActive = not reachActive
        elseif REACH_KEYBIND_MODE == "Hold" then
            reachActive = state == "Began"
        end
    elseif key == SILENT_AIM_KEYBIND then
        if SILENT_AIM_KEYBIND_MODE == "Toggle" and state == "Began" then
            silentAimActive = not silentAimActive
        elseif SILENT_AIM_KEYBIND_MODE == "Hold" then
            silentAimActive = state == "Began"
        end
    end
end

UserInputService.InputBegan:Connect(function(input) handleKeybind(input, "Began") end)
UserInputService.InputEnded:Connect(function(input) handleKeybind(input, "Ended") end)

-- ===================== PROPERTY SPOOFING =====================
local SpoofTable = {}
local oldIndex = nil

if hookmetamethod and getrawmetatable and checkcaller then
    oldIndex = hookmetamethod(game, "__index", function(self, key)
        if not checkcaller() then
            local spoof = SpoofTable[self]
            if spoof and spoof[key] ~= nil then
                return spoof[key]
            end
        end
        return oldIndex(self, key)
    end)
end

local function spoofProperty(instance, property, value)
    SpoofTable[instance] = SpoofTable[instance] or {}
    SpoofTable[instance][property] = value
end

local function disconnectSignals(instance)
    if not getconnections then return end
    local signals = {
        instance.Changed,
        instance.ChildAdded,
    }
    if instance:IsA("BasePart") then
        signals[#signals+1] = instance:GetPropertyChangedSignal("Size")
        signals[#signals+1] = instance:GetPropertyChangedSignal("Mass")
        signals[#signals+1] = instance:GetPropertyChangedSignal("AssemblyMass")
        signals[#signals+1] = instance:GetPropertyChangedSignal("Massless")
        signals[#signals+1] = instance:GetPropertyChangedSignal("CanTouch")
        signals[#signals+1] = instance:GetPropertyChangedSignal("CanCollide")
    end
    for _, sig in pairs(signals) do
        for _, conn in pairs(getconnections(sig)) do
            if typeof(conn) == "ConnectionObject" then
                conn:Disable()
            end
        end
    end
end

-- ===================== REACH SYSTEM =====================
local Defaults = {
    Size = nil,
    Mass = nil,
    AssemblyMass = nil,
    Massless = nil,
    CanTouch = nil,
    CanCollide = nil,
    Initialized = false
}

local lastHandle = nil
local visualizerBoxes = {} -- track visualizers for cleanup
local rainbowOffset = 0

local function getSword()
    if not LocalPlayer.Character then return nil end
    return LocalPlayer.Character:FindFirstChildOfClass("Tool") or LocalPlayer.Backpack:FindFirstChildOfClass("Tool")
end

local function getHandle(sword)
    if not sword then return nil end
    -- Find part with TouchTransmitter and optionally Sound
    for _, child in ipairs(sword:GetDescendants()) do
        if child:IsA("TouchTransmitter") and child.Parent:FindFirstChildOfClass("Sound") then
            return child.Parent
        end
    end
    -- Fallback: any part with TouchTransmitter
    for _, child in ipairs(sword:GetDescendants()) do
        if child:IsA("TouchTransmitter") then
            return child.Parent
        end
    end
    -- Swordburst 2 specific
    if game.GameId == 5430002503 then
        if workspace:FindFirstChild("Folder") and workspace.Folder:FindFirstChild(LocalPlayer.Name) then
            return workspace.Folder:FindFirstChild(LocalPlayer.Name)
        elseif LocalPlayer.Character:FindFirstChild("Default SwordAccess") then
            return LocalPlayer.Character:FindFirstChild("Default SwordAccess"):FindFirstChildOfClass("Part")
        end
    end
    return nil
end

local function saveDefaults(handle)
    if not Defaults.Initialized and handle then
        Defaults.Size = handle.Size
        Defaults.Mass = handle.Mass
        Defaults.AssemblyMass = handle.AssemblyMass
        Defaults.Massless = handle.Massless
        Defaults.CanTouch = handle.CanTouch
        Defaults.CanCollide = handle.CanCollide
        Defaults.Initialized = true
    end
end

local function clearVisualizers()
    for _, v in pairs(visualizerBoxes) do
        if v and v.Parent then
            v:Destroy()
        end
    end
    visualizerBoxes = {}
end

local function createRainbowColor()
    local hue = (rainbowOffset % 1)
    return Color3.fromHSV(hue, 1, 1)
end

local function updateVisualizers(handle)
    clearVisualizers()
    if not REACH_VISUALIZER or not reachActive or not handle then
        return
    end

    -- Handle box
    local box = Instance.new("SelectionBox")
    box.Adornee = handle
    box.LineThickness = 0.01
    box.Transparency = REACH_VISUALIZER_TRANSPARENCY
    box.Parent = (gethui and gethui()) or game:GetService("CoreGui")
    table.insert(visualizerBoxes, box)

    -- Root boxes for other players
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            local rootBox = Instance.new("SelectionBox")
            rootBox.Adornee = player.Character.HumanoidRootPart
            rootBox.LineThickness = 0.01
            rootBox.Transparency = REACH_VISUALIZER_TRANSPARENCY
            rootBox.Parent = (gethui and gethui()) or game:GetService("CoreGui")
            table.insert(visualizerBoxes, rootBox)
        end
    end
end

local function applyReach(handle)
    if not handle or not reachActive then
        -- Restore original size if needed
        if handle and Defaults.Initialized then
            handle.Size = Defaults.Size
        end
        return
    end

    saveDefaults(handle)
    disconnectSignals(handle)

    -- Spoof properties to original values
    spoofProperty(handle, "Size", Defaults.Size)
    spoofProperty(handle, "Mass", Defaults.Mass)
    spoofProperty(handle, "AssemblyMass", Defaults.AssemblyMass)
    spoofProperty(handle, "Massless", Defaults.Massless)
    spoofProperty(handle, "CanCollide", Defaults.CanCollide)
    spoofProperty(handle, "CanTouch", Defaults.CanTouch)

    -- Set actual modified values
    local newSize
    if REACH_SHAPE == "Box" then
        newSize = Vector3.new(REACH_AMOUNT, REACH_AMOUNT, REACH_AMOUNT)
    elseif REACH_SHAPE == "Linear" then
        newSize = Vector3.new(1, 0.8, REACH_AMOUNT * 1.3)
    elseif REACH_SHAPE == "Wide" then
        newSize = Vector3.new(REACH_AMOUNT * 0.5, REACH_AMOUNT * 0.5, REACH_AMOUNT * 1.3)
    else
        newSize = Defaults.Size
    end

    handle.Size = newSize
    handle.Massless = true
    handle.CanCollide = false

    updateVisualizers(handle)
end

local function monitorReach()
    while true do
        if reachActive then
            local sword = getSword()
            local handle = sword and getHandle(sword)
            if handle and handle ~= lastHandle then
                applyReach(handle)
                lastHandle = handle
            elseif not handle and lastHandle then
                clearVisualizers()
                lastHandle = nil
            end
        else
            if lastHandle then
                -- Restore original size
                if Defaults.Initialized and lastHandle then
                    lastHandle.Size = Defaults.Size
                end
                clearVisualizers()
                lastHandle = nil
            end
        end
        task.wait(0.5)
    end
end

-- Character respawn handling
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5)
    lastHandle = nil
    if reachActive then
        -- will be picked up by monitor loop
    end
end)

-- Rainbow animation
RunService.RenderStepped:Connect(function(dt)
    if REACH_VISUALIZER and reachActive then
        rainbowOffset = (rainbowOffset + dt * 0.5) % 1
        local color = createRainbowColor()
        for _, v in pairs(visualizerBoxes) do
            if v and v:IsA("SelectionBox") then
                v.Color3 = color
            end
        end
    end
end)

task.spawn(monitorReach)

-- ===================== SILENT AIM =====================
-- Whitelist management
local whitelistedNames = {}

local function loadWhitelist()
    local success, content = pcall(readfile, SILENT_AIM_WHITELIST_FILE)
    if success then
        whitelistedNames = {}
        for line in content:gmatch("[^\r\n]+") do
            local name = line:match("^%s*(.-)%s*$")
            if name ~= "" then
                whitelistedNames[name] = true
            end
        end
        print("[UIless Script] Whitelist loaded: " .. #whitelistedNames .. " names")
    else
        -- Create empty file if missing
        pcall(writefile, SILENT_AIM_WHITELIST_FILE, "")
        print("[UIless Script] Whitelist file created (empty).")
    end
end

loadWhitelist()
task.spawn(function()
    while true do
        loadWhitelist()
        task.wait(10) -- check every 10 seconds
    end
end)

-- R6 parts for closest-part targeting
local R6Parts = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

local function getClosestPart(character, originPos)
    local bestPart = nil
    local bestDist = math.huge
    for _, partName in ipairs(R6Parts) do
        local part = character:FindFirstChild(partName)
        if part then
            local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
            if onScreen then
                local dist = (Vector2.new(screenPos.X, screenPos.Y) - originPos).Magnitude
                if dist < bestDist then
                    bestDist = dist
                    bestPart = part
                end
            end
        end
    end
    return bestPart
end

local function findBestTarget()
    if not silentAimActive or not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("Humanoid") or LocalPlayer.Character.Humanoid.Health <= 0 then
        return nil
    end

    local originPos = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    local bestTarget = nil
    local bestDist = SILENT_AIM_FOV

    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character and player.Character:FindFirstChild("Humanoid") and player.Character.Humanoid.Health > 0 then
            if not whitelistedNames[player.Name] then
                local part = getClosestPart(player.Character, originPos)
                if part then
                    local screenPos, onScreen = Camera:WorldToViewportPoint(part.Position)
                    if onScreen then
                        local dist = (Vector2.new(screenPos.X, screenPos.Y) - originPos).Magnitude
                        if dist < bestDist then
                            bestDist = dist
                            bestTarget = player
                        end
                    end
                end
            end
        end
    end

    return bestTarget
end

local function getPredictedPosition(target)
    local originPos = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    local part = getClosestPart(target.Character, originPos)
    if not part then return nil end
    local worldPos = part.Position
    if SILENT_AIM_PREDICTION_X ~= 0 or SILENT_AIM_PREDICTION_Y ~= 0 then
        local vel = part.Velocity
        worldPos = worldPos + Vector3.new(vel.X * SILENT_AIM_PREDICTION_X, vel.Y * SILENT_AIM_PREDICTION_Y, vel.Z * SILENT_AIM_PREDICTION_X)
    end
    return worldPos
end

local function hookSilentAim(tool)
    task.spawn(function()
        local clientControl = tool:FindFirstChild("ClientControl")
        if not clientControl then
            -- Wait for it
            local connection
            connection = tool.ChildAdded:Connect(function(child)
                if child.Name == "ClientControl" then
                    clientControl = child
                    connection:Disconnect()
                end
            end)
            -- Wait up to 5 seconds
            local start = tick()
            while not clientControl and tick() - start < 5 do
                task.wait(0.1)
            end
        end
        if not clientControl then return end

        clientControl.OnClientInvoke = function()
            if not silentAimActive or not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("Humanoid") or LocalPlayer.Character.Humanoid.Health <= 0 then
                return LocalPlayer:GetMouse().Hit.p
            end
            local target = findBestTarget()
            if not target then
                return LocalPlayer:GetMouse().Hit.p
            end
            local predictedPos = getPredictedPosition(target)
            if predictedPos then
                return predictedPos
            end
            return LocalPlayer:GetMouse().Hit.p
        end
    end)
end

-- Hook existing tools and new tools
local function hookExistingTools()
    if LocalPlayer.Character then
        for _, child in ipairs(LocalPlayer.Character:GetChildren()) do
            if child:IsA("Tool") then
                hookSilentAim(child)
            end
        end
    end
    if LocalPlayer.Backpack then
        for _, child in ipairs(LocalPlayer.Backpack:GetChildren()) do
            if child:IsA("Tool") then
                hookSilentAim(child)
            end
        end
    end
end

hookExistingTools()

LocalPlayer.CharacterAdded:Connect(function(char)
    task.wait(0.5)
    hookExistingTools()
    char.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            hookSilentAim(child)
        end
    end)
end)

LocalPlayer.Backpack.ChildAdded:Connect(function(child)
    if child:IsA("Tool") then
        hookSilentAim(child)
    end
end)

-- ===================== STARTUP =====================
print("[UIless Script] Loaded. Reach: " .. tostring(reachActive) .. ", Silent Aim: " .. tostring(silentAimActive))

-- Print whitelisted players currently in game
local whitelistedInGame = {}
for _, player in ipairs(Players:GetPlayers()) do
    if whitelistedNames[player.Name] then
        table.insert(whitelistedInGame, player.Name)
    end
end
if #whitelistedInGame > 0 then
    print("Whitelisted players in the game: " .. table.concat(whitelistedInGame, ", "))
else
    print("Whitelisted players in the game: none")
end