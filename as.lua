-- ESP Script for Vehicles and Players with GUI
-- Creates blue outline lines around vehicles that can be seen through walls

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

-- ESP Settings
local ESP = {
    Enabled = true,
    OutlineColor = Color3.fromRGB(0, 170, 255), -- Blue outline for vehicles
    PlayerOutlineColor = Color3.fromRGB(255, 0, 0), -- Red outline for players
    OutlineTransparency = 0, -- Fully visible outline
    FillTransparency = 1, -- Completely transparent fill (no fill)
    TextEnabled = false, -- Disable all text labels
    LineThickness = 3, -- Make outlines thicker and more visible
    UpdateInterval = 1, -- Default update interval (1 second)
    FastUpdateInterval = 0.1, -- Fast update interval (0.1 seconds)
    CurrentInterval = 1, -- Current active interval
    AutoRespawnESP = true, -- Automatically recreate ESP if it gets removed
    Debug = true, -- Show debug messages
    ShowVehicles = true, -- Show ESP for vehicles
    ShowPlayers = true, -- Show ESP for players
    ScanFullWorkspace = false, -- No longer scan full workspace
    AutoFullScan = true, -- Auto full scan every interval
    ChunkSize = 10, -- Number of objects to process per frame for chunked scanning
    LagFreeMode = true, -- Optimize for performance
    FastScanMode = false -- Toggle for fast scan mode (0.1s)
}

-- Storage for ESP objects
local ESPObjects = {}
local knownVehicleClasses = {}
local lastFullUpdateTime = 0
local lastFPSCheckTime = 0
local currentFPS = 60
local scanQueue = {}
local chunkedScanActive = false
local scannedThisSecond = false
local totalVehiclesFound = 0

-- Debug function
local function DebugPrint(message)
    if ESP.Debug then
        print("[ESP Debug] " .. message)
    end
end

-- Create a container for our ESP objects to prevent them from being deleted
local espContainer = Instance.new("ScreenGui")
espContainer.Name = "ESPContainer"
espContainer.ResetOnSpawn = false
espContainer.Parent = game:GetService("CoreGui")

-- Check if an object looks like a vehicle based on its properties and children
local function LooksLikeVehicle(obj)
    if not obj:IsA("Model") then return false end
    
    -- Skip players
    if Players:GetPlayerFromCharacter(obj) then return false end
    
    -- If we've already determined this object's class is a vehicle, return true
    local className = obj.ClassName
    if knownVehicleClasses[className] then return true end
    
    -- Check for common vehicle parts or properties
    local vehicleIndicators = {
        "Body", "Chassis", "Engine", "Wheels", "Seats", "Seat", "VehicleSeat", 
        "Tank", "Turret", "Gun", "Cannon", "Track", "Tracks", "Vehicle", "Car",
        "Handle", "SteeringWheel", "Exhaust", "Hull", "Main", "Model"
    }
    
    -- Check if name contains vehicle-related terms
    local nameLower = obj.Name:lower()
    if nameLower:find("car") or nameLower:find("vehicle") or nameLower:find("tank") or 
       nameLower:find("truck") or nameLower:find("jeep") or nameLower:find("van") or
       nameLower:find("apc") or nameLower:find("artillery") or nameLower:find("humvee") or
       nameLower:find("transport") or nameLower:find("heli") or nameLower:find("chopper") or
       nameLower:find("plane") or nameLower:find("jet") or nameLower:find("ship") or
       nameLower:find("boat") or nameLower:find("mech") or nameLower:find("robot") or
       nameLower:find("walker") or nameLower:find("atv") or nameLower:find("btr") or
       nameLower:find("t-") or nameLower:find("m1") or nameLower:find("kv") or
       nameLower:find("tiger") or nameLower:find("panzer") or nameLower:find("abrams") or
       nameLower:find("sherman") or nameLower:find("chassis") then
        knownVehicleClasses[className] = true
        return true
    end
    
    -- Check for vehicle indicator parts
    for _, indicatorName in ipairs(vehicleIndicators) do
        if obj:FindFirstChild(indicatorName) then
            knownVehicleClasses[className] = true
            return true
        end
    end
    
    -- Check if it has specific parts like VehicleSeat or configuration
    for _, child in pairs(obj:GetChildren()) do
        if child:IsA("VehicleSeat") or 
           child:IsA("Model") and (child.Name:lower():find("seat") or child.Name:lower():find("driver")) or
           child:IsA("Configuration") or
           child:IsA("Model") and (child.Name:lower():find("wheel") or child.Name:lower():find("turret")) then
            knownVehicleClasses[className] = true
            return true
        end
    end
    
    -- Check for specific properties like PrimaryPart size (vehicles are usually larger)
    if obj.PrimaryPart and obj.PrimaryPart:IsA("BasePart") then
        local size = obj.PrimaryPart.Size
        if (size.X > 5 or size.Y > 5 or size.Z > 5) and #obj:GetChildren() > 3 then
            knownVehicleClasses[className] = true
            return true
        end
    end
    
    -- Check if it has physics constraints like hinges (often used in vehicles)
    for _, child in pairs(obj:GetDescendants()) do
        if child:IsA("HingeConstraint") or child:IsA("BallSocketConstraint") or child:IsA("SpringConstraint") then
            knownVehicleClasses[className] = true
            return true
        end
    end
    
    return false
