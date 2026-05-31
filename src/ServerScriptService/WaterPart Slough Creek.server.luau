for _, part in ipairs(workspace["Slough Creek Water"]:GetChildren()) do
	if part:IsA("BasePart") then
		workspace.Terrain:FillBlock(
			part.CFrame,
			part.Size,
			Enum.Material.Water
		)
		part:Destroy()
	end
end