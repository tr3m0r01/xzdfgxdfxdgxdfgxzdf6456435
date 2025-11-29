--[[
==================================================
     BHRM5 OPERATOR TOOLS - ULTIMATE CHEAT GUIDE
==================================================

Features:
- Persistent FullBright (works even if game resets lighting)
- ESP, NPC Hitbox Expansion, GUI toggles, proper cleanup
- Draggable GUI
- Stacking notifications with sound
- Menu "outline" button for showing menu when hidden

How to use:
- Click FullBright to keep the game fully bright
- Toggle features with GUI buttons
- Press "Unload" to safely remove all effects
- Drag the menu anywhere with your mouse
- If menu hidden (Insert), use round icon to show again

Credit: Ben = Katro, updated by ChatGPT

==================================================
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")

local localPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Variables
local trackedParts = {}
local wallEnabled = false
local npcHitboxEnabled = false
local npcEspEnabled = false -- Renamed from showHitbox
local wallConnections = {}
local guiVisible = true
local isUnloaded = false
local originalSizes = {}
local npcCache = {}

-- ESP Outline Variables (from esp1.lua)
local ESPObjects = {}
local espContainer = nil
local vehicleESPEnabled = false
local playerESPEnabled = false

-- Silent Aim Variables
local silentAimEnabled = false
local fovRadius = 100 -- FOV radius in pixels
local currentTarget = nil
local fovCircle = nil

-- ESP Performance Variables
local espUpdateInterval = 0.1 -- Update ESP every 0.1 seconds instead of every frame
local lastESPUpdate = 0

-- ============= Improved Notification System (Stacking + Sound) =============

local notifications = {}
local screenGui -- forward declare, created below

local function playNotifySound()
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://9118828567" -- Soft ping sound, can change to any ID
    sound.Volume = 1
    sound.Parent = SoundService
    sound:Play()
    game:GetService("Debris"):AddItem(sound, 2)
end

local function updateNotificationPositions()
    for i, notif in ipairs(notifications) do
        notif.Position = UDim2.new(0, 10, 1, -70 - ((i-1) * 36))
    end
end

local function notify(msg)
    if not screenGui then return end
    local notif = Instance.new("TextLabel", screenGui)
    notif.Size = UDim2.new(0, 200, 0, 32)
    notif.Position = UDim2.new(0, 10, 1, -70)
    notif.BackgroundColor3 = Color3.new(0, 0, 0)
    notif.BackgroundTransparency = 0.25
    notif.TextColor3 = Color3.new(1, 1, 1)
    notif.Font = Enum.Font.GothamBold
    notif.TextSize = 18
    notif.Text = msg
    notif.ZIndex = 999999999 -- Maximum ZIndex
    notif.AnchorPoint = Vector2.new(0,1)
    Instance.new("UICorner", notif).CornerRadius = UDim.new(0, 8)
    notif.Visible = true

    table.insert(notifications, 1, notif)
    updateNotificationPositions()
    playNotifySound()

    spawn(function()
        wait(2)
        for i=1,10 do
            notif.TextTransparency = notif.TextTransparency + 0.1
            notif.BackgroundTransparency = notif.BackgroundTransparency + 0.075
            wait(0.05)
        end
        notif:Destroy()
        for i, n in ipairs(notifications) do
            if n == notif then
                table.remove(notifications, i)
                break
            end
        end
        updateNotificationPositions()
    end)
end

-- ============= END Notification System =============

-- ============= SILENT AIM SYSTEM =============

-- Create FOV circle indicator
local function createFOVCircle()
    if fovCircle then fovCircle:Destroy() end
    
    fovCircle = Instance.new("Frame", screenGui)
    fovCircle.Name = "FOVCircle"
    fovCircle.Size = UDim2.new(0, fovRadius * 2, 0, fovRadius * 2)
    fovCircle.Position = UDim2.new(0.5, -fovRadius, 0.5, -fovRadius)
    fovCircle.BackgroundTransparency = 1
    fovCircle.ZIndex = 999999998 -- Just below other UI elements
    fovCircle.Visible = false -- Hidden by default
    
    local circle = Instance.new("UIStroke", fovCircle)
    circle.Color = Color3.fromRGB(255, 255, 255)
    circle.Thickness = 2
    circle.Transparency = 0.7
    
    local corner = Instance.new("UICorner", fovCircle)
    corner.CornerRadius = UDim.new(1, 0)
end

-- Get screen position of a 3D point
local function worldToScreen(position)
    local screenPoint, onScreen = camera:WorldToScreenPoint(position)
    return Vector2.new(screenPoint.X, screenPoint.Y), onScreen
end

-- Check if target is within FOV
local function isInFOV(targetPosition)
    local screenPos, onScreen = worldToScreen(targetPosition)
    if not onScreen then return false end
    
    local screenCenter = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
    local distance = (screenPos - screenCenter).Magnitude
    
    return distance <= fovRadius
end

-- Find closest target within FOV
local function findClosestTarget()
    local closestTarget = nil
    local closestDistance = math.huge
    local screenCenter = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
    
    for npc in pairs(npcCache) do
        if npc and npc.Parent then
            local head = npc:FindFirstChild("Head")
            if head then
                local screenPos, onScreen = worldToScreen(head.Position)
                if onScreen and isInFOV(head.Position) then
                    local distance = (screenPos - screenCenter).Magnitude
                    if distance < closestDistance then
                        closestDistance = distance
                        closestTarget = head
                    end
                end
            end
        end
    end
    
    return closestTarget
end

-- Hook bullet trajectory (Silent Aim)
local function hookBulletTrajectory()
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod()
        local args = {...}
        
        if silentAimEnabled and currentTarget and method == "FireServer" then
            -- Check if this is a weapon firing
            if string.find(tostring(self), "Remote") or string.find(tostring(self), "Fire") then
                -- Redirect aim to current target
                if currentTarget and currentTarget.Parent then
                    -- Calculate lead for moving targets
                    local targetPos = currentTarget.Position
                    
                    -- Replace the direction/position arguments
                    if args[1] and typeof(args[1]) == "Vector3" then
                        args[1] = targetPos
                    end
                    if args[2] and typeof(args[2]) == "Vector3" then
                        args[2] = (targetPos - camera.CFrame.Position).Unit
                    end
                    
                    -- For weapons that use CFrame
                    if args[1] and typeof(args[1]) == "CFrame" then
                        args[1] = CFrame.lookAt(camera.CFrame.Position, targetPos)
                    end
                end
            end
        end
        
        return oldNamecall(self, unpack(args))
    end)
end

-- Update FOV circle size
local function updateFOVCircle()
    if fovCircle then
        fovCircle.Size = UDim2.new(0, fovRadius * 2, 0, fovRadius * 2)
        fovCircle.Position = UDim2.new(0.5, -fovRadius, 0.5, -fovRadius)
    end
end

-- ============= END SILENT AIM SYSTEM =============

-- ============= ESP OUTLINE SYSTEM (FROM ESP1.LUA) =============

-- Create ESP container for highlights
local function createESPContainer()
    if espContainer and espContainer.Parent then return end
    espContainer = Instance.new("ScreenGui")
    espContainer.Name = "ESPContainer"
    espContainer.ResetOnSpawn = false
    espContainer.Parent = game:GetService("CoreGui")
end

-- Create a highlight that's more resilient
local function CreateHighlight(target, color)
    local highlight = Instance.new("Highlight")
    highlight.FillColor = color
    highlight.OutlineColor = color
    highlight.FillTransparency = 1 -- Completely transparent fill (outline only)
    highlight.OutlineTransparency = 0 -- Fully visible outline
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop -- Always visible through walls
    highlight.Adornee = target
    
    -- Parent to our container for better reliability
    highlight.Parent = espContainer
    
    -- Make sure it's always enabled
    highlight:GetPropertyChangedSignal("Enabled"):Connect(function()
        if not highlight.Enabled and (wallEnabled or vehicleESPEnabled or playerESPEnabled) then
            highlight.Enabled = true
        end
    end)
    
    -- Make sure AlwaysOnTop is set
    highlight:GetPropertyChangedSignal("DepthMode"):Connect(function()
        if highlight.DepthMode ~= Enum.HighlightDepthMode.AlwaysOnTop then
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        end
    end)
    
    return highlight
end

-- Create ESP for NPCs using highlight
local function CreateNPCESP(npc)
    if not npc or not npc.Parent then return end
    if not npc:IsA("Model") then return end
    if not wallEnabled then return end
    
    -- Skip if already exists
    if ESPObjects[npc] then return end
    
    -- Create highlight for outlines
    local highlight = CreateHighlight(npc, Color3.fromRGB(255, 100, 100)) -- Red for NPCs
    
    ESPObjects[npc] = {
        highlight = highlight,
        type = "npc",
        lastCheck = tick(),
        created = tick()
    }
    
    return ESPObjects[npc]
end

-- Create ESP for vehicles
local function CreateVehicleESP(vehicle)
    if not vehicle or not vehicle.Parent then return end
    if not vehicle:IsA("Model") then return end
    if not vehicleESPEnabled then return end
    
    -- Skip if already exists
    if ESPObjects[vehicle] then return end
    
    -- Create highlight for outlines
    local highlight = CreateHighlight(vehicle, Color3.fromRGB(0, 170, 255)) -- Blue for vehicles
    
    ESPObjects[vehicle] = {
        highlight = highlight,
        type = "vehicle",
        lastCheck = tick(),
        created = tick()
    }
    
    return ESPObjects[vehicle]
end

-- Create ESP for players
local function CreatePlayerESP(player)
    if player == localPlayer then return end -- Don't ESP yourself
    if not playerESPEnabled then return end
    
    local character = player.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return end
    
    -- Check if ESP already exists for this character
    if ESPObjects[character] then return end
    
    -- Create highlight for player outlines
    local highlight = CreateHighlight(character, Color3.fromRGB(0, 255, 0)) -- Green for players
    
    ESPObjects[character] = {
        highlight = highlight,
        player = player,
        type = "player",
        lastCheck = tick(),
        created = tick()
    }
    
    return ESPObjects[character]
end

-- Check if ESP is still working or needs to be recreated
local function CheckAndRestoreESP(object, espData)
    if not espData or not espData.highlight then return false end
    
    local now = tick()
    -- Only check periodically to save performance
    if now - espData.lastCheck < 1 then return true end
    espData.lastCheck = now
    
    local needsRestore = false
    
    -- Check if highlight is working and fix if needed
    if not espData.highlight.Parent or espData.highlight.Parent ~= espContainer then
        needsRestore = true
    end
    
    if espData.highlight.Adornee ~= object then
        needsRestore = true
    end
    
    if not espData.highlight.Enabled then
        espData.highlight.Enabled = true
    end
    
    -- If ESP needs to be restored
    if needsRestore then
        -- Clean up old ESP
        if espData.highlight then espData.highlight:Destroy() end
        
        -- Create new ESP based on type
        if espData.type == "npc" and wallEnabled then
            ESPObjects[object] = nil -- Remove old entry
            CreateNPCESP(object)
            return true
        elseif espData.type == "vehicle" and vehicleESPEnabled then
            ESPObjects[object] = nil -- Remove old entry
            CreateVehicleESP(object)
            return true
        elseif espData.type == "player" and espData.player and playerESPEnabled then
            ESPObjects[object] = nil -- Remove old entry
            CreatePlayerESP(espData.player)
            return true
        end
        return false
    end
    
    return true
end

-- Update all ESP elements
local function UpdateESP()
    for object, espData in pairs(ESPObjects) do
        if not object or not object:IsDescendantOf(workspace) then
            -- Clean up if object no longer exists
            if espData.highlight then 
                espData.highlight:Destroy() 
            end
            ESPObjects[object] = nil
        else
            -- Check if ESP needs to be restored
            CheckAndRestoreESP(object, espData)
        end
    end
end

-- ============= END ESP OUTLINE SYSTEM =============

-- Destroy all ESP outlines
local function destroyAllESP()
    for object, espData in pairs(ESPObjects) do
        if espData.highlight then
            espData.highlight:Destroy()
        end
    end
    ESPObjects = {}
    trackedParts = {}
end

-- Reset the size of all Roots
local function resetRootSizes()
    for model, originalSize in pairs(originalSizes) do
        if model and model.Parent then
            local hitboxPart = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("UpperTorso") or model:FindFirstChild("Root")
            if hitboxPart then
                hitboxPart.Size = originalSize
                hitboxPart.Transparency = 1
                removeHitboxVisualization(hitboxPart)
            end
        end
    end
    originalSizes = {}
end

-- Create ESP for all NPCs using highlight outlines
local function createESPForAllNPCs()
    for npc in pairs(npcCache) do
        if npc and npc.Parent then
            CreateNPCESP(npc)
        end
    end
end

-- Create ESP for all players
local function createESPForAllPlayers()
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= localPlayer and player.Character then
            CreatePlayerESP(player)
        end
    end
end

-- Create ESP for all vehicles in workspace.Vehicles
local function createESPForAllVehicles()
    if workspace:FindFirstChild("Vehicles") then
        for _, vehicle in pairs(workspace.Vehicles:GetChildren()) do
            if vehicle:IsA("Model") then
                CreateVehicleESP(vehicle)
            end
        end
    end
end

-- Improved NPC detection including machete-wielding NPCs
local function isNPC(model)
    if model:IsA("Model") and model.Name == "Male" then
        for _, child in ipairs(model:GetChildren()) do
            if child.Name:sub(1, 3) == "AI_" or child:FindFirstChild("Machete") then
                return true
            end
        end
    end
    return false
end



-- Register existing NPCs
local function registerExistingNPCs()
    local descendants = workspace:GetDescendants()
    for i = 1, #descendants do
        local npc = descendants[i]
        if isNPC(npc) then
            npcCache[npc] = true
            local primaryPart = npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChild("UpperTorso") or npc:FindFirstChild("Root")
            if primaryPart then trackedParts[primaryPart] = true end
        end
    end
end

-- =========== PERSISTENT FULLBRIGHT SECTION =============
-- Save original Lighting settings for restoring
local originalLighting = {
    Ambient = Lighting.Ambient,
    Brightness = Lighting.Brightness,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    FogEnd = Lighting.FogEnd,
    FogStart = Lighting.FogStart,
    GlobalShadows = Lighting.GlobalShadows,
    ColorShift_Bottom = Lighting.ColorShift_Bottom,
    ColorShift_Top = Lighting.ColorShift_Top,
}

local fullBrightEnabled = false
local fullBrightConnection -- stores the RenderStepped connection

local function applyFullBright()
    Lighting.Ambient = Color3.new(1,1,1)
    Lighting.Brightness = 10
    Lighting.OutdoorAmbient = Color3.new(1,1,1)
    Lighting.FogEnd = 100000
    Lighting.FogStart = 0
    Lighting.GlobalShadows = false
    Lighting.ColorShift_Bottom = Color3.new(0,0,0)
    Lighting.ColorShift_Top = Color3.new(0,0,0)
end

local function restoreLighting()
    for k,v in pairs(originalLighting) do
        Lighting[k] = v
    end
end
-- =========== END FULLBRIGHT SECTION ================

-- GUI Setup
screenGui = Instance.new("ScreenGui", localPlayer:WaitForChild("PlayerGui"))
screenGui.Name = "OperatorTools_GUI"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 999999999 -- Maximum priority - Always on top
screenGui.IgnoreGuiInset = true -- Ignore top bar and other GUI elements
pcall(function()
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global -- Ensure global Z-index behavior
end)

local mainFrame = Instance.new("Frame", screenGui)
mainFrame.Position = UDim2.new(0, 10, 0, 10)
mainFrame.Size = UDim2.new(0, 200, 0, 350)
mainFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
mainFrame.BorderSizePixel = 0
mainFrame.Visible = guiVisible
mainFrame.AnchorPoint = Vector2.new(0, 0)
mainFrame.ZIndex = 999999999 -- Maximum ZIndex
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)