end

-- Function to create a highlight that's more resilient
local function CreateHighlight(target, color)
    local highlight = Instance.new("Highlight")
    highlight.FillColor = color
    highlight.OutlineColor = color
    highlight.FillTransparency = ESP.FillTransparency
    highlight.OutlineTransparency = ESP.OutlineTransparency
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop -- Always visible through walls
    highlight.Adornee = target
    
    -- Make lines thicker if possible (may not work in all Roblox versions)
    pcall(function()
        highlight.OutlineSize = ESP.LineThickness
    end)
    
    -- Parent to our container for better reliability
    highlight.Parent = espContainer
    
    -- Make sure it's always enabled
    highlight:GetPropertyChangedSignal("Enabled"):Connect(function()
        if not highlight.Enabled and ESP.Enabled then
            highlight.Enabled = true
        end
    end)
    
    -- Make sure it's always visible
    highlight:GetPropertyChangedSignal("OutlineTransparency"):Connect(function()
        if highlight.OutlineTransparency > ESP.OutlineTransparency and ESP.Enabled then
            highlight.OutlineTransparency = ESP.OutlineTransparency
        end
    end)
    
    -- Make sure AlwaysOnTop is set
    highlight:GetPropertyChangedSignal("DepthMode"):Connect(function()
        if highlight.DepthMode ~= Enum.HighlightDepthMode.AlwaysOnTop and ESP.Enabled then
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        end
    end)
    
    return highlight
end

-- Create ESP for a vehicle
local function CreateVehicleESP(vehicle)
    if not vehicle or not vehicle.Parent then return end
    if not vehicle:IsA("Model") then return end
    if not ESP.ShowVehicles then return end
    
    -- Skip if already exists
    if ESPObjects[vehicle] then return end
    
    -- Create highlight for outlines
    local highlight = CreateHighlight(vehicle, ESP.OutlineColor)
    
    ESPObjects[vehicle] = {
        highlight = highlight,
        type = "vehicle",
        lastCheck = tick(),
        created = tick()
    }
    
    totalVehiclesFound = totalVehiclesFound + 1
    
    DebugPrint("Created ESP for vehicle: " .. vehicle.Name)
    return ESPObjects[vehicle]
end

