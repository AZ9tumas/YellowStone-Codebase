--// Services
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

--// Variables
local Player = Players.LocalPlayer
local HumanoidRootPart: BasePart = Player.Character:FindFirstChild("HumanoidRootPart")

local LocalFootstepSFX_Table: {Sound} = {}

--\\ Control Module
local ControlModule = require(Player.PlayerScripts:WaitForChild("PlayerModule"):WaitForChild("ControlModule"))

--// Events
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local FootstepEvent: RemoteEvent = Remotes:WaitForChild("FootstepEvent")

--// Functions
function IsPlayerMoving(): boolean
	local moveVector = ControlModule:GetMoveVector()
	return moveVector.Magnitude > 0
end

function GetMaterial()
	local RaycastParams = RaycastParams.new()
	RaycastParams.FilterType = Enum.RaycastFilterType.Include
	RaycastParams.FilterDescendantsInstances = {Workspace.Terrain}
	
	local raycastResult = Workspace:Raycast(Player.Character:FindFirstChild("HumanoidRootPart").Position, Vector3.new(0, -5, 0), RaycastParams)
	if raycastResult then
		print(raycastResult.Material)
		return raycastResult.Material
	end
end

function GetSound(material: Enum.Material)
	local UnderfootMaterial = GetMaterial()
	if UnderfootMaterial then
		FootstepEvent:FireServer(UnderfootMaterial, Player.Character:FindFirstChild("HumanoidRootPart"), LocalFootstepSFX_Table)
	end
end

--// Commands
if HumanoidRootPart then
	for _,v in HumanoidRootPart:GetChildren() do
		if v:GetAttribute("Sound") then
			table.insert(LocalFootstepSFX_Table,v)
		end
	end
else
	warn("No HumanoidRootPart found inside this character model.")
end

--// Connections
coroutine.wrap(function()
	while task.wait(0.4) do
		if IsPlayerMoving() then
			GetSound()
		end
	end
end)()