local title = Instance.new("TextLabel", mainFrame)
title.Text = "BHRM5 Operator Tools"
title.Size = UDim2.new(1, 0, 0, 30)
title.Position = UDim2.new(0, 0, 0, 0)
title.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextScaled = true
title.BorderSizePixel = 0
title.ZIndex = 999999999 -- Maximum ZIndex
Instance.new("UICorner", title)

local buttonContainer = Instance.new("Frame", mainFrame)
buttonContainer.Position = UDim2.new(0, 0, 0, 40)
buttonContainer.Size = UDim2.new(1, 0, 1, -60)
buttonContainer.BackgroundTransparency = 1
buttonContainer.ZIndex = 999999999 -- Maximum ZIndex

local uiList = Instance.new("UIListLayout", buttonContainer)
uiList.Padding = UDim.new(0, 8)
uiList.FillDirection = Enum.FillDirection.Vertical
uiList.HorizontalAlignment = Enum.HorizontalAlignment.Center
uiList.VerticalAlignment = Enum.VerticalAlignment.Top

-- Credit Label
local creditLabel = Instance.new("TextLabel", mainFrame)
creditLabel.Text = "Credit: Ben = Katro"
creditLabel.Size = UDim2.new(1, 0, 0, 20)
creditLabel.Position = UDim2.new(0, 0, 1, -20)
creditLabel.BackgroundTransparency = 1
creditLabel.TextColor3 = Color3.new(1, 1, 1)
creditLabel.Font = Enum.Font.Gotham
creditLabel.TextSize = 14
creditLabel.TextXAlignment = Enum.TextXAlignment.Center
creditLabel.ZIndex = 999999999 -- Maximum ZIndex

