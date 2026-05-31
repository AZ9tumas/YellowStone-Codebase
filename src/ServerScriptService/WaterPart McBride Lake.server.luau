for _, part in ipairs(workspace["McBride Lake Water"]:GetChildren()) do
	if part:IsA("BasePart") then
		workspace.Terrain:FillBlock(
			part.CFrame,
			part.Size,
			Enum.Material.Water
		)
		part:Destroy()
	end
end