local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
 

local Camera = workspace.CurrentCamera
local LocalPlayer = player

local ESP = {
    Enabled = true,
    OutlineColor = Color3.fromRGB(0,170,255),
    PlayerOutlineColor = Color3.fromRGB(255,0,0),
    OutlineTransparency = 0,
    FillTransparency = 1,
    TextEnabled = false,
    LineThickness = 3,
    UpdateInterval = 1,
    FastUpdateInterval = 0.1,
    CurrentInterval = 1,
    AutoRespawnESP = true,
    Debug = true,
    ShowVehicles = true,
    ShowPlayers = true,
    ScanFullWorkspace = false,
    AutoFullScan = true,
    ChunkSize = 10,
    LagFreeMode = true,
    FastScanMode = false
}

local ESPObjects = {}
local knownVehicleClasses = {}
local lastFullUpdateTime = 0
local lastFPSCheckTime = 0
local currentFPS = 60
local scanQueue = {}
local chunkedScanActive = false
local scannedThisSecond = false
local totalVehiclesFound = 0

local function DebugPrint(message)
    if ESP.Debug then
        print("[ESP Debug] " .. message)
    end
end

local espContainer = Instance.new("ScreenGui")
espContainer.Name = "ESPContainer"
espContainer.ResetOnSpawn = false
espContainer.Parent = game:GetService("CoreGui")

local function LooksLikeVehicle(obj)
    if not obj:IsA("Model") then return false end
    if Players:GetPlayerFromCharacter(obj) then return false end
    local className = obj.ClassName
    if knownVehicleClasses[className] then return true end
    local vehicleIndicators = {
        "Body","Chassis","Engine","Wheels","Seats","Seat","VehicleSeat",
        "Tank","Turret","Gun","Cannon","Track","Tracks","Vehicle","Car",
        "Handle","SteeringWheel","Exhaust","Hull","Main","Model"
    }
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
    for _, indicatorName in ipairs(vehicleIndicators) do
        if obj:FindFirstChild(indicatorName) then
            knownVehicleClasses[className] = true
            return true
        end
    end
    for _, child in pairs(obj:GetChildren()) do
        if child:IsA("VehicleSeat") or
           child:IsA("Model") and (child.Name:lower():find("seat") or child.Name:lower():find("driver")) or
           child:IsA("Configuration") or
           child:IsA("Model") and (child.Name:lower():find("wheel") or child.Name:lower():find("turret")) then
            knownVehicleClasses[className] = true
            return true
        end
    end
    if obj.PrimaryPart and obj.PrimaryPart:IsA("BasePart") then
        local size = obj.PrimaryPart.Size
        if (size.X > 5 or size.Y > 5 or size.Z > 5) and #obj:GetChildren() > 3 then
            knownVehicleClasses[className] = true
            return true
        end
    end
    for _, child in pairs(obj:GetDescendants()) do
        if child:IsA("HingeConstraint") or child:IsA("BallSocketConstraint") or child:IsA("SpringConstraint") then
            knownVehicleClasses[className] = true
            return true
        end
    end
    return false
end

local function CreateHighlight(target, color)
    local highlight = Instance.new("Highlight")
    highlight.FillColor = color
    highlight.OutlineColor = color
    highlight.FillTransparency = ESP.FillTransparency
    highlight.OutlineTransparency = ESP.OutlineTransparency
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Adornee = target
    pcall(function()
        highlight.OutlineSize = ESP.LineThickness
    end)
    highlight.Parent = espContainer
    highlight:GetPropertyChangedSignal("Enabled"):Connect(function()
        if not highlight.Enabled and ESP.Enabled then
            highlight.Enabled = true
        end
    end)
    highlight:GetPropertyChangedSignal("OutlineTransparency"):Connect(function()
        if highlight.OutlineTransparency > ESP.OutlineTransparency and ESP.Enabled then
            highlight.OutlineTransparency = ESP.OutlineTransparency
        end
    end)
    highlight:GetPropertyChangedSignal("DepthMode"):Connect(function()
        if highlight.DepthMode ~= Enum.HighlightDepthMode.AlwaysOnTop and ESP.Enabled then
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        end
    end)
    return highlight
end