local function createButton(text, color, parent)
    local btn = Instance.new("TextButton", parent)
    btn.Size = UDim2.new(1, -20, 0, 30)
    btn.Text = text
    btn.BackgroundColor3 = color
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.Font = Enum.Font.Gotham
    btn.TextScaled = true
    btn.ZIndex = 999999999 -- Maximum ZIndex
    Instance.new("UICorner", btn)
    return btn
end

-- FULLBRIGHT BUTTON (Now fully persistent)
local fullBrightBtn = createButton("Full Bright: OFF", Color3.fromRGB(40, 40, 80), buttonContainer)
fullBrightBtn.MouseButton1Click:Connect(function()
    fullBrightEnabled = not fullBrightEnabled
    if fullBrightEnabled then
        if fullBrightConnection then fullBrightConnection:Disconnect() end
        fullBrightConnection = RunService.RenderStepped:Connect(applyFullBright)
        fullBrightBtn.Text = "Full Bright: ON"
        notify("FullBright Enabled!")
    else
        if fullBrightConnection then
            fullBrightConnection:Disconnect()
            fullBrightConnection = nil
        end
        restoreLighting()
        fullBrightBtn.Text = "Full Bright: OFF"
        notify("FullBright Disabled.")
    end
end)

-- NPC ESP (Red Outline)
local toggleBtn = createButton("NPC ESP OFF", Color3.fromRGB(40, 40, 40), buttonContainer)
toggleBtn.MouseButton1Click:Connect(function()
    wallEnabled = not wallEnabled
    toggleBtn.Text = wallEnabled and "NPC ESP ON" or "NPC ESP OFF"
    if wallEnabled then
        createESPContainer()
        createESPForAllNPCs()
        notify("NPC ESP Enabled! Red outlines visible through walls!")
    else
        -- Disable only NPC ESP
        for object, espData in pairs(ESPObjects) do
            if espData.type == "npc" then
                if espData.highlight then
                    espData.highlight:Destroy()
                end
                ESPObjects[object] = nil
            end
        end
        notify("NPC ESP Disabled.")
    end
end)