-- Create ESP for a player
local function CreatePlayerESP(player)
    if player == LocalPlayer then return end -- Don't ESP yourself
    if not ESP.ShowPlayers then return end
    
    local character = player.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return end
    
    -- Check if ESP already exists for this character
    if ESPObjects[character] then return end
    
    -- Create highlight for player outlines
    local highlight = CreateHighlight(character, ESP.PlayerOutlineColor)
    
    ESPObjects[character] = {
        highlight = highlight,
        player = player,
        type = "player",
        lastCheck = tick(),
        created = tick()
    }
    
    DebugPrint("Created ESP for player: " .. player.Name)
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
        DebugPrint("ESP highlight was reparented or removed, restoring...")
        needsRestore = true
    end
    
    if espData.highlight.Adornee ~= object then
        DebugPrint("ESP lost its target, restoring...")
        needsRestore = true
    end
    
    if espData.highlight.OutlineTransparency > ESP.OutlineTransparency then
        DebugPrint("ESP transparency was changed, restoring...")
        espData.highlight.OutlineTransparency = ESP.OutlineTransparency
    end
    
    if espData.highlight.DepthMode ~= Enum.HighlightDepthMode.AlwaysOnTop then
        DebugPrint("ESP lost AlwaysOnTop setting, restoring...")
        espData.highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    end
    
    if not espData.highlight.Enabled and ESP.Enabled then
        DebugPrint("ESP was disabled, re-enabling...")
        espData.highlight.Enabled = true
    end
    
    -- If ESP needs to be restored and auto-respawn is enabled
    if needsRestore and ESP.AutoRespawnESP then
        -- Clean up old ESP
        if espData.highlight then espData.highlight:Destroy() end
        
        -- Create new ESP based on type
        if espData.type == "vehicle" and ESP.ShowVehicles then
            ESPObjects[object] = nil -- Remove old entry
            CreateVehicleESP(object)
            return true
        elseif espData.type == "player" and espData.player and ESP.ShowPlayers then
            ESPObjects[object] = nil -- Remove old entry
            CreatePlayerESP(espData.player)
            return true
        end
        return false
    end
    
    return true
end

-- Check FPS performance
local lastCheckTime = tick()
local frameCount = 0
local function UpdateFPS()
    frameCount = frameCount + 1
    local now = tick()
    if now - lastCheckTime >= 1 then
        currentFPS = frameCount
        frameCount = 0
        lastCheckTime = now
    end
end

-- Update all ESP elements
local function UpdateESP()
    for object, espData in pairs(ESPObjects) do
        if not object or not object:IsDescendantOf(workspace) then
            -- Clean up if object no longer exists
            if espData.highlight then 
                espData.highlight:Destroy() 
                DebugPrint("Removed ESP because object no longer exists")
                if espData.type == "vehicle" then
                    totalVehiclesFound = totalVehiclesFound - 1
                end
            end
            ESPObjects[object] = nil
        else
            -- Check if ESP needs to be restored
            if not CheckAndRestoreESP(object, espData) then
                continue -- Skip this iteration if restore failed
            end
        end
    end
end

-- Scan specifically workspace.Vehicles for vehicles
local function ScanVehicles()
    local vehiclesFound = 0
    
    -- Check if workspace.Vehicles exists
    if not workspace:FindFirstChild("Vehicles") then
        DebugPrint("workspace.Vehicles path not found")
        return 0
    end
    
    -- Scan all vehicles in the Vehicles folder
    for _, vehicle in pairs(workspace.Vehicles:GetChildren()) do
        if not ESPObjects[vehicle] then
            CreateVehicleESP(vehicle)
            vehiclesFound = vehiclesFound + 1
        end
    end
    
    DebugPrint("Found " .. vehiclesFound .. " vehicles in Vehicles folder")
    return vehiclesFound
end

-- Add objects to scan queue
local function EnqueueForScan(objects)
    for _, obj in pairs(objects) do
        table.insert(scanQueue, obj)
    end
end

-- Process a chunk of the scan queue
local function ProcessScanChunk()
    if #scanQueue == 0 then
        chunkedScanActive = false
        return
    end
    
    chunkedScanActive = true
    local processed = 0
    
    -- Process a chunk of objects
    while processed < ESP.ChunkSize and #scanQueue > 0 do
        local obj = table.remove(scanQueue, 1)
        
        -- Check if it's a vehicle
        if not ESPObjects[obj] then
            CreateVehicleESP(obj)
        end
        
        processed = processed + 1
    end
end

