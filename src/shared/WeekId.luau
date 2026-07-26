--!strict
-- WeekId.luau — Numéro de semaine ISO 8601 courant (année ISO + semaine), utilisé comme suffixe
-- de clé pour les classements hebdomadaires (OrderedDataStore) ET pour l'affichage client
-- ("Semaine 2026-W31"). Semaine 1 = celle qui contient le premier jeudi de l'année (règle ISO).
-- Calcul basé sur UTC (os.date("!*t")) pour que tous les serveurs (peu importe leur région)
-- s'accordent sur la même semaine au même instant.

local WeekId = {}

local function isLeapYear(y: number): boolean
	return (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0)
end

-- Jour de semaine ISO (1=lundi..7=dimanche) du 1er janvier de l'année y.
local function jan1IsoWeekday(y: number): number
	local t = os.time({ year = y, month = 1, day = 1, hour = 12 })
	local wday = tonumber(os.date("!%w", t)) or 0 -- 0=dimanche..6=samedi
	return ((wday + 6) % 7) + 1
end

local function weeksInYear(y: number): number
	local p = jan1IsoWeekday(y)
	return (p == 4 or (isLeapYear(y) and p == 3)) and 53 or 52
end

-- Résout (année ISO, semaine ISO) pour une date donnée (année civile, jour de l'année 1-366,
-- jour de semaine ISO 1-7 de cette date). Gère les débordements aux deux bords de l'année
-- civile (ex. le 1er janvier peut appartenir à la semaine 52/53 de l'année précédente, et le
-- 31 décembre peut appartenir à la semaine 1 de l'année suivante).
local function computeIsoWeek(year: number, yday: number, isoWday: number): (number, number)
	local week = math.floor((yday - isoWday + 10) / 7)
	if week < 1 then
		return year - 1, weeksInYear(year - 1)
	end
	local total = weeksInYear(year)
	if week > total then
		return year + 1, 1
	end
	return year, week
end

-- Id stable pour la semaine ISO courante (UTC), ex. "2026-W31". Change automatiquement au
-- passage du lundi 00:00 UTC — c'est ce qui fait "repartir à zéro" les classements hebdo (une
-- nouvelle clé de store = un nouveau classement vide, l'ancienne reste intacte et consultable).
function WeekId.Current(): string
	local now = os.date("!*t")
	local isoWday = ((now.wday + 5) % 7) + 1 -- now.wday : 1=dimanche..7=samedi → 1=lundi..7=dimanche
	local year, week = computeIsoWeek(now.year, now.yday, isoWday)
	return string.format("%d-W%02d", year, week)
end

return WeekId