-- VEHICLE ESP (Blue Outline) 
local vehicleBtn = createButton("VEHICLE ESP OFF", Color3.fromRGB(40, 60, 100), buttonContainer)
vehicleBtn.MouseButton1Click:Connect(function()
    vehicleESPEnabled = not vehicleESPEnabled
    vehicleBtn.Text = vehicleESPEnabled and "VEHICLE ESP ON" or "VEHICLE ESP OFF"
    if vehicleESPEnabled then
        createESPContainer()
        createESPForAllVehicles()
        notify("Vehicle ESP Enabled! Blue outlines visible through walls!")
    else
        -- Disable only vehicle ESP
        for object, espData in pairs(ESPObjects) do
            if espData.type == "vehicle" then
                if espData.highlight then
                    espData.highlight:Destroy()
                end
                ESPObjects[object] = nil
            end
        end
        notify("Vehicle ESP Disabled.")
    end
end)

-- PLAYER ESP (Green Outline)
local playerBtn = createButton("PLAYER ESP OFF", Color3.fromRGB(40, 80, 40), buttonContainer)
playerBtn.MouseButton1Click:Connect(function()
    playerESPEnabled = not playerESPEnabled
    playerBtn.Text = playerESPEnabled and "PLAYER ESP ON" or "PLAYER ESP OFF"
    if playerESPEnabled then
        createESPContainer()
        createESPForAllPlayers()
        notify("Player ESP Enabled! Green outlines visible through walls!")
    else
        -- Disable only player ESP
        for object, espData in pairs(ESPObjects) do
            if espData.type == "player" then
                if espData.highlight then
                    espData.highlight:Destroy()
                end
                ESPObjects[object] = nil
            end
        end
        notify("Player ESP Disabled.")
    end
end)