local function CreateVehicleESP(vehicle)
    if not vehicle or not vehicle.Parent then return end
    if not vehicle:IsA("Model") then return end
    if not ESP.ShowVehicles then return end
    if ESPObjects[vehicle] then return end
    local highlight = CreateHighlight(vehicle, ESP.OutlineColor)
    ESPObjects[vehicle] = {highlight = highlight, type = "vehicle", lastCheck = tick(), created = tick()}
    totalVehiclesFound = totalVehiclesFound + 1
    DebugPrint("Created ESP for vehicle: " .. vehicle.Name)
    return ESPObjects[vehicle]
end

local function CreatePlayerESP(plr)
    if plr == LocalPlayer then return end
    if not ESP.ShowPlayers then return end
    local character = plr.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then return end
    if ESPObjects[character] then return end
    local highlight = CreateHighlight(character, ESP.PlayerOutlineColor)
    ESPObjects[character] = {highlight = highlight, player = plr, type = "player", lastCheck = tick(), created = tick()}
    DebugPrint("Created ESP for player: " .. plr.Name)
    return ESPObjects[character]
end

local function CheckAndRestoreESP(object, espData)
    if not espData or not espData.highlight then return false end
    local now = tick()
    if now - espData.lastCheck < 1 then return true end
    espData.lastCheck = now
    local needsRestore = false
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
    if needsRestore and ESP.AutoRespawnESP then
        if espData.highlight then espData.highlight:Destroy() end
        if espData.type == "vehicle" and ESP.ShowVehicles then
            ESPObjects[object] = nil
            CreateVehicleESP(object)
            return true
        elseif espData.type == "player" and espData.player and ESP.ShowPlayers then
            ESPObjects[object] = nil
            CreatePlayerESP(espData.player)
            return true
        end
        return false
    end
    return true
end

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

local function UpdateESP()
    for object, espData in pairs(ESPObjects) do
        if not object or not object:IsDescendantOf(workspace) then
            if espData.highlight then
                espData.highlight:Destroy()
                DebugPrint("Removed ESP because object no longer exists")
                if espData.type == "vehicle" then
                    totalVehiclesFound = totalVehiclesFound - 1
                end
            end
            ESPObjects[object] = nil
        else
            if not CheckAndRestoreESP(object, espData) then
                continue
            end
        end
    end
end

local function ScanVehicles()
    local vehiclesFound = 0
    if not workspace:FindFirstChild("Vehicles") then
        DebugPrint("workspace.Vehicles path not found")
        return 0
    end
    for _, vehicle in pairs(workspace.Vehicles:GetChildren()) do
        if not ESPObjects[vehicle] then
            CreateVehicleESP(vehicle)
            vehiclesFound = vehiclesFound + 1
        end
    end
    DebugPrint("Found " .. vehiclesFound .. " vehicles in Vehicles folder")
    return vehiclesFound
end

local function EnqueueForScan(objects)
    for _, obj in pairs(objects) do
        table.insert(scanQueue, obj)
    end
end

local function ProcessScanChunk()
    if #scanQueue == 0 then
        chunkedScanActive = false
        return
    end
    chunkedScanActive = true
    local processed = 0
    while processed < ESP.ChunkSize and #scanQueue > 0 do
        local obj = table.remove(scanQueue, 1)
        if not ESPObjects[obj] then
            CreateVehicleESP(obj)
        end
        processed = processed + 1
    end
end

