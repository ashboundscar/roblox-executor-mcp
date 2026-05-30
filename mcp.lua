-- Roblox Executor MCP Client (HTTP Polling Mode) - Ultra Stable Version
local HttpService = game:GetService("HttpService")

-- Configuration
local SETTINGS = {
    SERVER_URL = "http://localhost:8080",
    ENABLE_REMOTE_HOOKS = false, -- Toggle Remote Event/Function logging
    POLL_INTERVAL = 0.5,        -- Polling delay in seconds
    MAX_LOGS = 300              -- Maximum number of logs to keep
}

-- Remote Logging Storage
local RemoteLogs = {}
local MaxLogs = SETTINGS.MAX_LOGS
local PageSize = 30

local function getObjectFromPath(path)
    if path == "game" then return game end
    local parts = path:split(".")
    local current = game
    
    local startIdx = 1
    if parts[1] == "game" then startIdx = 2 end
    for i = startIdx, #parts do
        local name = parts[i]
        local success, nextObj = pcall(function() return current:FindFirstChild(name) end)
        if not success or not nextObj then
            local s, service = pcall(function() return game:GetService(name) end)
            if s and service then nextObj = service else return nil, "Could not find child: " .. name end
        end
        current = nextObj
    end
    return current
end

local function listChildren(path)
    local obj, err = getObjectFromPath(path)
    if not obj then return {error = err} end
    local children = {}
    pcall(function()
        for _, child in ipairs(obj:GetChildren()) do
            table.insert(children, {
                name = child.Name,
                className = child.ClassName,
                path = path .. "." .. child.Name
            })
        end
    end)
    return children
end

local function inspectObject(path)
    local obj, err = getObjectFromPath(path)
    if not obj then return {error = err} end

    local details = {
        name = obj.Name,
        className = obj.ClassName,
        parent = obj.Parent and obj.Parent.Name or "nil",
        fullName = obj:GetFullName(),
        childrenCount = #obj:GetChildren(),
        properties = {},
        attributes = obj:GetAttributes(),
        tags = game:GetService("CollectionService"):GetTags(obj)
    }

    local propertyList = {
        "Name", "ClassName", "Parent", "Position", "Size", "Rotation", "Orientation", "Color", 
        "Transparency", "Reflectance", "Material", "Anchored", "CanCollide", "CanTouch", 
        "CanQuery", "CastShadow", "Shape", "Text", "TextColor3", "TextSize", "Font", 
        "Value", "Enabled", "Visible", "ZIndex", "Health", "MaxHealth", "WalkSpeed", 
        "JumpPower", "JumpHeight", "Sit", "PlatformStand", "AutoRotate", "UseJumpPower", 
        "UserId", "AccountAge", "Team", "TeamColor", "Neutral", "Brightness", "Range", 
        "Shadows", "ClockTime", "TimeOfDay", "FogColor", "FogEnd", "FogStart", 
        "GlobalShadows", "Gravity", "FallenPartsDestroyHeight", "Source", "Disabled", 
        "AssetId", "AnimationId", "SoundId", "Volume", "PlaybackSpeed", "Playing", 
        "Looped", "TimePosition", "TextureId", "MeshId", "Scale", "Offset", "VertexColor",
        "DisplayDistanceType", "HealthDisplayDistance", "NameDisplayDistance", "HealthDisplayType",
        "CollisionGroupId", "Mass", "CenterOfMass", "AssemblyLinearVelocity", "AssemblyAngularVelocity"
    }

    if gethiddenproperties then
        pcall(function()
            local hp = gethiddenproperties(obj)
            if typeof(hp) == "table" then
                for k, v in pairs(hp) do
                    details.properties[k] = tostring(v)
                end
            end
        end)
    end

    for _, prop in ipairs(propertyList) do
        pcall(function()
            local val = obj[prop]
            if val ~= nil then
                if typeof(val) == "Vector3" then
                    details.properties[prop] = string.format("%.3f, %.3f, %.3f", val.X, val.Y, val.Z)
                elseif typeof(val) == "Color3" then
                    details.properties[prop] = string.format("RGB(%d, %d, %d)", val.R*255, val.G*255, val.B*255)
                elseif typeof(val) == "Instance" then
                    details.properties[prop] = val:GetFullName()
                elseif typeof(val) == "EnumItem" then
                    details.properties[prop] = tostring(val)
                else
                    details.properties[prop] = tostring(val)
                end
            end
        end)
    end

    return details
end

local function runLua(code)
    local func, err = loadstring(code)
    if not func then return {error = "Loadstring error: " .. tostring(err)} end
    local success, result = pcall(func)
    if not success then return {error = "Runtime error: " .. tostring(result)} end
    return {result = tostring(result)}
end

local function decompileScript(path)
    local obj, err = getObjectFromPath(path)
    if not obj then return {error = err} end
    if not obj:IsA("LuaSourceContainer") then return {error = "Object is not a script"} end
    local success, source = pcall(decompile, obj)
    if not success then return {error = "Decompilation failed: " .. tostring(source)} end
    return {source = source}
end

-- Remote Logger Tools
local function getRemoteList()
    local stats = {}
    for _, log in ipairs(RemoteLogs) do
        stats[log.name] = (stats[log.name] or 0) + 1
    end
    return stats
end

local function getRemoteLogs(params)
    local page = params.page or 1
    local nameFilter = params.name
    local filtered = {}
    for i = #RemoteLogs, 1, -1 do
        local log = RemoteLogs[i]
        if not nameFilter or log.name:find(nameFilter) then
            table.insert(filtered, log)
        end
    end
    local total = #filtered
    local start = (page - 1) * PageSize + 1
    local finish = start + PageSize - 1
    local result = {}
    for i = start, math.min(finish, total) do
        table.insert(result, filtered[i])
    end
    return { logs = result, currentPage = page, totalPages = math.ceil(total / PageSize), totalLogs = total }
