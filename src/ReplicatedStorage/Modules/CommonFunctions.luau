local CommonFunctions = {}

function CommonFunctions.LinearInterpolation(StartValue: number, EndValue: number, Percent: number): number
	if Percent <= 1 and Percent >= 0 then
		return StartValue + (EndValue - StartValue) * Percent
	else
		warn("Percent must be between 0 and 1")
	end
end

return CommonFunctions