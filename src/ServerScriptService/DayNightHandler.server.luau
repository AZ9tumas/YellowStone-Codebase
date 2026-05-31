--// Services
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
--// Variables
local Atmosphere = Lighting:WaitForChild("Atmosphere")
--^ Events
--^ Sounds
--^ Math Library
local clamp,inradian,sine,cosine = math.clamp,math.rad,math.sin,math.cos
--^ Tween Information
local TweenDetails = TweenInfo.new
 
--^ Day Variables
local CycleSpeed_Day = 45 --// Cycle speed is how long one hour takes during this time range, it is measured in seconds
local DayBrightness = 3.5 --// Brightness of the game during this time range
local DayAmbientColour: Color3 = Color3.fromRGB(42, 37, 34) -- // Ambient colour of the game during this time range
local DayColourshift_Top = Color3.fromRGB(208, 208, 208)
local DayOutdoorAmbient = Color3.fromRGB(216, 213, 255)
local DayAtmosphereDensity = 0.155
local DayAtmosphereColour = Color3.fromRGB(226, 226, 226)
local DayAtmosphereDecay = Color3.fromRGB(216, 213, 255)
local DayAtmosphereGlare = 0.36
local DayAtmosphereHaze = 2.14

--^ Night Variables
local CycleSpeed_Night = 45
local NightBrightness = 3.3
local NightAmbientColour: Color3 = Color3.fromRGB(74, 104, 161)
local NightColourshift_Top = Color3.fromRGB(121, 146, 255)
local NightOutdoorAmbient = Color3.fromRGB(0, 0, 0)
local NightAtmosphereDensity = 0.316
local NightAtmosphereColour = Color3.fromRGB(85, 90, 93)
local NightAtmosphereDecay = Color3.fromRGB(34, 37, 43)
local NightAtmosphereGlare = 0.26
local NightAtmosphereHaze = 2.11

--^ Dawn Variables
local CycleSpeed_Dawn = 45
local DawnBrightness = 3.2
local DawnAmbientColour: Color3 = Color3.fromRGB(42, 37, 34)
local DawnColourshift_Top = Color3.fromRGB(208, 192, 161)
local DawnOutdoorAmbient = Color3.fromRGB(147, 132, 109)
local DawnAtmosphereDensity = 0.155
local DawnAtmosphereColour = Color3.fromRGB(153, 255, 0)
local DawnAtmosphereDecay = Color3.fromRGB(216, 213, 255)
local DawnAtmosphereGlare = 0.36
local DawnAtmosphereHaze = 2.1

--^ Dusk Variables
local CycleSpeed_Dusk = 45
local DuskBrightness = 3.3
local DuskAmbientColour: Color3 = Color3.fromRGB(42, 37, 34)
local DuskColourshift_Top = Color3.fromRGB(208, 192, 161)
local DuskOutdoorAmbient = Color3.fromRGB(147, 132, 109)
local DuskAtmosphereDensity = 0.155
local DuskAtmosphereColour = Color3.fromRGB(153, 255, 0)
local DuskAtmosphereDecay = Color3.fromRGB(216, 213, 255)
local DuskAtmosphereGlare = 1.03
local DuskAtmosphereHaze = 2.1

--^ Early Morning Variables
local CycleSpeed_EarlyMorning = 45
local EarlyMorningBrightness = 3.3
local EarlyMorningAmbientColour: Color3 = Color3.fromRGB(42, 37, 34)
local EarlyMorningColourshift_Top = Color3.fromRGB(208, 192, 161)
local EarlyMorningOutdoorAmbient = Color3.fromRGB(147, 132, 109)
local EarlyMorningAtmosphereDensity = 0.155
local EarlyMorningAtmosphereColour = Color3.fromRGB(153, 255, 0)
local EarlyMorningAtmosphereDecay = Color3.fromRGB(216, 213, 255)
local EarlyMorningAtmosphereGlare = 1.03
local EarlyMorningAtmosphereHaze = 2.1

--^ Late Day Variables
local CycleSpeed_LateDay = 45
local LateDayBrightness = 3.3
local LateDayAmbientColour: Color3 = Color3.fromRGB(42, 37, 34)
local LateDayColourshift_Top = Color3.fromRGB(208, 192, 161)
local LateDayOutdoorAmbient = Color3.fromRGB(147, 132, 109)
local LateDayAtmosphereDensity = 0.155
local LateDayAtmosphereColour = Color3.fromRGB(153, 255, 0)
local LateDayAtmosphereDecay = Color3.fromRGB(216, 213, 255)
local LateDayAtmosphereGlare = 1.03
local LateDayAtmosphereHaze = 2.1

