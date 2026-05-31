--// Services
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

--// Variables

--\\ Modules
local CommonFunctions = require(ReplicatedStorage.Modules.CommonFunctions)

--// Events
local Remotes = ReplicatedStorage.Remotes
local FootstepEvent: RemoteEvent = Remotes.FootstepEvent

--// Functions

--// Connections
FootstepEvent.OnServerEvent:Connect(function(Player, UnderfootMaterial, HumanoidRootPart: BasePart, LocalFootstepSFX_Table: {Sound})
	
	if UnderfootMaterial then
		for _,v in HumanoidRootPart:GetChildren() do
			if v:GetAttribute("FootstepSFX") then
				print(v)
				table.insert(LocalFootstepSFX_Table,v)
			else
				warn("no sound attribute")
			end
		end
		if LocalFootstepSFX_Table then
			local FootstepSFX_Types = {
				[Enum.Material.Grass] = "Grass",
				[Enum.Material.LeafyGrass] = "Grass"
			}
			local FootstepSFX_SelectedSounds: {Sound} = {}
			for _,v in LocalFootstepSFX_Table do
				if v:GetAttribute(FootstepSFX_Types[UnderfootMaterial]) then
					table.insert(FootstepSFX_SelectedSounds,v)
				end
			end
			print(LocalFootstepSFX_Table, " selected table")
			
			--\\ This randomly selects a sound from the given folder and plays it
			if FootstepSFX_SelectedSounds then
				local SelectedSound: Sound = FootstepSFX_SelectedSounds[math.random(1,#FootstepSFX_SelectedSounds)]
				print(SelectedSound, " selected sound")
				print((HumanoidRootPart.AssemblyLinearVelocity.Magnitude*100)/100)
				SelectedSound.PlaybackSpeed = CommonFunctions.LinearInterpolation(1,4.5,math.floor(HumanoidRootPart.AssemblyLinearVelocity.Magnitude)/100)
				SelectedSound.RollOffMaxDistance = math.floor(HumanoidRootPart.AssemblyLinearVelocity.Magnitude)*4
				SelectedSound:Play()
			else
				warn("This value is false or nil.")
			end
		else
			warn("Folder not found.")
		end
	end
end)