-- Find all vehicles in Vehicles folder efficiently
local function QuickScanVehicles()
    scanQueue = {}
    
    -- Check if workspace.Vehicles exists
    if workspace:FindFirstChild("Vehicles") then
        -- Queue all vehicles children for scanning
        EnqueueForScan(workspace.Vehicles:GetChildren())
        DebugPrint("Queued " .. #scanQueue .. " vehicles for scanning")
    else
        DebugPrint("workspace.Vehicles path not found")
    end
    
    -- Start processing
    chunkedScanActive = true
end

-- Find players for ESP
local function FindPlayers()
    for _, player in pairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            CreatePlayerESP(player)
        end
    end
end

-- Ensure ESP container isn't deleted
game:GetService("CoreGui").ChildRemoved:Connect(function(child)
    if child == espContainer then
        DebugPrint("ESP container was removed, recreating...")
        espContainer = Instance.new("ScreenGui")
        espContainer.Name = "ESPContainer"
        espContainer.ResetOnSpawn = false
        espContainer.Parent = game:GetService("CoreGui")
        
        -- Recreate all ESPs
        for object, espData in pairs(ESPObjects) do
            if espData.type == "vehicle" and ESP.ShowVehicles then
                CreateVehicleESP(object)
            elseif espData.type == "player" and espData.player and ESP.ShowPlayers then
                CreatePlayerESP(espData.player)
            end
        end
    end
end)

-- Real-time ESP update function with optimization
local function RealTimeUpdate()
    if not ESP.Enabled then return end
    
    -- Update FPS counter
    UpdateFPS()
    
    -- Update existing ESP
    UpdateESP()
    
    -- Check if it's time for a full auto scan
    local currentTime = tick()
    if ESP.AutoFullScan and currentTime - lastFullUpdateTime >= ESP.CurrentInterval and not scannedThisSecond then
        -- Don't start a new scan if FPS is too low and lag-free mode is enabled
        if ESP.LagFreeMode and currentFPS < 30 and ESP.FastScanMode then
            DebugPrint("Skipping fast scan due to low FPS: " .. currentFPS)
            return
        end
        
        -- Mark that we've done a scan this second
        scannedThisSecond = true
        lastFullUpdateTime = currentTime
        
        -- Start a chunked scan
        QuickScanVehicles()
        FindPlayers() -- Players are fewer so we can scan them all at once
        
        -- Reset the flag after the update interval
        task.delay(ESP.CurrentInterval, function()
            scannedThisSecond = false
        end)
    end
    
    -- Process a chunk of the scan queue if active
    if chunkedScanActive then
        ProcessScanChunk()
    end
    
    -- Update status UI
    UpdateStatusUI()
end

-- Main update loop - use RenderStepped for efficient updates
RunService.RenderStepped:Connect(function()
    RealTimeUpdate()
end)

-- Watch for new vehicles in Vehicles folder
if workspace:FindFirstChild("Vehicles") then
    workspace.Vehicles.ChildAdded:Connect(function(vehicle)
        if not ESP.Enabled or not ESP.ShowVehicles then return end
        
        -- Create ESP for new vehicle with small delay to ensure model is loaded
        task.spawn(function()
            task.wait(0.1)
            CreateVehicleESP(vehicle)
        end)
    end)
end

-- Handle player joining
Players.PlayerAdded:Connect(function(player)
    DebugPrint("New player joined: " .. player.Name)
    -- Wait for character to load
    player.CharacterAdded:Connect(function(character)
        if ESP.Enabled and ESP.ShowPlayers then
            task.wait(0.5) -- Small delay to ensure character is fully loaded
            CreatePlayerESP(player)
        end
    end)
end)

-- Handle existing players' new characters
for _, player in pairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        player.CharacterAdded:Connect(function(character)
            if ESP.Enabled and ESP.ShowPlayers then
                task.wait(0.5) -- Small delay to ensure character is fully loaded
                CreatePlayerESP(player)
            end
        end)
    end
end

-- Create a compact status GUI similar to the image
local StatusGUI = Instance.new("ScreenGui")
StatusGUI.Name = "ESP_Status"
StatusGUI.ResetOnSpawn = false
StatusGUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
StatusGUI.Parent = game:GetService("CoreGui")

-- Create main frame
local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 150, 0, 110)
MainFrame.Position = UDim2.new(0, 10, 0, 10)
MainFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
MainFrame.BackgroundTransparency = 0.5
MainFrame.BorderSizePixel = 1
MainFrame.BorderColor3 = Color3.fromRGB(0, 170, 255)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = StatusGUI