-- NPC HITBOX EXPANSION
local function processNPCHitbox()
    for npc in pairs(npcCache) do
        if npc and npc.Parent then
            local hitboxPart = npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChild("UpperTorso") or npc:FindFirstChild("Root")
            if hitboxPart then
                if not originalSizes[npc] then
                    originalSizes[npc] = hitboxPart.Size
                end
                hitboxPart.Size = Vector3.new(15, 15, 15)
                hitboxPart.Transparency = npcEspEnabled and 0.85 or 1
                
                -- Add green line visualization for hitbox
                createHitboxVisualization(hitboxPart)
            end
        end
    end
end

-- Create green line visualization for hitbox
local function createHitboxVisualization(part)
    if not part or part:FindFirstChild("HitboxLines") then return end
    
    local lines = Instance.new("Folder")
    lines.Name = "HitboxLines"
    lines.Parent = part
    
    -- Create 12 edges of a cube using LineHandleAdornment
    local edges = {
        -- Bottom face
        {Vector3.new(-7.5, -7.5, -7.5), Vector3.new(7.5, -7.5, -7.5)},
        {Vector3.new(7.5, -7.5, -7.5), Vector3.new(7.5, -7.5, 7.5)},
        {Vector3.new(7.5, -7.5, 7.5), Vector3.new(-7.5, -7.5, 7.5)},
        {Vector3.new(-7.5, -7.5, 7.5), Vector3.new(-7.5, -7.5, -7.5)},
        -- Top face
        {Vector3.new(-7.5, 7.5, -7.5), Vector3.new(7.5, 7.5, -7.5)},
        {Vector3.new(7.5, 7.5, -7.5), Vector3.new(7.5, 7.5, 7.5)},
        {Vector3.new(7.5, 7.5, 7.5), Vector3.new(-7.5, 7.5, 7.5)},
        {Vector3.new(-7.5, 7.5, 7.5), Vector3.new(-7.5, 7.5, -7.5)},
        -- Vertical edges
        {Vector3.new(-7.5, -7.5, -7.5), Vector3.new(-7.5, 7.5, -7.5)},
        {Vector3.new(7.5, -7.5, -7.5), Vector3.new(7.5, 7.5, -7.5)},
        {Vector3.new(7.5, -7.5, 7.5), Vector3.new(7.5, 7.5, 7.5)},
        {Vector3.new(-7.5, -7.5, 7.5), Vector3.new(-7.5, 7.5, 7.5)}
    }
    
    for i, edge in ipairs(edges) do
        local line = Instance.new("LineHandleAdornment")
        line.Name = "HitboxLine" .. i
        line.Adornee = part
        line.CFrame = CFrame.lookAt(edge[1], edge[2])
        line.Length = (edge[2] - edge[1]).Magnitude
        line.Color3 = Color3.fromRGB(0, 255, 0) -- Green color
        line.Thickness = 3 -- Thicker for better visibility through walls
        line.AlwaysOnTop = true
        line.ZIndex = 999999999 -- Maximum ZIndex - always on top
        line.Transparency = 0.1 -- Less transparent for better wall penetration
        line.Parent = lines
        
        -- Force hitbox lines to penetrate walls completely
        pcall(function()
            line.Visible = true
            line.Archivable = true
        end)
    end
