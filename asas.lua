local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer
local ESP_COLOR = Color3.fromRGB(173, 216, 230)  -- Светло-голубой
local OUTLINE_COLOR = Color3.fromRGB(0, 191, 255)  -- Голубой outline
local TANK_NAME = "ChassisBaBFT_100k3A"  -- Исключаем свой танк
local highlighted = {}

local function addESP(obj)
    if highlighted[obj] or obj.Name == TANK_NAME or obj.Name:find(player.Name) then return end
    if obj:IsA("Model") or obj:IsA("Folder") or obj:IsA("BasePart") then
        local hl = Instance.new("Highlight")
        hl.Adornee = obj
        hl.FillColor = ESP_COLOR
        hl.OutlineColor = OUTLINE_COLOR
        hl.FillTransparency = 1
        hl.OutlineTransparency = 0
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = game.CoreGui
        highlighted[obj] = hl
    end
end

-- ESP loop
RunService.Heartbeat:Connect(function()
    local vehicles = workspace:FindFirstChild("Vehicles")
    local vehiclesGarage = workspace:FindFirstChild("VehiclesGarage")
    
    for obj, hl in pairs(highlighted) do
        if not obj:IsDescendantOf(workspace) then
            hl:Destroy()
            highlighted[obj] = nil
        end
    end
    
    if vehicles then
        for _, v in ipairs(vehicles:GetChildren()) do
            addESP(v)
        end
    end
    
    if vehiclesGarage then
        for _, v in ipairs(vehiclesGarage:GetChildren()) do
            addESP(v)
        end
    end
end)

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