-- Title
local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 20)
Title.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
Title.BackgroundTransparency = 0.2
Title.BorderSizePixel = 0
Title.Text = "ESP Status"
Title.TextColor3 = Color3.fromRGB(0, 170, 255)
Title.TextSize = 14
Title.Font = Enum.Font.SourceSansBold
Title.Parent = MainFrame

-- Function to create status labels
local function CreateStatusLabel(text, position, textColor)
    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, 0, 0, 18)
    Label.Position = position
    Label.BackgroundTransparency = 1
    Label.Text = text
    Label.TextColor3 = textColor or Color3.fromRGB(255, 255, 255)
    Label.TextSize = 14
    Label.Font = Enum.Font.SourceSans
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.TextYAlignment = Enum.TextYAlignment.Center
    Label.Parent = MainFrame
    return Label
end

-- Create status labels
local ScanLabel = CreateStatusLabel("Scan: 0.1s/1s", UDim2.new(0, 5, 0, 25))
local ESPLabel = CreateStatusLabel("ESP: ON", UDim2.new(0, 5, 0, 45), Color3.fromRGB(0, 255, 0))
local VehiclesLabel = CreateStatusLabel("Vehs: 0", UDim2.new(0, 5, 0, 65))
local FPSLabel = CreateStatusLabel("FPS: 60", UDim2.new(0, 5, 0, 85))

-- Function to update status UI
function UpdateStatusUI()
    -- Update scan rate
    ScanLabel.Text = "Scan: " .. (ESP.FastScanMode and "0.1s" or "1s")
    
    -- Update ESP status
    ESPLabel.Text = "ESP: " .. (ESP.Enabled and "ON" or "OFF")
    ESPLabel.TextColor3 = ESP.Enabled and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
    
    -- Update vehicles count
    local vehicleCount = 0
    for _, espData in pairs(ESPObjects) do
        if espData.type == "vehicle" then
            vehicleCount = vehicleCount + 1
        end
    end
    VehiclesLabel.Text = "Vehs: " .. vehicleCount
    
    -- Update FPS
    FPSLabel.Text = "FPS: " .. currentFPS
end

-- Function to toggle ESP with keyboard
local UserInputService = game:GetService("UserInputService")
UserInputService.InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.F3 then
        -- Toggle ESP
        ESP.Enabled = not ESP.Enabled
        
        -- Update status
        for _, espData in pairs(ESPObjects) do
            if espData.highlight then
                espData.highlight.Enabled = ESP.Enabled
            end
        end
    elseif input.KeyCode == Enum.KeyCode.F5 then
        -- Toggle vehicles
        ESP.ShowVehicles = not ESP.ShowVehicles
        
        for object, espData in pairs(ESPObjects) do
            if espData.type == "vehicle" and espData.highlight then
                espData.highlight.Enabled = ESP.Enabled and ESP.ShowVehicles
            end
        end
    elseif input.KeyCode == Enum.KeyCode.F6 then
        -- Toggle players
        ESP.ShowPlayers = not ESP.ShowPlayers
        
        for object, espData in pairs(ESPObjects) do
            if espData.type == "player" and espData.highlight then
                espData.highlight.Enabled = ESP.Enabled and ESP.ShowPlayers
            end
        end
    elseif input.KeyCode == Enum.KeyCode.F8 then
        -- Toggle scan rate
        ESP.FastScanMode = not ESP.FastScanMode
        
        if ESP.FastScanMode then
            ESP.CurrentInterval = ESP.FastUpdateInterval
        else
            ESP.CurrentInterval = ESP.UpdateInterval
        end
    end
end)

-- Initial run
scanQueue = {}
QuickScanVehicles()
FindPlayers()
lastFullUpdateTime = tick()
ESP.CurrentInterval = ESP.UpdateInterval -- Start with normal scan rate
DebugPrint("ESP System Initialized")
print("ESP System Initialized - Scanning workspace.Vehicles")