--^ Day/Night Variables
local CycleSpeed_Current = CycleSpeed_Day
--// Base Commands
--// Functions
function DayNight_Cycle()
	while true do
		local TimeInterpolation: Tween = TweenService:Create(Lighting,TweenDetails(CycleSpeed_Current),{ClockTime = Lighting.ClockTime + 1})
		TimeInterpolation:Play()
		TimeInterpolation.Completed:Wait()
		
		-- Current Time
		print(Lighting.ClockTime)
		
		-- Clocktime Events
		if Lighting.ClockTime == 20 then
			CycleSpeed_Current = CycleSpeed_Night
			TweenService:Create(Lighting,TweenDetails(30),{Brightness = NightBrightness, Ambient = NightAmbientColour, ColorShift_Top = NightColourshift_Top, OutdoorAmbient = NightOutdoorAmbient}):Play()
			TweenService:Create(Atmosphere,TweenDetails(30),{Density = NightAtmosphereDensity, Color = NightAtmosphereColour, Decay = NightAtmosphereDecay, Glare = NightAtmosphereGlare, Haze = NightAtmosphereHaze}):Play()
		end
		if Lighting.ClockTime == 5.3 then
			CycleSpeed_Current = CycleSpeed_EarlyMorning
			TweenService:Create(Lighting,TweenDetails(30),{Brightness = EarlyMorningBrightness, Ambient = EarlyMorningAmbientColour, ColorShift_Top = EarlyMorningColourshift_Top, OutdoorAmbient = EarlyMorningOutdoorAmbient}):Play()
			TweenService:Create(Atmosphere,TweenDetails(30),{Density = EarlyMorningAtmosphereDensity, Color = EarlyMorningAtmosphereColour, Decay = EarlyMorningAtmosphereDecay, Glare = EarlyMorningAtmosphereGlare, Haze = EarlyMorningAtmosphereHaze}):Play()
		end
		if Lighting.ClockTime == 6.1 then
			CycleSpeed_Current = CycleSpeed_Dawn
			TweenService:Create(Lighting,TweenDetails(30),{Brightness = DawnBrightness, Ambient = DawnAmbientColour, ColorShift_Top = DawnColourshift_Top, OutdoorAmbient = DawnOutdoorAmbient}):Play()
			TweenService:Create(Atmosphere,TweenDetails(30),{Density = DawnAtmosphereDensity, Color = DawnAtmosphereColour, Decay = DawnAtmosphereDecay, Glare = DawnAtmosphereGlare, Haze = DawnAtmosphereHaze}):Play()
		end
		if Lighting.ClockTime == 8 then
			CycleSpeed_Current = CycleSpeed_Day
			TweenService:Create(Lighting,TweenDetails(30),{Brightness = DayBrightness, Ambient = DayAmbientColour, ColorShift_Top = DayColourshift_Top, OutdoorAmbient = DayOutdoorAmbient}):Play()
			TweenService:Create(Atmosphere,TweenDetails(30),{Density = DayAtmosphereDensity, Color = DayAtmosphereColour, Decay = DayAtmosphereDecay, Glare = DayAtmosphereGlare, Haze = DayAtmosphereHaze}):Play()
		end
		if Lighting.ClockTime == 17.5 then
			CycleSpeed_Current = CycleSpeed_LateDay
			TweenService:Create(Lighting,TweenDetails(30),{Brightness = LateDayBrightness, Ambient = LateDayAmbientColour, ColorShift_Top = LateDayColourshift_Top, OutdoorAmbient = LateDayOutdoorAmbient}):Play()
			TweenService:Create(Atmosphere,TweenDetails(30),{Density = LateDayAtmosphereDensity, Color = LateDayAtmosphereColour, Decay = LateDayAtmosphereDecay, Glare = LateDayAtmosphereGlare, Haze = LateDayAtmosphereHaze}):Play()
		end
		if Lighting.ClockTime == 19.5 then
			CycleSpeed_Current = CycleSpeed_Dusk
			TweenService:Create(Lighting,TweenDetails(30),{Brightness = DuskBrightness, Ambient = DuskAmbientColour, ColorShift_Top = DuskColourshift_Top, OutdoorAmbient = DuskOutdoorAmbient}):Play()
			TweenService:Create(Atmosphere,TweenDetails(30),{Density = DuskAtmosphereDensity, Color = DuskAtmosphereColour, Decay = DuskAtmosphereDecay, Glare = DuskAtmosphereGlare, Haze = DuskAtmosphereHaze}):Play()
		end
		
	end
end
--// Connections
--// Coroutines
coroutine.wrap(DayNight_Cycle)()