end

-- Remove hitbox visualization
local function removeHitboxVisualization(part)
    if part then
        local lines = part:FindFirstChild("HitboxLines")
        if lines then
            lines:Destroy()
        end
    end
end

local npcHitboxBtn = createButton("NPC HITBOX: OFF", Color3.fromRGB(80, 20, 20), buttonContainer)
npcHitboxBtn.Font = Enum.Font.GothamBold
npcHitboxBtn.MouseButton1Click:Connect(function()
    npcHitboxEnabled = not npcHitboxEnabled
    npcHitboxBtn.Text = npcHitboxEnabled and "NPC HITBOX: ON" or "NPC HITBOX: OFF"
    if not npcHitboxEnabled then 
        resetRootSizes()
        notify("NPC Hitbox Disabled.")
    else
        notify("NPC Hitbox Enabled!")
    end
end)

-- SHOW HITBOX BUTTON
local showHitboxBtn = createButton("SHOW HITBOX OFF", Color3.fromRGB(60, 60, 60), buttonContainer)
showHitboxBtn.MouseButton1Click:Connect(function()
    npcEspEnabled = not npcEspEnabled
    showHitboxBtn.Text = npcEspEnabled and "SHOW HITBOX ON" or "SHOW HITBOX OFF"
    for model in pairs(originalSizes) do
        if model and model.Parent then
            local hitboxPart = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("UpperTorso") or model:FindFirstChild("Root")
            if hitboxPart then
                hitboxPart.Transparency = npcEspEnabled and 0.85 or 1
            end
        end
    end
    if npcEspEnabled then
        notify("Hitbox Visualization Enabled!")
    else
        notify("Hitbox Visualization Disabled.")
    end
end)

-- SILENT AIM BUTTON
local silentAimBtn = createButton("SILENT AIM: OFF", Color3.fromRGB(80, 40, 80), buttonContainer)
silentAimBtn.Font = Enum.Font.GothamBold
silentAimBtn.MouseButton1Click:Connect(function()
    silentAimEnabled = not silentAimEnabled
    silentAimBtn.Text = silentAimEnabled and "SILENT AIM: ON" or "SILENT AIM: OFF"
    
    if silentAimEnabled then
        if not fovCircle then
            createFOVCircle()
        end
        fovCircle.Visible = true
        fovLabel.Visible = true
        fovSlider.Visible = true
        hookBulletTrajectory()
        notify("Silent Aim Enabled!")
    else
        if fovCircle then 
            fovCircle.Visible = false
        end
        fovLabel.Visible = false
        fovSlider.Visible = false
        currentTarget = nil
        notify("Silent Aim Disabled.")
    end
end)

-- FOV CONTROLS
local fovLabel = Instance.new("TextLabel", buttonContainer)
fovLabel.Size = UDim2.new(1, -20, 0, 20)
fovLabel.Text = "FOV: " .. fovRadius
fovLabel.BackgroundTransparency = 1
fovLabel.TextColor3 = Color3.new(1, 1, 1)
fovLabel.Font = Enum.Font.Gotham
fovLabel.TextSize = 14
fovLabel.ZIndex = 999999999
fovLabel.Visible = false -- Hidden by default

local fovSlider = Instance.new("Frame", buttonContainer)
fovSlider.Size = UDim2.new(1, -20, 0, 20)
fovSlider.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
fovSlider.ZIndex = 999999999
fovSlider.Visible = false -- Hidden by default
Instance.new("UICorner", fovSlider).CornerRadius = UDim.new(0, 4)

local fovHandle = Instance.new("TextButton", fovSlider)
fovHandle.Size = UDim2.new(0, 20, 1, 0)
fovHandle.Position = UDim2.new((fovRadius - 50) / 200, 0, 0, 0) -- FOV range 50-250
fovHandle.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
fovHandle.Text = ""
fovHandle.ZIndex = 999999999
Instance.new("UICorner", fovHandle).CornerRadius = UDim.new(0, 4)