local function QuickScanVehicles()
    scanQueue = {}
    if workspace:FindFirstChild("Vehicles") then
        EnqueueForScan(workspace.Vehicles:GetChildren())
        DebugPrint("Queued " .. #scanQueue .. " vehicles for scanning")
    else
        DebugPrint("workspace.Vehicles path not found")
    end
    chunkedScanActive = true
end

local function FindPlayers()
    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            CreatePlayerESP(plr)
        end
    end
end

game:GetService("CoreGui").ChildRemoved:Connect(function(child)
    if child == espContainer then
        DebugPrint("ESP container was removed, recreating...")
        espContainer = Instance.new("ScreenGui")
        espContainer.Name = "ESPContainer"
        espContainer.ResetOnSpawn = false
        espContainer.Parent = game:GetService("CoreGui")
        for object, espData in pairs(ESPObjects) do
            if espData.type == "vehicle" and ESP.ShowVehicles then
                CreateVehicleESP(object)
            elseif espData.type == "player" and espData.player and ESP.ShowPlayers then
                CreatePlayerESP(espData.player)
            end
        end
    end
end)

local function RealTimeUpdate()
    if not ESP.Enabled then return end
    UpdateFPS()
    UpdateESP()
    local currentTime = tick()
    if ESP.AutoFullScan and currentTime - lastFullUpdateTime >= ESP.CurrentInterval and not scannedThisSecond then
        if ESP.LagFreeMode and currentFPS < 30 and ESP.FastScanMode then
            DebugPrint("Skipping fast scan due to low FPS: " .. currentFPS)
            return
        end
        scannedThisSecond = true
        lastFullUpdateTime = currentTime
        QuickScanVehicles()
        FindPlayers()
        task.delay(ESP.CurrentInterval, function()
            scannedThisSecond = false
        end)
    end
    if chunkedScanActive then
        ProcessScanChunk()
    end
    UpdateStatusUI()
end

RunService.RenderStepped:Connect(function()
    RealTimeUpdate()
end)

if workspace:FindFirstChild("Vehicles") then
    workspace.Vehicles.ChildAdded:Connect(function(vehicle)
        if not ESP.Enabled or not ESP.ShowVehicles then return end
        task.spawn(function()
            task.wait(0.1)
            CreateVehicleESP(vehicle)
        end)
    end)
end

Players.PlayerAdded:Connect(function(plr)
    DebugPrint("New player joined: " .. plr.Name)
    plr.CharacterAdded:Connect(function(character)
        if ESP.Enabled and ESP.ShowPlayers then
            task.wait(0.5)
            CreatePlayerESP(plr)
        end
    end)
end)

for _, plr in pairs(Players:GetPlayers()) do
    if plr ~= LocalPlayer then
        plr.CharacterAdded:Connect(function(character)
            if ESP.Enabled and ESP.ShowPlayers then
                task.wait(0.5)
                CreatePlayerESP(plr)
            end
        end)
    end
end

local StatusGUI = Instance.new("ScreenGui")
StatusGUI.Name = "ESP_Status"
StatusGUI.ResetOnSpawn = false
StatusGUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
StatusGUI.Parent = game:GetService("CoreGui")

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0,150,0,110)
MainFrame.Position = UDim2.new(0,10,0,10)
MainFrame.BackgroundColor3 = Color3.fromRGB(0,0,0)
MainFrame.BackgroundTransparency = 0.5
MainFrame.BorderSizePixel = 1
MainFrame.BorderColor3 = Color3.fromRGB(0,170,255)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = StatusGUI

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1,0,0,20)
Title.BackgroundColor3 = Color3.fromRGB(0,0,0)
Title.BackgroundTransparency = 0.2
Title.BorderSizePixel = 0
Title.Text = "ESP Status"
Title.TextColor3 = Color3.fromRGB(0,170,255)
Title.TextSize = 14
Title.Font = Enum.Font.SourceSansBold
Title.Parent = MainFrame

local function CreateStatusLabel(text, position, textColor)
    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1,0,0,18)
    Label.Position = position
    Label.BackgroundTransparency = 1
    Label.Text = text
    Label.TextColor3 = textColor or Color3.fromRGB(255,255,255)
    Label.TextSize = 14
    Label.Font = Enum.Font.SourceSans
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.TextYAlignment = Enum.TextYAlignment.Center
    Label.Parent = MainFrame
    return Label
end

local ScanLabel = CreateStatusLabel("Scan: 0.1s/1s", UDim2.new(0,5,0,25))
local ESPLabel = CreateStatusLabel("ESP: ON", UDim2.new(0,5,0,45), Color3.fromRGB(0,255,0))
local VehiclesLabel = CreateStatusLabel("Vehs: 0", UDim2.new(0,5,0,65))
local FPSLabel = CreateStatusLabel("FPS: 60", UDim2.new(0,5,0,85))

function UpdateStatusUI()
    ScanLabel.Text = "Scan: " .. (ESP.FastScanMode and "0.1s" or "1s")
    ESPLabel.Text = "ESP: " .. (ESP.Enabled and "ON" or "OFF")
    ESPLabel.TextColor3 = (ESP.Enabled and Color3.fromRGB(0,255,0) or Color3.fromRGB(255,0,0))
    local vehicleCount = 0
    for _, espData in pairs(ESPObjects) do
        if espData.type == "vehicle" then
            vehicleCount = vehicleCount + 1
        end
    end
    VehiclesLabel.Text = "Vehs: " .. vehicleCount
    FPSLabel.Text = "FPS: " .. currentFPS
end

