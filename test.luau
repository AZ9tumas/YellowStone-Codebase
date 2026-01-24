-- export_classic_with_meta.lua
-- Classic Rojo export + init.meta.json everywhere.

local remodel = require("./remodel")

-- ========= CONFIG =========
local PLACE_PATH = "./BighornTest.rbxl"  -- or .rbxl
local SRC_ROOT   = "src"

-- Exported services (tweak as needed)
local SERVICE_NAMES = {
    "ReplicatedStorage",
    "ServerScriptService",
    "ServerStorage",
    "ReplicatedFirst",
    "StarterGui",
    "StarterPack",
    "StarterPlayer", -- special handling for SPS/SCS
    "Workspace",
    "Lighting",
    "SoundService",
    "Chat",
    "TextChatService",
    "Players",
}

-- Meta payload (exact as requested)
local META_JSON = [[
{
  "ignoreUnknownInstances": true
}
]]

local function generateMetaJson(className)
    if className then
        return [[
{
  "className": "]] .. className .. [[",
  "ignoreUnknownInstances": true
}
]]
    else
        return META_JSON
    end
end

-- ========= UTIL =========
local function sanitize(name)
    local s = name:gsub("[/%\\:*?\"<>|]", "_")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then s = "Unnamed" end
    return s
end

local function extFor(className)
    if className == "Script" then return "server.luau"
    elseif className == "LocalScript" then return "client.luau"
    else return "luau" end -- ModuleScript
end

local function safeRead(path)
    local ok, res = pcall(function() return remodel.readFile(path) end)
    if ok then return res end
    return nil
end

local function writeFile(path, contents)
    remodel.writeFile(path, contents or "")
end

-- cache dirs so we only write meta once per directory
local createdDirs = {}

local function ensureMeta(dirPath, className)
    local metaPath = dirPath .. "/init.meta.json"
    if not safeRead(metaPath) then
        writeFile(metaPath, generateMetaJson(className))
    end
end

local function ensureDirWithMeta(dirPath, className)
    if createdDirs[dirPath] then return end
    remodel.createDirAll(dirPath)
    ensureMeta(dirPath, className)
    createdDirs[dirPath] = true
end

local function fileExists(path)
    local ok = pcall(function() remodel.readFile(path) end)
    return ok
end

local function uniquePath(path)
    if not fileExists(path) then return path end
    local base, ext = path:match("^(.*)%.([%w%.]+)$")
    if not base then base, ext = path, "" end
    local n = 2
    while true do
        local try = ext ~= "" and (base .. "_" .. n .. "." .. ext) or (base .. "_" .. n)
        if not fileExists(try) then return try end
        n += 1
    end
end

local function hasChildScript(inst)
    for _, ch in ipairs(inst:GetChildren()) do
        local c = ch.ClassName
        if c == "Script" or c == "LocalScript" or c == "ModuleScript" then
            return true
        end
    end
    return false
end

-- Build on-disk directory mirroring parent chain within a service subtree
local function dirFor(gameRoot, serviceRoot, serviceBasePath, inst)
    local parts = {}
    local cur = inst.Parent
    while cur and cur ~= gameRoot and cur ~= serviceRoot do
        table.insert(parts, 1, sanitize(cur.Name))
        cur = cur.Parent
    end
    local dir = serviceBasePath
    ensureDirWithMeta(dir) -- service base
    for _, p in ipairs(parts) do
        dir = dir .. "/" .. p
        ensureDirWithMeta(dir) -- EVERY intermediate dir gets meta
    end
    return dir
end

-- Write a single script into dir; if it has child scripts, create folder + init.<ext>
local function writeScriptInto(dir, inst)
    ensureDirWithMeta(dir)
    local name = sanitize(inst.Name)
    local ext  = extFor(inst.ClassName)
    local src  = inst.Source or "-- empty"
    local toInit = hasChildScript(inst)

    if toInit then
        local folder = dir .. "/" .. name
        ensureDirWithMeta(folder, inst.ClassName) -- meta with className for the script folder
        local initPath = folder .. "/init." .. ext
        writeFile(initPath, src)
        return folder
    else
        local filePath = uniquePath(dir .. "/" .. name .. "." .. ext)
        writeFile(filePath, src)
        return nil
    end
end

-- Export scripts under a container (service or subtree), preserving parent chains
local function exportScriptsUnder(gameRoot, serviceRoot, serviceBasePath, container)
    ensureDirWithMeta(serviceBasePath)
    for _, inst in ipairs(container:GetDescendants()) do
        local cls = inst.ClassName
        if cls == "Script" or cls == "LocalScript" or cls == "ModuleScript" then
            local targetDir = dirFor(gameRoot, serviceRoot, serviceBasePath, inst)
            writeScriptInto(targetDir, inst)
            -- No special recursion needed: GetDescendants covers nested scripts.
        end
    end
end

-- StarterPlayer handling (SPS & SCS subtrees)
local function exportStarterPlayer(gameRoot, sp, base)
    ensureDirWithMeta(base)
    local sps = sp:FindFirstChild("StarterPlayerScripts")
    local scs = sp:FindFirstChild("StarterCharacterScripts")

    if sps then
        local spsBase = base .. "/StarterPlayerScripts"
        exportScriptsUnder(gameRoot, sps, spsBase, sps)
    end
    if scs then
        local scsBase = base .. "/StarterCharacterScripts"
        exportScriptsUnder(gameRoot, scs, scsBase, scs)
    end
end

-- ========= EXECUTE =========
print("[Remodel] Reading place: " .. PLACE_PATH)
local game = remodel.readPlaceFile(PLACE_PATH)

ensureDirWithMeta(SRC_ROOT)

for _, svcName in ipairs(SERVICE_NAMES) do
    local service
    local ok = pcall(function() service = game:GetService(svcName) end)
    if not ok or service == nil then
        service = game:FindFirstChild(svcName)
    end

    if service then
        local base = SRC_ROOT .. "/" .. svcName
        ensureDirWithMeta(base)

        if svcName == "StarterPlayer" then
            exportStarterPlayer(game, service, base)
        else
            exportScriptsUnder(game, service, base, service)
        end

        print(("[Remodel] Exported %-20s → %s"):format(svcName, base))
    end
end

print("[Remodel] Export complete with init.meta.json in every directory → src/<Service>/…")