end

local function searchObjects(params)
    local parent, err = getObjectFromPath(params.parentPath or "game")
    if not parent then return {error = err} end
    if parent == game and params.recursive then return {error = "Recursive search on 'game' is too slow. Use 'workspace'."} end
    
    local nameFilter = params.name and params.name:lower()
    local classFilter = params.className
    local limit = params.limit or 50
    local recursive = params.recursive ~= false
    local results = {}
    
    local candidates = {}
    pcall(function() candidates = recursive and parent:GetDescendants() or parent:GetChildren() end)
    
    for _, obj in ipairs(candidates) do
        local match = true
        if nameFilter and not obj.Name:lower():find(nameFilter) then match = false end
        if classFilter and obj.ClassName ~= classFilter then match = false end
        if match then
            table.insert(results, { name = obj.Name, className = obj.ClassName, path = obj:GetFullName() })
            if #results >= limit then break end
        end
    end
    return results
end

-- --- Remote Hooking Logic (Inspired by Hydroxide) ---

local function logRemote(instance, method, ...)
    if not instance or typeof(instance) ~= "Instance" then return end
    
    local args = {...}
    local logEntry = {
        name = instance.Name,
        path = instance:GetFullName(),
        method = method,
        args = {},
        time = os.date("%H:%M:%S")
    }
    
    for i, arg in ipairs(args) do
        pcall(function()
            if typeof(arg) == "Instance" then
                logEntry.args[i] = "Instance: " .. arg:GetFullName()
            elseif typeof(arg) == "table" then
                logEntry.args[i] = "Table (" .. #arg .. " items)"
            elseif typeof(arg) == "string" then
                logEntry.args[i] = #arg > 100 and arg:sub(1, 100) .. "..." or arg
            else
                logEntry.args[i] = tostring(arg)
            end
        end)
    end
    
    table.insert(RemoteLogs, 1, logEntry)
    if #RemoteLogs > MaxLogs then
        table.remove(RemoteLogs)
    end
end

local function setupHooks()
    -- Hook __namecall
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        if checkcaller() then return oldNamecall(self, ...) end
        
        local method = getnamecallmethod()
        if typeof(self) == "Instance" then
            if (method == "FireServer" or method == "fireServer") and self:IsA("RemoteEvent") then
                pcall(logRemote, self, "FireServer", ...)
            elseif (method == "InvokeServer" or method == "invokeServer") and self:IsA("RemoteFunction") then
                pcall(logRemote, self, "InvokeServer", ...)
            end
        end
        
        return oldNamecall(self, ...)
    end))

    -- Hook direct method calls for better stability and coverage
    local oldFireServer
    oldFireServer = hookfunction(Instance.new("RemoteEvent").FireServer, newcclosure(function(self, ...)
        if not checkcaller() then
            pcall(logRemote, self, "FireServer (Direct)", ...)
        end
        return oldFireServer(self, ...)
    end))

    local oldInvokeServer
    oldInvokeServer = hookfunction(Instance.new("RemoteFunction").InvokeServer, newcclosure(function(self, ...)
        if not checkcaller() then
            pcall(logRemote, self, "InvokeServer (Direct)", ...)
        end
        return oldInvokeServer(self, ...)
    end))

    print("MCP: Remote hooks setup (Hydroxide-Style Stable)")
end

local function poll()
    while true do
        pcall(function()
            local success, response = pcall(function()
                return request({
                    Url = SETTINGS.SERVER_URL,
                    Method = "POST",
                    Headers = { ["Content-Type"] = "application/json" },
                    Body = HttpService:JSONEncode({ type = "poll" })
                })
            end)

            if success and response.Success then
                local decodeSuccess, data = pcall(HttpService.JSONDecode, HttpService, response.Body)
                if decodeSuccess and data and data.id ~= nil then
                    local result
                    if data.method == "run_lua" then result = runLua(data.params.code)
                    elseif data.method == "run_lua_file" then result = runLua(data.params.code)
                    elseif data.method == "list_children" then result = listChildren(data.params.path)
                    elseif data.method == "inspect_object" then result = inspectObject(data.params.path)
                    elseif data.method == "decompile_script" then result = decompileScript(data.params.path)
                    elseif data.method == "get_remote_list" then result = getRemoteList()
                    elseif data.method == "get_remote_logs" then result = getRemoteLogs(data.params)
                    elseif data.method == "search_objects" then result = searchObjects(data.params)
                    end

                    pcall(function()
                        request({
                            Url = SETTINGS.SERVER_URL,
                            Method = "POST",
                            Headers = { ["Content-Type"] = "application/json" },
                            Body = HttpService:JSONEncode({ type = "result", id = data.id, result = result })
                        })
                    end)
                end
            end
        end)
        task.wait(SETTINGS.POLL_INTERVAL)
    end
end

if SETTINGS.ENABLE_REMOTE_HOOKS then
    pcall(setupHooks)
else
    print("MCP: Remote hooks are disabled in SETTINGS")
end

print("MCP: HTTP Polling started!")
task.spawn(poll)
       end)
        task.wait(SETTINGS.POLL_INTERVAL)
    end
end

if SETTINGS.ENABLE_REMOTE_HOOKS then
    pcall(setupHooks)
else
    print("MCP: Remote hooks are disabled in SETTINGS")
end

print("MCP: HTTP Polling started!")
task.spawn(poll)