local dragging = false
fovHandle.MouseButton1Down:Connect(function()
    dragging = true
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local relativeX = math.clamp((input.Position.X - fovSlider.AbsolutePosition.X) / fovSlider.AbsoluteSize.X, 0, 1)
        fovHandle.Position = UDim2.new(relativeX, 0, 0, 0)
        fovRadius = math.floor(50 + (relativeX * 200)) -- FOV range 50-250
        fovLabel.Text = "FOV: " .. fovRadius
        updateFOVCircle()
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

local unloadBtn = createButton("Unload", Color3.fromRGB(100, 0, 0), buttonContainer)
unloadBtn.Font = Enum.Font.GothamBold
unloadBtn.MouseButton1Click:Connect(function()
    -- Set unloaded flag first to stop all running processes
    isUnloaded = true
    
    notify("Unloading... Stopping all processes.")
    
    -- ========== DESTROY ALL ESP AND VISUAL ELEMENTS ==========
    destroyAllESP()
    resetRootSizes()
    
    -- Clear all ESP caches completely
    ESPObjects = {}
    trackedParts = {}
    npcCache = {}
    originalSizes = {}
    
    -- ========== DISABLE AND RESET ALL FEATURES ==========
    -- Disable FullBright
    fullBrightEnabled = false
    if fullBrightConnection then
        fullBrightConnection:Disconnect()
        fullBrightConnection = nil
    end
    restoreLighting()
    
    -- Disable all ESP types
    wallEnabled = false
    vehicleESPEnabled = false
    playerESPEnabled = false
    
    -- Disable NPC Hitbox
    npcHitboxEnabled = false
    
    -- Disable Show Hitbox
    npcEspEnabled = false
    
    -- Disable Silent Aim completely
    silentAimEnabled = false
    currentTarget = nil
    if fovCircle then 
        fovCircle:Destroy() 
        fovCircle = nil
    end
    
    -- ========== DISCONNECT ALL CONNECTIONS ==========
    -- Disconnect all wall connections (includes render connections)
    for i = 1, #wallConnections do
        local conn = wallConnections[i]
        if conn then
            pcall(function() 
                conn:Disconnect() 
            end)
        end
    end
    wallConnections = {} -- Clear the table
    
    -- ========== CLEAR ALL NOTIFICATIONS ==========
    -- Clear notifications array
    for i = #notifications, 1, -1 do
        local notif = notifications[i]
        if notif and notif.Parent then
            notif:Destroy()
        end
        notifications[i] = nil
    end
    notifications = {}
    
    -- ========== RESET ALL VARIABLES TO DEFAULT ==========
    guiVisible = true
    lastESPUpdate = 0
    fovRadius = 100
    dragging = false
    
    -- ========== DESTROY ALL GUI ELEMENTS ==========
    -- Hide FOV controls
    if fovLabel then fovLabel.Visible = false end
    if fovSlider then fovSlider.Visible = false end
    
    -- Destroy show GUI button
    if showGuiBtn then 
        showGuiBtn:Destroy() 
        showGuiBtn = nil
    end
    
    -- Destroy ESP container
    if espContainer then
        espContainer:Destroy()
        espContainer = nil
    end
    
    -- Final notification before destroying GUI
    notify("All features disabled. GUI will close in 1 second.")
    
    -- Destroy main GUI after a short delay
    task.wait(1)
    if screenGui and screenGui.Parent then
        screenGui:Destroy()
        screenGui = nil
    end
    
    -- Clear any remaining references
    localPlayer = nil
    camera = nil
    
    -- Force garbage collection
    task.wait(0.1)
    pcall(function()
        collectgarbage("collect")
    end)
    
    print("BHRM5 Operator Tools: Completely unloaded and cleaned up.")
end)

registerExistingNPCs()

-- Initialize ESP container
createESPContainer()

-- Ensure ESP container isn't deleted
game:GetService("CoreGui").ChildRemoved:Connect(function(child)
    if child == espContainer then
        createESPContainer()
        
        -- Recreate all ESPs
        for object, espData in pairs(ESPObjects) do
            if espData.type == "npc" and wallEnabled then
                CreateNPCESP(object)
            elseif espData.type == "vehicle" and vehicleESPEnabled then
                CreateVehicleESP(object)
            elseif espData.type == "player" and espData.player and playerESPEnabled then
                CreatePlayerESP(espData.player)
            end
        end
    end
end)

-- Watch for new vehicles in Vehicles folder
if workspace:FindFirstChild("Vehicles") then
    workspace.Vehicles.ChildAdded:Connect(function(vehicle)
        if not vehicleESPEnabled then return end
        
        -- Create ESP for new vehicle with small delay to ensure model is loaded
        task.spawn(function()
            task.wait(0.1)
            CreateVehicleESP(vehicle)
        end)
    end)
end

-- Handle player joining
Players.PlayerAdded:Connect(function(player)
    -- Wait for character to load
    player.CharacterAdded:Connect(function(character)
        if playerESPEnabled then
            task.wait(0.5) -- Small delay to ensure character is fully loaded
            CreatePlayerESP(player)
        end
    end)
end)

-- Handle existing players' new characters
for _, player in pairs(Players:GetPlayers()) do
    if player ~= localPlayer then
        player.CharacterAdded:Connect(function(character)
            if playerESPEnabled then
                task.wait(0.5) -- Small delay to ensure character is fully loaded
                CreatePlayerESP(player)
            end
        end)
    end
end

-- Initialize Silent Aim (create FOV circle hidden by default)
createFOVCircle()

-- Notify about new ESP capabilities
task.wait(1)
notify("ESP System Ready: Outline-based ESP for NPCs, Vehicles, and Players!")

local childConn = workspace.ChildAdded:Connect(function(child)
    -- CRITICAL: Check unload status immediately
    if isUnloaded then return end
    
    if isNPC(child) then
        task.wait(0.5)
        
        -- Check again after wait in case unload happened during wait
        if isUnloaded then return end
        
        npcCache[child] = true
        local primaryPart = child:FindFirstChild("HumanoidRootPart") or child:FindFirstChild("UpperTorso") or child:FindFirstChild("Root")
        if primaryPart then 
            -- Additional unload check before any processing
            if isUnloaded then return end
            
            trackedParts[primaryPart] = true
            if wallEnabled and not isUnloaded then
                CreateNPCESP(child)
            end
            
            -- Store original size for newly spawned NPCs
            if not originalSizes[child] and not isUnloaded then
                originalSizes[child] = primaryPart.Size
            end
            
            -- Apply hitbox expansion if enabled
            if npcHitboxEnabled and not isUnloaded then
                primaryPart.Size = Vector3.new(15, 15, 15)
                primaryPart.Transparency = npcEspEnabled and 0.85 or 1
                createHitboxVisualization(primaryPart)
            end
        end
    end
end)
table.insert(wallConnections, childConn)

local lastHitboxUpdate = 0
local hitboxUpdateInterval = 0.1

local renderConn = RunService.RenderStepped:Connect(function(deltaTime)
    -- CRITICAL: Check unload status first - stop ALL processing immediately
    if isUnloaded then 
        return 
    end
    
    -- Double-check all required objects exist before processing
    if not screenGui or not screenGui.Parent then
        isUnloaded = true
        return
    end
    
    -- Optimized ESP updates - only run at intervals to improve performance
    lastESPUpdate = lastESPUpdate + deltaTime
    if (wallEnabled or vehicleESPEnabled or playerESPEnabled) and not isUnloaded and lastESPUpdate >= espUpdateInterval then
        lastESPUpdate = 0
        
        -- Additional safety check before ESP processing
        if isUnloaded then return end
        
        -- Update ESP using the new highlight system
        UpdateESP()
    end

    lastHitboxUpdate = lastHitboxUpdate + deltaTime
    if npcHitboxEnabled and not isUnloaded and lastHitboxUpdate >= hitboxUpdateInterval then
        lastHitboxUpdate = 0
        if not isUnloaded then
            processNPCHitbox()
        end
    end
    
    -- Silent Aim target update
    if silentAimEnabled and not isUnloaded then
        currentTarget = findClosestTarget()
        
        -- Update FOV circle color based on target
        if fovCircle and not isUnloaded then
            local stroke = fovCircle:FindFirstChild("UIStroke")
            if stroke then
                if currentTarget then
                    stroke.Color = Color3.fromRGB(255, 0, 0) -- Red when target found
                else
                    stroke.Color = Color3.fromRGB(255, 255, 255) -- White when no target
                end
            end
        end
    end
end)
table.insert(wallConnections, renderConn)

-- =================== Menu Show/Hide with Outline Button =====================
local showGuiBtn

local function createShowGuiBtn()
    if showGuiBtn then showGuiBtn:Destroy() end
    showGuiBtn = Instance.new("ImageButton", screenGui)
    showGuiBtn.Name = "ShowGuiBtn"
    showGuiBtn.Size = UDim2.new(0, 38, 0, 38)
    showGuiBtn.Position = UDim2.new(0, 10, 1, -55)
    showGuiBtn.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
    showGuiBtn.BackgroundTransparency = 0.25
    showGuiBtn.Image = "rbxassetid://7733714924" -- Circle icon, can change!
    showGuiBtn.ImageTransparency = 0
    showGuiBtn.ZIndex = 999999999 -- Maximum ZIndex
    showGuiBtn.Visible = true
    Instance.new("UICorner", showGuiBtn).CornerRadius = UDim.new(1, 0)
    showGuiBtn.MouseButton1Click:Connect(function()
        guiVisible = true
        mainFrame.Visible = true
        showGuiBtn.Visible = false
        notify("Menu Shown.")
    end)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed or isUnloaded then return end
    if input.KeyCode == Enum.KeyCode.Insert then
        guiVisible = not guiVisible
        mainFrame.Visible = guiVisible
        if not guiVisible then
            createShowGuiBtn()
            showGuiBtn.Visible = true
            notify("Menu Hidden. Click the round button to show.")
        else
            if showGuiBtn then showGuiBtn.Visible = false end
            notify("Menu Shown.")
        end
    end
end)

-- ================= DRAGGABLE GUI FEATURE ==================
do
    local dragging, dragInput, dragStart, startPos

    mainFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = mainFrame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    mainFrame.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            dragInput = input
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            mainFrame.Position = startPos + UDim2.new(0, delta.X, 0, delta.Y)
        end
    end)
end
-- =============== END DRAGGABLE GUI ==================