local UserInputService = game:GetService("UserInputService")
UserInputService.InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.F3 then
        ESP.Enabled = not ESP.Enabled
        for _, espData in pairs(ESPObjects) do
            if espData.highlight then
                espData.highlight.Enabled = ESP.Enabled
            end
        end
    elseif input.KeyCode == Enum.KeyCode.F5 then
        ESP.ShowVehicles = not ESP.ShowVehicles
        for object, espData in pairs(ESPObjects) do
            if espData.type == "vehicle" and espData.highlight then
                espData.highlight.Enabled = ESP.Enabled and ESP.ShowVehicles
            end
        end
    elseif input.KeyCode == Enum.KeyCode.F6 then
        ESP.ShowPlayers = not ESP.ShowPlayers
        for object, espData in pairs(ESPObjects) do
            if espData.type == "player" and espData.highlight then
                espData.highlight.Enabled = ESP.Enabled and ESP.ShowPlayers
            end
        end
    elseif input.KeyCode == Enum.KeyCode.F8 then
        ESP.FastScanMode = not ESP.FastScanMode
        if ESP.FastScanMode then
            ESP.CurrentInterval = ESP.FastUpdateInterval
        else
            ESP.CurrentInterval = ESP.UpdateInterval
        end
    end
end)

scanQueue = {}
QuickScanVehicles()
FindPlayers()
lastFullUpdateTime = tick()
ESP.CurrentInterval = ESP.UpdateInterval
DebugPrint("ESP System Initialized")
print("ESP System Initialized - Scanning workspace.Vehicles")

-- Mod loop (Penetration 9999999999 + OverheatMult 9999999999 для AP/APHE)
local TARGET_PEN = 9999999999
local TARGET_OVERHEAT = 9999999999
spawn(function()
    while true do
        for _, obj in pairs(workspace.Vehicles:GetChildren()) do
            if obj.Name:find(player.Name) or obj.Name:find("Chassis") then
                local gun = obj:FindFirstChild("Gun", true)
                if gun then
                    local config = gun:FindFirstChild("Config", true)
                    if config then
                        local overheat = config:FindFirstChild("OverheatMult")
                        if overheat and (overheat:IsA("IntValue") or overheat:IsA("NumberValue")) then
                            overheat.Value = TARGET_OVERHEAT
                        end
                        local shells = config:FindFirstChild("Shells", true)
                        if shells then
                            for _, shellName in ipairs({"AP", "APHE"}) do
                                local shell = shells:FindFirstChild(shellName)
                                if shell then
                                    local pen = shell:FindFirstChild("Penetration")
                                    if pen and (pen:IsA("IntValue") or pen:IsA("NumberValue")) then
                                        pen.Value = TARGET_PEN
                                    end
                                    local conf = shell:FindFirstChild("Configuration")
                                    if conf then
                                        local pen2 = conf:FindFirstChild("Penetration")
                                        if pen2 then
                                            pen2.Value = TARGET_PEN
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        wait(0.5)
    end
end)

-- CTS — INSTANT SHELL + MAX PEN (2025)
-- Работает на любом танке, даже если переименовали

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer

local TARGET_PEN = 9999999999
local TARGET_SPEED = 9999999999   -- мгновенный полёт

spawn(function()
    while true do
        for _, tank in pairs(Workspace.Vehicles:GetChildren()) do
            -- Твой танк (по нику или части имени)
            if tank.Name:find(player.Name) or tank.Name:find("MysticPhoenix201975") or tank.Name:find("Chassis") then
                
                local gun = tank:FindFirstChild("Gun", true)
                if gun then
                    local config = gun:FindFirstChild("Config", true)
                    if config then
                        local shells = config:FindFirstChild("Shells", true)
                        if shells then
                            for _, shell in pairs(shells:GetChildren()) do
                                -- Пробитие
                                local pen = shell:FindFirstChild("Penetration")
                                if pen then pen.Value = TARGET_PEN end
                                
                                local conf = shell:FindFirstChild("Configuration")
                                if conf then
                                    local pen2 = conf:FindFirstChild("Penetration")
                                    if pen2 then pen2.Value = TARGET_PEN end
                                end

                                -- СКОРОСТЬ СНАРЯДА (главное)
                                local speed = shell:FindFirstChild("ShellSpeed")
                                if speed then speed.Value = TARGET_SPEED end
                                
                                if conf then
                                    local speed2 = conf:FindFirstChild("ShellSpeed")
                                    if speed2 then speed2.Value = TARGET_SPEED end
                                end
                            end
                        end
                    end
                end
            end
        end
        task.wait(0.2)
    end
end)

print("INSTANT SHELL + MAX PEN АКТИВЕН — пуля прилетает мгновенно и пробивает всё")
