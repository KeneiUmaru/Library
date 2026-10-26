-- Anime Adventures | Project A
-- Uses keneiproject/Library/Linoria.lua, including its bundled theme/menu controls.
-- Lobby tools and macro engine are based on Ref.lua.
-- Maid / Network adapted from fisch_kaitun_undetected.lua; one priority scheduler owns polling.
-- For local loading, place Library/Linoria.lua in the executor workspace, or execute
-- the library first and set getgenv().LinoriaLocal = true. End toggles the menu.

repeat
	task.wait()
until game:IsLoaded()

repeat
	task.wait()
until game:GetService("Players").LocalPlayer

-- kill old run first (_G is per roblox window so multi client is fine)
if _G.TowerMacro then
	pcall(function()
		_G.TowerMacro:Destroy()
	end)
end
if _G.TowerLobby then
	pcall(function()
		_G.TowerLobby:Destroy()
	end)
end
if _G.Thread then
	for _, thread in ipairs(_G.Thread) do
		pcall(task.cancel, thread)
	end
end
_G.Thread = {}

local endpoints = game:GetService("ReplicatedStorage"):WaitForChild("endpoints", 20)
local remotes = endpoints and endpoints:WaitForChild("client_to_server", 20)
assert(remotes, "client_to_server not found")

--// Maid Class ---------------------------------------------------------------

local Task = task
local Maid = {}
Maid.ClassName = "Maid"
Maid.__index = Maid

local function cleanupTask(task)
	if task == nil then
		return
	end

	local taskType = type(task)
	local robloxType = typeof(task)

	if taskType == "function" then
		task()
	elseif taskType == "thread" then
		if task ~= coroutine.running() then
			pcall(Task.cancel, task)
		end
	elseif robloxType == "RBXScriptConnection" then
		if task.Connected then
			task:Disconnect()
		end
	elseif robloxType == "Instance" then
		if task.Parent ~= nil then
			task:Destroy()
		else
			pcall(function()
				task:Destroy()
			end)
		end
	elseif taskType == "table" and type(task.Destroy) == "function" then
		task:Destroy()
	end
end

function Maid.new()
	return setmetatable({
		_tasks = {},
		_nextId = 0,
	}, Maid)
end

function Maid.isMaid(value)
	return type(value) == "table" and value.ClassName == "Maid"
end

function Maid:__index(index)
	if Maid[index] ~= nil then
		return Maid[index]
	end

	local tasks = rawget(self, "_tasks")
	if tasks then
		return tasks[index]
	end

	return nil
end

function Maid:__newindex(index, newTask)
	if Maid[index] ~= nil then
		error(("'%s' is reserved"):format(tostring(index)), 2)
	end

	local tasks = rawget(self, "_tasks")
	local oldTask = tasks[index]

	if oldTask == newTask then
		return
	end

	tasks[index] = newTask
	cleanupTask(oldTask)
end

function Maid:GiveTask(taskObj)
	if taskObj == nil then
		error("Task cannot be nil", 2)
	end

	self._nextId += 1
	local taskId = self._nextId
	self[taskId] = taskObj
	return taskId
end

function Maid:GivePromise(promise)
	if not promise then
		return promise
	end

	if type(promise.IsPending) == "function" and not promise:IsPending() then
		return promise
	end

	local id = self:GiveTask(function()
		if promise == nil then
			return
		end

		if type(promise.cancel) == "function" then
			promise:cancel()
		elseif type(promise.Cancel) == "function" then
			promise:Cancel()
		elseif type(promise.Destroy) == "function" then
			promise:Destroy()
		end
	end)

	if type(promise.Finally) == "function" then
		promise:Finally(function()
			self[id] = nil
		end)
	end

	return promise
end

function Maid:DoCleaning()
	local tasks = self._tasks

	for index, taskObj in pairs(tasks) do
		tasks[index] = nil
		local ok, err = pcall(cleanupTask, taskObj)
		if not ok then
			warn("[Project A cleanup]", err)
		end
	end
end

Maid.Destroy = Maid.DoCleaning

-- Register before starting: synchronous completion cannot leave dead threads in the maid.
function Maid:Spawn(callback, ...)
	local args = table.pack(...)
	local id
	local thread = coroutine.create(function()
		local ok, err = xpcall(callback, debug.traceback, table.unpack(args, 1, args.n))
		self._tasks[id] = nil
		if not ok then
			warn("[Project A task]", err)
		end
	end)
	id = self:GiveTask(thread)
	task.spawn(thread)
	return thread
end

function Maid:Delay(seconds, callback, ...)
	local args = table.pack(...)
	return self:Spawn(function()
		task.wait(seconds)
		callback(table.unpack(args, 1, args.n))
	end)
end

--// Rerun-safe bootstrap ------------------------------------------------------

if _G.ProjectAMaid then
	_G.ProjectAMaid:Destroy()
end
local maid = Maid.new()
_G.ProjectAMaid = maid

maid.mainthread = Maid.new()
maid.Events = Maid.new()
maid.OneShots = Maid.new()

--// Network Class ------------------------------------------------------------

local function isEventRemote(remote)
	return remote:IsA("RemoteEvent")
		or remote:IsA("UnreliableRemoteEvent")
		or remote.ClassName == "RemoteEvent"
		or remote.ClassName == "UnreliableRemoteEvent"
end

local function isFunctionRemote(remote)
	return remote:IsA("RemoteFunction") or remote.ClassName == "RemoteFunction"
end

local Network = setmetatable({
	cache = {
		connections = {},
		callbacks = {},
		remotes = {},
	},

	Resolve = function(self, name)
		if typeof(name) == "Instance" then
			return name
		end

		local cached = self.cache.remotes[name]
		if cached then
			if cached.Parent then
				return cached
			end
			self.cache.remotes[name] = nil
		end

		local remote = remotes:FindFirstChild(name)
		if remote then
			self.cache.remotes[name] = remote
		end
		return remote
	end,

	Retrieve = function(self, name, func)
		local remote = self:Resolve(name)
		if not remote then
			warn("[Network] unable to identify remote:", name)
			return nil
		end

		if isEventRemote(remote) then
			local connection = remote.OnClientEvent:Connect(func)
			table.insert(self.cache.connections, connection)
			return connection
		elseif isFunctionRemote(remote) then
			local original
			pcall(function()
				original = getcallbackvalue(remote, "OnClientInvoke")
			end)
			remote.OnClientInvoke = func
			table.insert(self.cache.callbacks, { remote = remote, original = original })
			return remote
		end

		warn("[Network] unsupported remote class:", remote.ClassName)
		return nil
	end,

	Send = function(self, name, ...)
		local remote = self:Resolve(name)
		if not remote then
			warn("[Network] unable to identify remote:", name)
			return nil
		end

		if isEventRemote(remote) then
			return remote:FireServer(...)
		elseif isFunctionRemote(remote) then
			return remote:InvokeServer(...)
		end

		warn("[Network] unsupported remote class:", remote.ClassName)
		return nil
	end,

	Clear = function(self)
		local connections = self.cache.connections
		for i = #connections, 1, -1 do
			if connections[i].Connected then
				connections[i]:Disconnect()
			end
			connections[i] = nil
		end

		local callbacks = self.cache.callbacks
		for i = #callbacks, 1, -1 do
			local entry = callbacks[i]
			pcall(function()
				entry.remote.OnClientInvoke = entry.original
			end)
			callbacks[i] = nil
		end

		table.clear(self.cache.remotes)
	end,
}, {
	__tostring = function()
		return "NetworkModule"
	end,
})

maid:GiveTask(function()
	Network:Clear()
end)

--// Scheduler ---------------------------------------------------------------

-- One timer dispatches due jobs. Each job has at most one active step; yielding
-- network/UI work runs independently so it cannot stall round-state monitoring.
local Scheduler = {
	Tasks = {},
	Running = {}, -- job -> whether its current step is still active
	Held = {}, -- resource -> job holding it
	Interval = 0.1,
	Stopped = false,
}

function Scheduler:Add(def)
	assert(type(def.Name) == "string" and type(def.Run) == "function", "Invalid scheduled job")
	def.Priority = def.Priority or 0
	def.Needs = def.Needs or {}
	def.Cooldown = def.Cooldown or 0.5
	def.NextRun = os.clock() + (def.Delay or 0)
	def.Order = #self.Tasks + 1
	table.insert(self.Tasks, def)
	table.sort(self.Tasks, function(a, b)
		return a.Priority > b.Priority or (a.Priority == b.Priority and a.Order < b.Order)
	end)
	return def
end

function Scheduler:Dispatch(job, now)
	if self.Running[job] or now < job.NextRun then
		return
	end
	job.NextRun = now + job.Cooldown
	local ok, enabled = true, true
	if job.When then
		ok, enabled = pcall(job.When)
	end
	if not ok then
		warn("[Project A scheduler]", job.Name, enabled)
	end
	if not ok or not enabled then
		return
	end
	for _, resource in ipairs(job.Needs) do
		if self.Held[resource] then
			return
		end
	end
	for _, resource in ipairs(job.Needs) do
		self.Held[resource] = job
	end
	-- Set this before Spawn: short jobs may finish before Spawn returns.
	self.Running[job] = true
	maid.mainthread:Spawn(function()
		local success, err = xpcall(job.Run, debug.traceback)
		self.Running[job] = nil
		for _, resource in ipairs(job.Needs) do
			if self.Held[resource] == job then
				self.Held[resource] = nil
			end
		end
		if not success then
			job.NextRun = os.clock() + 5
			warn("[Project A scheduler]", job.Name, err)
		end
	end)
end

function Scheduler:Tick()
	if self.Stopped then
		return
	end
	local now = os.clock()
	for _, job in ipairs(self.Tasks) do
		self:Dispatch(job, now)
	end
end

function Scheduler:StopAll()
	self.Stopped = true
	table.clear(self.Tasks)
end

maid:GiveTask(function()
	Scheduler:StopAll()
end)

--// Config -------------------------------------------------------------------

local mainFolder = "project a macro"
local settingsFolder = mainFolder .. "/settings"
if not isfolder(mainFolder) then
	makefolder(mainFolder)
end
if not isfolder(settingsFolder) then
	makefolder(settingsFolder)
end

local preferencesFile = settingsFolder .. "/preferences.json"
local configFiles = {
	[preferencesFile] = { autoSave = true },
	[settingsFolder .. "/lobby.json"] = {
		mode = "Story",
		world = "namek",
		level = "namek_level_1",
		difficulty = "Normal",
		friendsOnly = true,
		autoJoin = false,
		autoSummon = false,
		autoSell = false,
		sellRarities = { Rare = true },
		sellTraits = { none = true },
		autoCraft = false,
		autoClaim = false,
		banner = "EventClover",
		pullMode = "gems",
		summonLimit = 10,
		summonDone = 0,
		reserve = 0,
		target = "",
		recipe = "",
		craftLimit = 1,
		craftDone = 0,
		customCodes = "",
	},
	[settingsFolder .. "/config.json"] = {
		profile = "",
		mode = "wave",
		timeout = 60,
		playMacro = false,
		autoReplay = false,
		autoSkipWave = false,
		autoStartGame = false,
		autoPickCard = false,
		followPlayerCard = false,
		cardType = "Any",
		cardPriority = { "Attack III", "Attack II", "Cooldown III", "Yen III", "Range III" },
		autoReturnLobby = false,
		returnWave = 15,
	},
}

_G.Config = {}

function SaveConfig()
	for path, defaults in pairs(configFiles) do
		local data = {}
		for key in pairs(defaults) do
			data[key] = _G.Config[path:match("/lobby.json$") and key == "mode" and "lobbyMode" or key]
		end
		writefile(path, game:GetService("HttpService"):JSONEncode(data))
	end
end

function LoadConfig()
	for path, defaults in pairs(configFiles) do
		local ok, decoded = pcall(function()
			return game:GetService("HttpService"):JSONDecode(readfile(path))
		end)
		for key, value in pairs(defaults) do
			if ok and type(decoded) == "table" and type(decoded[key]) == type(value) then
				value = decoded[key]
			end
			_G.Config[path:match("/lobby.json$") and key == "mode" and "lobbyMode" or key] = value
		end
	end
end

LoadConfig()

function getValue(object, name)
	local v = object and object:FindFirstChild(name)
	if v and v:IsA("ValueBase") then
		return v.Value
	end
	return nil
end

--// Linoria UI ---------------------------------------------------------------

-- Prefer the workspace library when the executor exposes it through readfile.
-- Otherwise load the same fork from its published repository.
local function loadLibrary()
	local env = getgenv()
	if env.LinoriaLocal and env.Library and env.Library.ScreenGui and env.Library.ScreenGui.Parent then
		return env.Library
	end

	if type(isfile) == "function" and type(readfile) == "function" then
		for _, path in ipairs({ "keneiproject/Library/Linoria.lua", "Library/Linoria.lua", "Linoria.lua" }) do
			if isfile(path) then
				local chunk, err = loadstring(readfile(path), "@" .. path)
				assert(chunk, err)
				return chunk()
			end
		end
	end

	local chunk, err = loadstring(game:HttpGet("https://raw.githubusercontent.com/KeneiUmaru/Library/main/Linoria.lua"))
	assert(chunk, err)
	return chunk()
end

local Library = loadLibrary()
local ThemeManager = Library.ThemeManager
assert(
	ThemeManager and type(ThemeManager.BuildMenuSection) == "function",
	"Use keneiproject/Library/Linoria.lua (bundled ThemeManager required)"
)
Library.NotifyOnError = true
Library.AccentColor = Color3.fromRGB(130, 82, 255)
Library.AccentColorDark = Library:GetDarkerColor(Library.AccentColor)
local Window = Library:CreateWindow({
	Title = "Anime Adventures | Project A",
	Center = true,
	AutoShow = false,
})

--// Lobby tools --------------------------------------------------------------

do
	_G.Config.summonLimit = math.clamp(math.floor(_G.Config.summonLimit), 1, 100000)
	_G.Config.craftLimit = math.clamp(math.floor(_G.Config.craftLimit), 1, 100000)
	_G.Config.summonDone = math.max(0, math.floor(_G.Config.summonDone))
	_G.Config.craftDone = math.max(0, math.floor(_G.Config.craftDone))
	_G.Config.reserve = math.max(0, math.floor(_G.Config.reserve))

	local Loader = require(game:GetService("ReplicatedStorage").src.Loader)
	local function getClientService(name)
		local ok, result = pcall(Loader.load_client_service, game:GetService("ReplicatedStorage").src.Loader, name)
		if ok then
			return result
		end
		return nil
	end

	-- wait for the game to load player data (script can run before the lobby is ready)
	local LobbyService, GameUI, session
	if game.PlaceId == 8304191830 then
		local waitUntil = os.clock() + 60
		repeat
			LobbyService = LobbyService or getClientService("LobbyServiceClient")
			GameUI = GameUI or getClientService("GUIService")
			session = LobbyService and LobbyService.session
			local dataReady = session
				and session.profile_data
				and session.inventory
				and session.collection
				and session.quest_handler
			if dataReady then
				break
			end
			task.wait(0.5)
		until os.clock() >= waitUntil
		assert(LobbyService, "Lobby service is not ready")
		assert(GameUI, "Game UI is not ready")
		assert(session and session.profile_data and session.inventory, "Player data is not ready")
	else
		LobbyService = {}
		GameUI = getClientService("GUIService") or {}
		session = {
			profile_data = {},
			inventory = { inventory_profile_data = {} },
			collection = { collection_profile_data = {} },
			quest_handler = { quest_profile_data = { quests = {} } },
		}
	end

	local Levels = require(game:GetService("ReplicatedStorage").src.Data.Levels)
	local Worlds = require(game:GetService("ReplicatedStorage").src.Data.Worlds)
	local Banners = require(game:GetService("ReplicatedStorage").src.Data.Banners)
	local Items = require(game:GetService("ReplicatedStorage").src.Data.Items)
	local Units = require(game:GetService("ReplicatedStorage").src.Data.Units)
	local Traits = Loader.load_data(game:GetService("ReplicatedStorage").src.Loader, "Traits")

	local LobbyTools = {
		State = "lobby",
		Settings = _G.Config,
		Message = game.PlaceId == 8304191830 and "Lobby ready - Macros are disabled"
			or "Lobby automation is disabled in matches",
		Busy = nil,
		Destroyed = false,
	}
	_G.TowerLobby = LobbyTools

	local statusLabel, resourcesLabel, logLabel, recipeLabel, summonLabel, sellLabel
	local history = {}
	local controls = {}
	local ready = false
	local syncing = false
	local generation = 0

	local allowedRemotes = {
		request_join_lobby = true,
		request_leave_lobby = true,
		request_lock_level = true,
		request_start_game = true,
		buy_from_banner = true,
		sell_units = true,
		craft_item = true,
		craft_raid_item = true,
		craft_raid_item_2 = true,
		craft_raid_unit = true,
		redeem_code = true,
		claim_daily_reward = true,
		request_current_dailymissions = true,
		request_dailymissions_data = true,
		request_claim_dailymission = true,
		claim_battlepass_rewards = true,
		claim_player_level_rewards = true,
		claim_first_clear_rewards = true,
		claim_previous_tournament_rewards = true,
		claim_christmas_calendar_reward = true,
		redeem_quest = true,
	}
	local knownCodes = { "DUNGEONS", "UPDATESOON5189", "APRILFOOLS", "MILLIONFAVES", "2BILLIONAA" }
	local triedCodes = {}
	local dailyMissionDefinitions
	local codesSource = "https://www.gamesradar.com/games/strategy/anime-adventures-codes/"

	local function setMessage(text, isError)
		LobbyTools.Message = tostring(text)
		LobbyTools.MessageError = isError
	end

	local function addLog(text)
		table.insert(history, 1, tostring(text))
		if #history > 10 then
			table.remove(history)
		end
	end

	local function guard()
		assert(not LobbyTools.Destroyed and game.PlaceId == 8304191830, "Lobby tools are disabled outside the lobby")
	end

	local function saveSettings()
		if not ready or LobbyTools.Destroyed or not _G.Config.autoSave then
			return
		end
		local ok, err = pcall(SaveConfig)
		if not ok then
			setMessage(err, true)
		end
	end

	function LobbyTools:Invoke(name, ...)
		guard()
		assert(allowedRemotes[name], "This action is not allowed in the lobby")
		local remote = remotes:FindFirstChild(name)
		assert(remote and remote:IsA("RemoteFunction"), "Action is unavailable: " .. name)

		local args = table.pack(...)
		local token = generation
		local done = false
		local result
		maid.OneShots:Spawn(function()
			result = table.pack(pcall(function()
				guard()
				assert(token == generation, "Action cancelled")
				return Network:Send(remote, table.unpack(args, 1, args.n))
			end))
			done = true
		end)

		local deadline = os.clock() + 15
		repeat
			task.wait(0.05)
		until done or os.clock() >= deadline or self.Destroyed
		guard()
		assert(done, "Action timed out; automation stopped to prevent duplicate purchases")
		assert(result[1], tostring(result[2]))
		assert(result[2] ~= false, tostring(result[3] or "Action rejected by the game"))
		return table.unpack(result, 2, result.n)
	end

	function LobbyTools:Run(name, callback, autoKey)
		guard()
		assert(not self.Busy, "Wait for the current action: " .. tostring(self.Busy))
		self.Busy = name
		maid.OneShots:Spawn(function()
			local ok, err = pcall(callback)
			self.Busy = nil
			if self.Destroyed then
				return
			end
			if not ok then
				if autoKey then
					_G.Config[autoKey] = false
					saveSettings()
				end
				setMessage(err, true)
				addLog(name .. ": " .. tostring(err))
			end
		end)
	end

	local function getStageMode(id, level)
		local world = Worlds[level.world] or {}
		if world.legend_stage then
			return "Legend Stage"
		end
		if level.is_raid or world.raid_world then
			return "Raid"
		end
		if id:find("infinite", 1, true) then
			return "Infinite"
		end
		if level.story_level_rank then
			return "Story"
		end
	end

	if _G.Config.lobbyMode == "Raid / Legend" then
		local level = Levels[_G.Config.level] or {}
		local world = Worlds[level.world or _G.Config.world] or {}
		_G.Config.lobbyMode = world.legend_stage and "Legend Stage" or "Raid"
	end

	local function getRoomFolders(mode)
		if mode == "Challenge" then
			return { workspace:FindFirstChild("_CHALLENGES") }
		end
		if mode == "All Stages" then
			mode = getStageMode(_G.Config.level, Levels[_G.Config.level] or {})
		end
		if mode == "Raid" then
			return { workspace:FindFirstChild("_RAID"), workspace:FindFirstChild("_MAPS") }
		end
		return { workspace:FindFirstChild("_LOBBIES") }
	end

	local function getMyRoom()
		for _, folderName in ipairs({ "_LOBBIES", "_RAID", "_MAPS", "_CHALLENGES" }) do
			local roomFolder = workspace:FindFirstChild(folderName)
			if roomFolder then
				for _, room in ipairs(roomFolder:GetDescendants()) do
					if room:IsA("Model") and room.Name:match("^_lobbytemplate") then
						if
							getValue(room, "Owner") == game:GetService("Players").LocalPlayer
							or LobbyService.current_lobby == room.Name
						then
							return room
						end
					end
				end
			end
		end
	end

	local function findRoom(mode)
		local myRoom = getMyRoom()
		if myRoom then
			return myRoom
		end

		for _, roomFolder in pairs(getRoomFolders(mode)) do
			for _, room in ipairs(roomFolder:GetDescendants()) do
				if
					room:IsA("Model")
					and room.Name:match("^_lobbytemplate")
					and not getValue(room, "Owner")
					and getValue(room, "Teleporting") ~= true
					and getValue(room, "Locked") ~= true
				then
					local members = room:FindFirstChild("Players")
					if members and #members:GetChildren() == 0 then
						return room
					end
				end
			end
		end
	end

	function LobbyTools:StageList(mode, worldId)
		local list = {}
		local lookup = {}
		if mode == "Challenge" then
			return list, lookup
		end

		for id, level in pairs(Levels) do
			if
				type(level) == "table"
				and (not worldId or level.world == worldId)
				and not level._portal_only_level
				and not level._map_item_only
			then
				local world = Worlds[level.world] or {}
				local matches = mode == "All Stages" or mode == getStageMode(id, level)

				if matches then
					local label = (world.name or level.world or "Other")
						.. " / "
						.. (level.name or id)
						.. " ["
						.. id
						.. "]"
					table.insert(list, label)
					lookup[label] = id
				end
			end
		end

		table.sort(list)
		return list, lookup
	end

	function LobbyTools:JoinStage(startGame)
		guard()
		if self.JoiningRoom then
			setMessage("Waiting for the selected stage to start")
			return self.JoiningRoom
		end

		local room = findRoom(_G.Config.lobbyMode)
		if not room then
			setMessage("Waiting for an empty room")
			return false
		end

		function isMine()
			return getValue(room, "Owner") == game:GetService("Players").LocalPlayer
				or LobbyService.current_lobby == room.Name
		end

		if not isMine() then
			self:Invoke("request_join_lobby", room.Name)
			local deadline = os.clock() + 5
			repeat
				guard()
				if isMine() then
					break
				end
				task.wait(0.1)
			until os.clock() >= deadline
			assert(isMine(), "Unable to join the selected room")
		end

		if _G.Config.lobbyMode ~= "Challenge" then
			assert(Levels[_G.Config.level], "Choose a stage first")
			if getValue(room, "Level") ~= _G.Config.level or getValue(room, "Locked") ~= true then
				self:Invoke(
					"request_lock_level",
					room.Name,
					_G.Config.level,
					_G.Config.friendsOnly,
					_G.Config.difficulty
				)
			end
		end

		setMessage("Joined " .. room.Name)
		addLog("Joined " .. (getValue(room, "Level") or _G.Config.level) .. " · " .. _G.Config.difficulty)

		if startGame ~= false then
			if _G.Config.lobbyMode == "Challenge" and getValue(room, "requires_owner") == false then
				setMessage("Joined challenge · waiting for the countdown")
			else
				self:Invoke("request_start_game", room.Name)
				setMessage("Starting the selected stage")
			end
			self.JoiningRoom = room.Name
			self.JoinDeadline = os.clock() + 30
		end
		return room.Name
	end

	function LobbyTools:LeaveRoom()
		local room = getMyRoom()
		local roomId = room and room.Name or LobbyService.current_lobby
		assert(roomId, "You are not in a room")
		self:Invoke("request_leave_lobby", roomId)
		self.JoiningRoom = nil
		if type(LobbyService.cancel_selections) == "function" then
			LobbyService.cancel_selections()
		end
		setMessage("Left the room")
	end

	local function getInventory()
		return session.inventory.inventory_profile_data
	end

	local function countItem(id)
		local inventory = getInventory()
		local amount = inventory.normal_items and inventory.normal_items[id]
		if type(amount) == "number" then
			return amount
		end
		if type(amount) == "table" then
			return tonumber(amount.amount) or 0
		end

		local total = 0
		for _, item in pairs(inventory.unique_items or {}) do
			if item.item_id == id or item.id == id then
				total = total + 1
			end
		end
		return total
	end

	local function getCurrency(id)
		if id == "Gems" then
			return tonumber(session.profile_data.gem_amount) or 0
		end
		if id == "Gold" then
			return tonumber(session.profile_data.gold_amount) or 0
		end
		local resources = session.profile_data.resources or {}
		return tonumber(resources[id])
			or tonumber(getValue(game:GetService("Players").LocalPlayer:FindFirstChild("_stats"), "_resource" .. id))
			or 0
	end

	local function countTargetUnit()
		local total = 0
		for _, unit in pairs(session.collection.collection_profile_data.owned_units or {}) do
			if unit.unit_id == _G.Config.target then
				total = total + 1
			end
		end
		return total
	end

	function LobbyTools:SummonOnce(limited)
		local banner = Banners[_G.Config.banner]
		assert(banner, "Select a banner")
		assert(banner.active ~= false, "This banner is not active")
		assert(
			_G.Config.pullMode == "gems" or _G.Config.pullMode == "gems10" or _G.Config.pullMode == "ticket",
			"Choose a summon amount"
		)

		local pullMode = _G.Config.pullMode
		local amount = 1
		if pullMode == "gems10" then
			amount = 10
		end

		if limited then
			assert(_G.Config.summonDone < _G.Config.summonLimit, "Summon limit reached")
			if amount > _G.Config.summonLimit - _G.Config.summonDone then
				pullMode = "gems"
				amount = 1
			end
		end

		local cost = banner.resource_cost or { id = "Gems", amount = 50 }
		if pullMode == "ticket" then
			assert(not banner._no_summon_ticket and countItem("summon_ticket") > 0, "No usable summon tickets")
		else
			local need = (tonumber(cost.amount) or 50) * amount + _G.Config.reserve
			assert(getCurrency(cost.id) >= need, "Not enough currency to keep the selected reserve")
		end

		local before = countTargetUnit()
		self:Invoke("buy_from_banner", _G.Config.banner, pullMode)
		_G.Config.summonDone = _G.Config.summonDone + amount
		task.wait(0.4)

		if _G.Config.target ~= "" and countTargetUnit() > before then
			_G.Config.autoSummon = false
			setMessage("Target unit obtained")
		elseif _G.Config.summonDone >= _G.Config.summonLimit then
			_G.Config.autoSummon = false
			setMessage("Summon limit reached")
		else
			setMessage("Summoned " .. amount .. " · " .. _G.Config.summonDone .. "/" .. _G.Config.summonLimit)
		end
		saveSettings()
		addLog("Summon: " .. _G.Config.banner .. " · " .. pullMode)
	end

	local function matchesSellTraits(traits)
		local selected = _G.Config.sellTraits
		if not traits or not next(traits) then
			return selected.none == true
		end
		for _, trait in pairs(traits) do
			if type(trait) ~= "table" or not trait.trait then
				return false
			end
			local key = trait.trait .. ":" .. tostring(trait.tier or "1")
			if not selected[key] then
				return false
			end
		end
		return true
	end

	-- Sell owned collection units; temporary match units are never candidates.
	function LobbyTools:GetSellCandidates()
		local collection = session.collection.collection_profile_data
		local equipped = {}
		for _, uuid in pairs(collection.equipped_units or {}) do
			equipped[uuid] = true
		end
		for _, uuid in pairs(session.override_equipped_units or {}) do
			equipped[uuid] = true
		end
		for _, loadout in pairs(session.profile_data.loadouts_v2 or {}) do
			if type(loadout) == "table" then
				for _, uuid in pairs(loadout.equipped_units or {}) do
					equipped[uuid] = true
				end
			end
		end

		local candidates = {}
		for key, unit in pairs(collection.owned_units or {}) do
			if type(unit) == "table" then
				local uuid = unit.uuid or key
				local definition = Units[unit.unit_id]
				if
					definition
					and _G.Config.sellRarities[definition.rarity]
					and not equipped[uuid]
					and not unit.equipped_slot
					and not unit._locked
					and not unit.locked
					and not unit.shiny
					and not unit._shiny
					and matchesSellTraits(unit.traits)
					and unit.unit_id ~= _G.Config.target
				then
					table.insert(candidates, uuid)
				end
			end
		end
		table.sort(candidates)
		return candidates
	end

	function LobbyTools:SellUnits()
		guard()
		local candidates = self:GetSellCandidates()
		if #candidates == 0 then
			return
		end
		-- Keep individual requests bounded while the collection replicates changes.
		while #candidates > 50 do
			table.remove(candidates)
		end
		self:Invoke("sell_units", candidates)
		local deadline = os.clock() + 8
		local remaining
		repeat
			guard()
			remaining = 0
			for _, uuid in ipairs(candidates) do
				if session.collection:get_unit_by_uuid(uuid) then
					remaining = remaining + 1
				end
			end
			if remaining > 0 then
				task.wait(0.1)
			end
		until remaining == 0 or os.clock() >= deadline
		assert(remaining == 0, "Sale was not confirmed; Auto Sell stopped")
		self.SoldUnits = (self.SoldUnits or 0) + #candidates
		setMessage("Sold " .. #candidates .. " units")
		addLog("Auto Sell: " .. #candidates .. " units")
	end

	local craftMenus = {}
	for _, object in pairs(GameUI) do
		if
			type(object) == "table"
			and type(object.filter_craft_type) == "string"
			and type(object._ui_instance_name) == "string"
		then
			craftMenus[object.filter_craft_type] = object._ui_instance_name
		end
	end

	local function getRecipe(item)
		local result = {}
		for key, entry in pairs(item.crafting_recipe or {}) do
			local id = key
			local amount = entry
			if type(entry) == "table" then
				id = entry.item_id or entry.id or key
				amount = entry.amount
			end
			assert(type(id) == "string" and type(amount) == "number" and amount > 0, "Unsupported recipe")
			table.insert(result, { id = id, amount = amount })
		end
		return result
	end

	local function itemName(id)
		return Items[id] and Items[id].name or id
	end

	function LobbyTools:RecipeList()
		local list = {}
		local lookup = {}
		for id, item in pairs(Items) do
			if type(item) == "table" and type(item.crafting_recipe) == "table" and craftMenus[item._craft_type] then
				local label = (item.name or id) .. " [" .. id .. "]"
				table.insert(list, label)
				lookup[label] = id
			end
		end
		table.sort(list)
		return list, lookup
	end

	function LobbyTools:RecipeText()
		local item = Items[_G.Config.recipe]
		if not item then
			return "Choose a recipe"
		end

		local lines = {}
		for _, need in ipairs(getRecipe(item)) do
			table.insert(lines, itemName(need.id) .. " " .. countItem(need.id) .. "/" .. need.amount)
		end
		table.insert(lines, "Gold: " .. getCurrency("Gold") .. "/" .. tostring(item.crafting_cost or 0))
		return table.concat(lines, "\n")
	end

	function LobbyTools:CraftOnce(limited)
		local item = Items[_G.Config.recipe]
		assert(item, "Select a recipe")
		local menu = craftMenus[item._craft_type]
		assert(menu, "Recipe is not supported by the current crafting menu")
		if limited then
			assert(_G.Config.craftDone < _G.Config.craftLimit, "Craft limit reached")
		end

		for _, need in ipairs(getRecipe(item)) do
			assert(countItem(need.id) >= need.amount, "Missing material: " .. itemName(need.id))
		end
		assert(getCurrency("Gold") >= (tonumber(item.crafting_cost) or 0), "Not enough gold")

		self:Invoke("craft_item", _G.Config.recipe, menu)
		_G.Config.craftDone = _G.Config.craftDone + 1
		if _G.Config.craftDone >= _G.Config.craftLimit then
			_G.Config.autoCraft = false
		end
		setMessage(
			"Crafted "
				.. (item.name or _G.Config.recipe)
				.. " · "
				.. _G.Config.craftDone
				.. "/"
				.. _G.Config.craftLimit
		)
		addLog("Craft: " .. _G.Config.recipe)
		saveSettings()
	end

	function LobbyTools:RedeemCodes()
		local codeList = {}
		local added = {}
		for _, code in ipairs(knownCodes) do
			table.insert(codeList, code)
			added[code] = true
		end
		for code in _G.Config.customCodes:gmatch("[^,%s;]+") do
			if not added[code] then
				table.insert(codeList, code)
				added[code] = true
			end
		end

		local accepted = 0
		local checked = 0
		for _, code in ipairs(codeList) do
			guard()
			if not triedCodes[code] then
				local ok, err = pcall(self.Invoke, self, "redeem_code", code)
				triedCodes[code] = true
				checked = checked + 1
				if ok then
					accepted = accepted + 1
					addLog("Redeem accepted: " .. code)
				else
					addLog("Redeem " .. code .. ": " .. tostring(err))
				end
				setMessage("Redeem codes: " .. checked .. "/" .. #codeList)
				task.wait(0.35)
			end
		end

		setMessage("Codes checked: " .. checked .. " · accepted: " .. accepted)
		return accepted, checked
	end

	function LobbyTools:ClaimRewards(category)
		guard()
		local claimed, failed = 0, 0
		local function claim(label, confirmed, remote, ...)
			guard()
			local ok, err = pcall(self.Invoke, self, remote, ...)
			if ok then
				local deadline = os.clock() + 2
				repeat
					task.wait(0.1)
				until confirmed() or os.clock() >= deadline or self.Destroyed
				guard()
				if confirmed() then
					claimed = claimed + 1
					addLog("Claimed: " .. label)
					return true
				end
				err = "Reward not confirmed"
			end
			failed = failed + 1
			addLog(label .. ": " .. tostring(err))
			return false
		end

		if not category or category == "Daily" then
			local settings = Loader.load_data(game:GetService("ReplicatedStorage").src.Loader, "GameplaySettings")
			local previous = session.profile_data.last_daily_reward_claimed_time or 0
			if os.time() - previous >= settings.DAILY_REWARD_WAIT then
				claim("Daily Login", function()
					return (session.profile_data.last_daily_reward_claimed_time or 0) > previous
				end, "claim_daily_reward")
			end
		end

		if not category or category == "Levels" then
			local core = Loader.load_core_service(game:GetService("ReplicatedStorage").src.Loader, "LevelServiceCore")
			local playerLevel = core.calculate_level(
				session.player,
				getValue(game:GetService("Players").LocalPlayer:FindFirstChild("_stats"), "player_xp")
					or session.profile_data.player_xp
					or 0
			)
			for _, reward in pairs(require(game:GetService("ReplicatedStorage").src.Data.PlayerLevelRewards)) do
				if
					tonumber(reward.level) <= playerLevel
					and not (session.profile_data.level_rewards_claimed or {})[reward.level]
				then
					claim("Level " .. reward.level, function()
						return (session.profile_data.level_rewards_claimed or {})[reward.level]
					end, "claim_player_level_rewards", reward.level)
				end
			end
		end

		if not category or category == "Clears" then
			for id, progress in pairs((session.profile_data.level_data or {}).completed_story_levels or {}) do
				for difficulty, rewards in pairs((Levels[id] or {}).clear_rewards or {}) do
					local clears = ((progress.difficulty_completed_data or {})[difficulty] or {}).times_completed or 0
					for _, reward in pairs(rewards) do
						local function confirmed()
							return (((session.profile_data.clear_rewards or {})[id] or {})[difficulty] or {})[reward._id]
						end
						if clears >= reward.clears and not confirmed() then
							claim(
								id .. " / " .. difficulty .. " / " .. tostring(reward._id),
								confirmed,
								"claim_first_clear_rewards",
								id,
								difficulty,
								reward._id
							)
						end
					end
				end
			end
		end

		local dailyQuestIds = {}
		if not category or category == "Daily Missions" then
			local current, interval = self:Invoke("request_current_dailymissions")
			assert(type(current) == "table" and type(interval) == "number", "Daily missions unavailable")
			if not dailyMissionDefinitions then
				dailyMissionDefinitions = self:Invoke("request_dailymissions_data")
			end
			assert(type(dailyMissionDefinitions) == "table", "Daily mission data unavailable")
			for _, id in pairs(current) do
				local mission = dailyMissionDefinitions[id]
				if type(mission) == "table" and mission.quest_id then
					dailyQuestIds[mission.quest_id] = true
					local function accepted()
						local data = session.profile_data.dailymissions_data or {}
						return (tonumber(data.highest_claimed_interval) or -math.huge) >= interval
							and (data.claimed_missions or {})[id] == true
					end
					if not accepted() then
						claim("Daily mission: " .. id, accepted, "request_claim_dailymission", id)
					end
				end
			end
		end

		if not category or category == "Quests" or category == "Daily Missions" then
			local core = Loader.load_core_service(game:GetService("ReplicatedStorage").src.Loader, "QuestClassesCore")
			local attempted = {}
			for _ = 1, 32 do
				local readyQuests = {}
				for uuid, quest in pairs(session.quest_handler.quest_profile_data.quests or {}) do
					local info = quest.quest_info or {}
					local matches = category ~= "Daily Missions"
						or quest.quest_type == "daily"
						or dailyQuestIds[info.id]
					local ok, complete = false, false
					if matches then
						ok, complete = pcall(core.is_quest_complete, session, quest)
					end
					if ok and complete and not attempted[uuid] then
						readyQuests[#readyQuests + 1] = { uuid = uuid, quest = quest }
					end
				end
				if #readyQuests == 0 then
					break
				end
				for _, entry in ipairs(readyQuests) do
					attempted[entry.uuid] = true
					claim(entry.quest.quest_info.quest_name or entry.uuid, function()
						return not session.quest_handler.quest_profile_data.quests[entry.uuid]
					end, "redeem_quest", entry.quest.uuid or entry.uuid)
				end
			end
		end

		if not category or category == "Battle Pass" then
			local previous = game:GetService("HttpService"):JSONEncode(session.profile_data.battlepass_data or {})
			local ok, err = pcall(self.Invoke, self, "claim_battlepass_rewards")
			task.wait(0.2)
			if ok then
				if
					game:GetService("HttpService"):JSONEncode(session.profile_data.battlepass_data or {}) ~= previous
				then
					claimed = claimed + 1
					addLog("Claimed: Battle Pass")
				end
			else
				failed = failed + 1
				addLog("Battle Pass: " .. tostring(err))
			end
		end

		if not category or category == "Events" then
			local service = getClientService("SpecialEventServiceClient")
			if service and service.christmas_calendar_available_day then
				local rewards = Loader.load_data(game:GetService("ReplicatedStorage").src.Loader, "HolidayRewards")
				local day = service.christmas_calendar_available_day
				local function confirmed()
					return (
						((session.profile_data.login_calendar or {})[rewards._login_calendar_id] or {}).days_claimed
						or {}
					)[day]
				end
				if not confirmed() then
					claim("Event Calendar", confirmed, "claim_christmas_calendar_reward")
				end
			end
		end

		if not category or category == "Tournament" then
			local service = getClientService("TournamentServiceClient")
			local previous = service and service._PREVIOUS_TOURNAMENT
			local score = previous
				and ((session.profile_data.tournament_data or {}).tournament_scores or {})[previous.tournament_id]
			if score and score.final_ranking and not score.claimed_rewards then
				local before = game:GetService("HttpService"):JSONEncode(score)
				claim("Tournament", function()
					local current = ((session.profile_data.tournament_data or {}).tournament_scores or {})[previous.tournament_id]
					return not current or game:GetService("HttpService"):JSONEncode(current) ~= before
				end, "claim_previous_tournament_rewards")
			end
		end

		setMessage(
			"Claimed "
				.. claimed
				.. " reward(s)"
				.. (
					failed > 0 and " - " .. failed .. " unconfirmed; see Recent Actions"
					or " - All available rewards checked"
				)
		)
		return claimed, failed
	end

	function LobbyTools:OpenMenu(name)
		guard()
		local menu = GameUI[name]
		assert(menu, "Menu is unavailable")
		assert(type(menu.toggle) == "function", "Menu cannot be opened")
		menu:toggle()
	end

	function LobbyTools:Teleport(name)
		guard()
		local teleport = LobbyService[name]
		assert(teleport, "Location is unavailable")
		assert(type(teleport) == "function" and name:match("^teleport_to_"), "Invalid location")
		teleport()
	end

	function LobbyTools:StopAll()
		_G.Config.autoSell = false
		_G.Config.autoJoin = false
		_G.Config.autoSummon = false
		_G.Config.autoCraft = false
		_G.Config.autoClaim = false
		saveSettings()
		setMessage("Automation stopped")
	end

	function LobbyTools:Destroy()
		if self.Destroyed then
			return
		end
		self.Destroyed = true
		generation = generation + 1
		local ui = Library
		Library = nil
		if ui then
			ui:Unload()
		end
		if _G.TowerLobby == self then
			_G.TowerLobby = nil
		end
	end

	--// Lobby controls -----------------------------------------------------------

	local Tabs = {}
	for _, name in ipairs({ "Maps", "Units", "Rewards" }) do
		Tabs[name] = Window:AddTab(name)
	end

	local mapsBox = Tabs.Maps:AddLeftGroupbox("Auto Join Map")
	local roomBox = Tabs.Maps:AddRightGroupbox("Room Actions")
	local statusBox = Tabs.Maps:AddRightGroupbox("Lobby Status")
	local summonBox = Tabs.Units:AddLeftGroupbox("Summon")
	local sellBox = Tabs.Units:AddLeftGroupbox("Auto Sell")
	local summonOptionsBox = Tabs.Units:AddRightGroupbox("Limits / Target")
	local craftBox = Tabs.Units:AddLeftGroupbox("Item Crafting")
	local materialBox = Tabs.Units:AddRightGroupbox("Materials")
	local raidCraftBox = Tabs.Units:AddRightGroupbox("Raid Crafting")
	local codesBox = Tabs.Rewards:AddLeftGroupbox("Redeem Codes")
	local rewardsBox = Tabs.Rewards:AddLeftGroupbox("Reward Automation")
	local dailyBox = Tabs.Rewards:AddLeftGroupbox("Daily / Battle Pass")
	local progressBox = Tabs.Rewards:AddRightGroupbox("Levels / Stage Clears")
	local questsBox = Tabs.Rewards:AddRightGroupbox("Quests / Tournament")
	local eventsBox = Tabs.Rewards:AddLeftGroupbox("Event Rewards")
	local menusBox = Tabs.Maps:AddLeftGroupbox("Native Game Menus")
	local locationsBox = Tabs.Maps:AddRightGroupbox("Lobby Locations")
	local recentBox = Tabs.Rewards:AddRightGroupbox("Recent Actions")

	local function safe(callback)
		return function(...)
			local ok, err = pcall(callback, ...)
			if not ok then
				setMessage(err, true)
				if Library then
					Library:Notify(tostring(err), 4)
				end
			end
		end
	end

	local function addButton(group, text, name, callback)
		group:AddButton({ Text = text, Func = safe(function()
			LobbyTools:Run(name, callback)
		end) })
	end

	local function addNumberInput(group, key, text, min, max)
		controls[key] = group:AddInput("Lobby_" .. key, {
			Text = text,
			Default = tostring(_G.Config[key]),
			Numeric = true,
			Finished = true,
			Callback = safe(function(v)
				local n = tonumber(v)
				assert(
					n and n == math.floor(n) and n >= min and n <= max,
					"Enter a whole number from " .. min .. " to " .. max
				)
				_G.Config[key] = n
				saveSettings()
			end),
		})
	end

	local function addToggle(group, key, text, resetKey)
		controls[key] = group:AddToggle("Lobby_" .. key, {
			Text = text,
			Default = _G.Config[key],
			Callback = function(enabled)
				if syncing then
					return
				end
				if enabled and not _G.Config[key] then
					if resetKey then
						_G.Config[resetKey] = 0
					end
					if key == "autoJoin" then
						LobbyTools.JoiningRoom = nil
					end
				end
				_G.Config[key] = enabled
				saveSettings()
			end,
		})
	end

	local worldDropdown, stageDropdown
	local worldLookup = {}
	local stageLookup = {}
	local updatingMaps = false

	local function refreshStages()
		if updatingMaps then
			return
		end
		updatingMaps = true

		local worldNames = {}
		worldLookup = {}
		for id, world in pairs(Worlds) do
			if type(world) == "table" then
				local stages = LobbyTools:StageList(_G.Config.lobbyMode, id)
				if #stages > 0 then
					local label = (world.name or id) .. " [" .. id .. "]"
					table.insert(worldNames, label)
					worldLookup[label] = id
				end
			end
		end
		table.sort(worldNames)

		if worldDropdown then
			worldDropdown:SetValues(worldNames)
			local chosen
			for label, id in pairs(worldLookup) do
				if id == _G.Config.world then
					chosen = label
				end
			end
			chosen = chosen or worldNames[1]
			_G.Config.world = chosen and worldLookup[chosen] or ""
			worldDropdown:SetValue(chosen)
		end

		local stageNames
		stageNames, stageLookup = LobbyTools:StageList(_G.Config.lobbyMode, _G.Config.world)
		if stageDropdown then
			stageDropdown:SetValues(stageNames)
			local chosen
			for label, id in pairs(stageLookup) do
				if id == _G.Config.level then
					chosen = label
				end
			end
			chosen = chosen or stageNames[1]
			_G.Config.level = chosen and stageLookup[chosen] or ""
			stageDropdown:SetValue(chosen)
		end

		updatingMaps = false
	end

	mapsBox:AddDropdown("Lobby_Mode", {
		Text = "Mode",
		Values = { "Story", "Infinite", "Legend Stage", "Raid", "Challenge", "All Stages" },
		Default = _G.Config.lobbyMode,
		Callback = function(v)
			_G.Config.lobbyMode = v
			refreshStages()
			saveSettings()
		end,
	})
	worldDropdown = mapsBox:AddDropdown("Lobby_World", {
		Text = "World",
		Values = {},
		AllowNull = true,
		Callback = function(v)
			if updatingMaps then
				return
			end
			if worldLookup[v] then
				_G.Config.world = worldLookup[v]
				refreshStages()
				saveSettings()
			end
		end,
	})
	stageDropdown = mapsBox:AddDropdown("Lobby_Level", {
		Text = "Stage",
		Values = {},
		AllowNull = true,
		Callback = function(v)
			if updatingMaps then
				return
			end
			if stageLookup[v] then
				_G.Config.level = stageLookup[v]
				saveSettings()
			end
		end,
	})
	mapsBox:AddDropdown("Lobby_Difficulty", {
		Text = "Difficulty",
		Values = { "Normal", "Hard", "Insane" },
		Default = _G.Config.difficulty,
		Callback = function(v)
			_G.Config.difficulty = v
			saveSettings()
		end,
	})
	addToggle(mapsBox, "friendsOnly", "Friends Only")
	addToggle(mapsBox, "autoJoin", "Auto Join / Start")

	addButton(roomBox, "Join and Start", "Join Map", function()
		LobbyTools:JoinStage(true)
	end)
	addButton(roomBox, "Join / Select Only", "Select Map", function()
		LobbyTools:JoinStage(false)
	end)
	addButton(roomBox, "Leave Room", "Leave Room", function()
		_G.Config.autoJoin = false
		saveSettings()
		LobbyTools:LeaveRoom()
	end)
	roomBox:AddButton({
		Text = "Stop All Automation",
		Func = function()
			LobbyTools:StopAll()
		end,
	})
	roomBox:AddButton({
		Text = "Save Settings",
		Func = safe(function()
			SaveConfig()
			setMessage("Lobby settings saved")
		end),
	})

	statusBox:AddLabel("Macros are blocked in PlaceId 8304191830.", true)
	statusLabel = statusBox:AddLabel(LobbyTools.Message, true)
	resourcesLabel = statusBox:AddLabel("Loading player resources", true)

	local bannerNames = {}
	for id, banner in pairs(Banners) do
		if type(banner) == "table" and banner.active ~= false then
			table.insert(bannerNames, id)
		end
	end
	table.sort(bannerNames)
	if not table.find(bannerNames, _G.Config.banner) then
		_G.Config.banner = bannerNames[1] or "EventClover"
	end
	summonBox:AddDropdown("Lobby_Banner", {
		Text = "Banner",
		Values = bannerNames,
		Default = _G.Config.banner,
		Callback = function(v)
			_G.Config.banner = v
			saveSettings()
		end,
	})

	local pullModes = { ["Single"] = "gems", ["10 Units"] = "gems10", ["Summon Ticket"] = "ticket" }
	local pullDefault = "Single"
	if _G.Config.pullMode == "gems10" then
		pullDefault = "10 Units"
	elseif _G.Config.pullMode == "ticket" then
		pullDefault = "Summon Ticket"
	end
	summonBox:AddDropdown("Lobby_PullMode", {
		Text = "Summon Amount",
		Values = { "Single", "10 Units", "Summon Ticket" },
		Default = pullDefault,
		Callback = function(v)
			_G.Config.pullMode = pullModes[v]
			saveSettings()
		end,
	})
	addToggle(summonBox, "autoSummon", "Auto Summon", "summonDone")
	addButton(summonBox, "Summon Selected Amount", "Summon", function()
		LobbyTools:SummonOnce(false)
	end)
	summonLabel = summonBox:AddLabel("No summons yet", true)

	local sellRarities = { "Rare", "Epic", "Legendary", "Mythic", "Secret" }
	local sellDefaults = {}
	for _, rarity in ipairs(sellRarities) do
		if _G.Config.sellRarities[rarity] then
			table.insert(sellDefaults, rarity)
		end
	end
	sellBox:AddDropdown("Lobby_SellRarities", {
		Text = "Rarity",
		Values = sellRarities,
		Default = sellDefaults,
		Multi = true,
		AllowNull = true,
		Callback = function(selected)
			_G.Config.sellRarities = table.clone(selected)
			saveSettings()
		end,
	})
	local traitNames = { "None" }
	local traitLookup = { None = "none" }
	for id, definition in pairs(Traits) do
		if type(definition) == "table" then
			local tiers = definition.tiers or {}
			local multiple = 0
			for _ in pairs(tiers) do
				multiple = multiple + 1
			end
			for tier in pairs(tiers) do
				local label = (definition.name or id) .. (multiple > 1 and " " .. tostring(tier) or "")
				table.insert(traitNames, label)
				traitLookup[label] = id .. ":" .. tostring(tier)
			end
		end
	end
	table.sort(traitNames)
	local traitDefaults = {}
	for _, label in ipairs(traitNames) do
		if _G.Config.sellTraits[traitLookup[label]] then
			table.insert(traitDefaults, label)
		end
	end
	sellBox:AddDropdown("Lobby_SellTraits", {
		Text = "Traits",
		Values = traitNames,
		Default = traitDefaults,
		Multi = true,
		AllowNull = true,
		Tooltip = "Rarity and every trait must match. None = no trait.",
		Callback = function(selected)
			local values = {}
			for label, enabled in pairs(selected) do
				if enabled and traitLookup[label] then
					values[traitLookup[label]] = true
				end
			end
			_G.Config.sellTraits = values
			saveSettings()
		end,
	})
	addToggle(sellBox, "autoSell", "Enable")
	sellBox:AddLabel("Lobby only. Keeps equipped, locked, shiny & target.", true)
	sellLabel = sellBox:AddLabel("Sold: 0", true)

	addNumberInput(summonOptionsBox, "summonLimit", "Maximum Units Per Run", 1, 100000)
	addNumberInput(summonOptionsBox, "reserve", "Currency to Keep", 0, 1000000000)

	local targetNames = { "None" }
	local targetLookup = { None = "" }
	for id, unit in pairs(Units) do
		if type(unit) == "table" then
			local label = (unit.name or id) .. " [" .. id .. "]"
			table.insert(targetNames, label)
			targetLookup[label] = id
		end
	end
	table.sort(targetNames)
	local targetDefault = "None"
	for label, id in pairs(targetLookup) do
		if id == _G.Config.target then
			targetDefault = label
		end
	end
	summonOptionsBox:AddDropdown("Lobby_Target", {
		Text = "Stop When Obtained",
		Values = targetNames,
		Default = targetDefault,
		Callback = function(v)
			_G.Config.target = targetLookup[v] or ""
			saveSettings()
		end,
	})
	summonOptionsBox:AddLabel(
		"Auto Summon stops at the limit, target unit, currency reserve, or a rejected request.",
		true
	)

	local recipeNames, recipeLookup = LobbyTools:RecipeList()
	local selectedRecipe
	for label, id in pairs(recipeLookup) do
		if id == _G.Config.recipe then
			selectedRecipe = label
		end
	end
	craftBox:AddDropdown("Lobby_Recipe", {
		Text = "Recipe",
		Values = recipeNames,
		Default = selectedRecipe,
		AllowNull = true,
		Callback = function(v)
			_G.Config.recipe = recipeLookup[v] or ""
			saveSettings()
		end,
	})
	addNumberInput(craftBox, "craftLimit", "Maximum Crafts Per Run", 1, 100000)
	addToggle(craftBox, "autoCraft", "Auto Craft", "craftDone")
	addButton(craftBox, "Craft Once", "Craft", function()
		LobbyTools:CraftOnce(false)
	end)
	recipeLabel = materialBox:AddLabel("Choose a recipe", true)

	for _, entry in ipairs({
		{ "Craft Raid Item", "craft_raid_item" },
		{ "Craft Raid Item 2", "craft_raid_item_2" },
		{ "Craft Raid Unit", "craft_raid_unit" },
	}) do
		local label = entry[1]
		local remoteName = entry[2]
		addButton(raidCraftBox, label, label, function()
			LobbyTools:Invoke(remoteName)
			setMessage(label .. " accepted")
		end)
	end
	raidCraftBox:AddLabel("Uses the current raid's recipe and materials.", true)

	codesBox:AddInput("Lobby_CustomCodes", {
		Text = "Extra Codes (comma separated)",
		Default = _G.Config.customCodes,
		Finished = true,
		Callback = function(v)
			_G.Config.customCodes = v
			saveSettings()
		end,
	})
	addButton(codesBox, "Redeem All Codes", "Redeem Codes", function()
		LobbyTools:RedeemCodes()
	end)
	codesBox:AddButton({
		Text = "Retry All Codes",
		Func = safe(function()
			triedCodes = {}
			LobbyTools:Run("Redeem Codes", function()
				LobbyTools:RedeemCodes()
			end)
		end),
	})
	codesBox:AddButton({
		Text = "Copy Code List Source",
		Func = function()
			if setclipboard then
				setclipboard(codesSource)
			end
		end,
	})

	addToggle(rewardsBox, "autoClaim", "Auto Claim Rewards / Quests")
	addButton(rewardsBox, "Claim Available Rewards", "Claim Rewards", function()
		LobbyTools:ClaimRewards()
	end)
	addButton(dailyBox, "Claim Daily Login", "Daily Login", function()
		LobbyTools:ClaimRewards("Daily")
	end)
	addButton(dailyBox, "Claim Daily Missions", "Daily Missions", function()
		LobbyTools:ClaimRewards("Daily Missions")
	end)
	addButton(dailyBox, "Claim Battle Pass", "Battle Pass", function()
		LobbyTools:ClaimRewards("Battle Pass")
	end)
	addButton(eventsBox, "Claim Available Event Rewards", "Event Rewards", function()
		LobbyTools:ClaimRewards("Events")
	end)
	addButton(progressBox, "Claim All Level Rewards", "Level Rewards", function()
		LobbyTools:ClaimRewards("Levels")
	end)
	addButton(progressBox, "Claim All Stage Clear Rewards", "Stage Clear Rewards", function()
		LobbyTools:ClaimRewards("Clears")
	end)
	addButton(progressBox, "Open Level Rewards", "Level Rewards", function()
		LobbyTools:OpenMenu("level_rewards_ui")
	end)
	addButton(questsBox, "Claim All Completed Quests", "Quests", function()
		LobbyTools:ClaimRewards("Quests")
	end)
	addButton(questsBox, "Claim Tournament Rewards", "Tournament", function()
		LobbyTools:ClaimRewards("Tournament")
	end)
	addButton(questsBox, "Open Quests", "Quests", function()
		LobbyTools:OpenMenu("quests_ui")
	end)
	addButton(questsBox, "Open Daily Missions", "Missions", function()
		LobbyTools:OpenMenu("dailymission_ui")
	end)

	local function prettyName(name)
		name = name:gsub("^teleport_to_", "")
		name = name:gsub("_ui$", "")
		name = name:gsub("_", " ")
		name = name:gsub("%f[%a]%l", string.upper)
		return name
	end

	local menuNames = {}
	local menuLookup = {}
	for name, object in pairs(GameUI) do
		if type(object) == "table" and type(object.toggle) == "function" then
			local label = prettyName(name)
			table.insert(menuNames, label)
			menuLookup[label] = name
		end
	end
	table.sort(menuNames)
	local selectedMenu = menuNames[1]
	menusBox:AddDropdown("Lobby_NativeMenu", {
		Text = "Game Menu",
		Values = menuNames,
		Default = selectedMenu,
		AllowNull = true,
		Callback = function(v)
			selectedMenu = v
		end,
	})
	addButton(menusBox, "Open / Close Selected Menu", "Open Menu", function()
		LobbyTools:OpenMenu(menuLookup[selectedMenu])
	end)

	local locationNames = {}
	local locationLookup = {}
	for name, fn in pairs(LobbyService) do
		if type(fn) == "function" and name:match("^teleport_to_") then
			local label = prettyName(name)
			table.insert(locationNames, label)
			locationLookup[label] = name
		end
	end
	table.sort(locationNames)
	local selectedLocation = locationNames[1]
	locationsBox:AddDropdown("Lobby_Location", {
		Text = "Location",
		Values = locationNames,
		Default = selectedLocation,
		AllowNull = true,
		Callback = function(v)
			selectedLocation = v
		end,
	})
	addButton(locationsBox, "Go to Selected Location", "Teleport", function()
		LobbyTools:Teleport(locationLookup[selectedLocation])
	end)
	logLabel = recentBox:AddLabel("No actions yet", true)

	refreshStages()
	LobbyTools.OnUnload = function()
		if not LobbyTools.Destroyed then
			LobbyTools:StopAll()
		end
		LobbyTools:Destroy()
	end
	if game.PlaceId == 8304191830 then
		Tabs.Maps:ShowTab()
	end
	ready = true
	saveSettings()

	LobbyTools.NextClaim = 0
	LobbyTools.NextJoin = 0

	do
		Scheduler:Add({
			Name = "Lobby Craft",
			Priority = 0,
			Cooldown = 0.8,
			When = function()
				return not LobbyTools.Destroyed and game.PlaceId == 8304191830
			end,
			Run = function()
				if LobbyTools.Destroyed or game.PlaceId ~= 8304191830 then
					return
				end
				pcall(function()
					if _G.Config.autoCraft and not LobbyTools.Busy then
						if _G.Config.craftDone >= _G.Config.craftLimit then
							_G.Config.autoCraft = false
							saveSettings()
						else
							LobbyTools:Run("Auto Craft", function()
								LobbyTools:CraftOnce(true)
							end, "autoCraft")
						end
					end
				end)
			end,
		})
	end

	do
		Scheduler:Add({
			Name = "Lobby Auto Sell",
			Priority = 10,
			Cooldown = 2,
			When = function()
				return not LobbyTools.Destroyed
					and game.PlaceId == 8304191830
					and _G.Config.autoSell
					and not LobbyTools.Busy
			end,
			Run = function()
				if not _G.Config.autoSell or LobbyTools.Busy then
					return
				end
				LobbyTools:Run("Auto Sell", function()
					LobbyTools:SellUnits()
				end, "autoSell")
			end,
		})
	end

	do
		Scheduler:Add({
			Name = "Lobby Summon",
			Priority = 0,
			Cooldown = 0.8,
			When = function()
				return not LobbyTools.Destroyed and game.PlaceId == 8304191830
			end,
			Run = function()
				if LobbyTools.Destroyed or game.PlaceId ~= 8304191830 then
					return
				end
				pcall(function()
					if _G.Config.autoSummon and not _G.Config.autoCraft and not LobbyTools.Busy then
						if _G.Config.summonDone >= _G.Config.summonLimit then
							_G.Config.autoSummon = false
							saveSettings()
						else
							LobbyTools:Run("Auto Summon", function()
								LobbyTools:SummonOnce(true)
							end, "autoSummon")
						end
					end
				end)
			end,
		})
	end

	do
		Scheduler:Add({
			Name = "Lobby Rewards",
			Priority = 0,
			Cooldown = 0.8,
			When = function()
				return not LobbyTools.Destroyed and game.PlaceId == 8304191830
			end,
			Run = function()
				if LobbyTools.Destroyed or game.PlaceId ~= 8304191830 then
					return
				end
				pcall(function()
					if
						_G.Config.autoClaim
						and not _G.Config.autoCraft
						and not _G.Config.autoSummon
						and not LobbyTools.Busy
						and os.clock() >= LobbyTools.NextClaim
					then
						LobbyTools.NextClaim = os.clock() + 45
						LobbyTools:Run("Auto Claim", function()
							LobbyTools:ClaimRewards()
						end, "autoClaim")
					end
				end)
			end,
		})
	end

	do
		Scheduler:Add({
			Name = "Lobby Join",
			Priority = 0,
			Cooldown = 0.8,
			When = function()
				return not LobbyTools.Destroyed and game.PlaceId == 8304191830
			end,
			Run = function()
				if LobbyTools.Destroyed or game.PlaceId ~= 8304191830 then
					return
				end
				pcall(function()
					if LobbyTools.JoiningRoom and os.clock() >= LobbyTools.JoinDeadline then
						LobbyTools.JoiningRoom = nil
						_G.Config.autoJoin = false
						saveSettings()
						setMessage("Stage did not start; Auto Join stopped", true)
					end
					if
						_G.Config.autoJoin
						and not _G.Config.autoCraft
						and not _G.Config.autoSummon
						and not LobbyTools.Busy
						and not LobbyTools.JoiningRoom
						and os.clock() >= LobbyTools.NextJoin
					then
						if _G.Config.autoClaim and os.clock() >= LobbyTools.NextClaim then
							return
						end
						LobbyTools.NextJoin = os.clock() + 6
						LobbyTools:Run("Auto Join", function()
							LobbyTools:JoinStage(true)
						end, "autoJoin")
					end
				end)
			end,
		})
	end

	-- Update status labels only when their text changes.
	do
		local lastText = {}
		Scheduler:Add({
			Name = "Lobby UI",
			Priority = 0,
			Cooldown = 0.3,
			When = function()
				return not LobbyTools.Destroyed
			end,
			Run = function()
				for key, toggle in pairs(controls) do
					if type(_G.Config[key]) == "boolean" and toggle.Value ~= _G.Config[key] then
						syncing = true
						toggle:SetValue(_G.Config[key])
						syncing = false
					end
				end

				local statusText = (LobbyTools.MessageError and "Error: " or "") .. LobbyTools.Message
				if LobbyTools.Busy then
					statusText = statusText .. "\nRunning: " .. LobbyTools.Busy
				end

				local labels = {
					{
						"sell",
						sellLabel,
						"Sold: " .. tostring(LobbyTools.SoldUnits or 0),
					},
					{ "status", statusLabel, statusText },
					{
						"resources",
						resourcesLabel,
						"Gems: "
							.. getCurrency("Gems")
							.. " · Gold: "
							.. getCurrency("Gold")
							.. (game.PlaceId == 8304191830 and "\nMacros: DISABLED" or "\nLobby automation: DISABLED"),
					},
					{ "log", logLabel, #history > 0 and table.concat(history, "\n") or "No actions yet" },
					{
						"summon",
						summonLabel,
						_G.Config.banner .. " · Units: " .. _G.Config.summonDone .. "/" .. _G.Config.summonLimit,
					},
					{ "recipe", recipeLabel, LobbyTools:RecipeText() },
				}
				for _, entry in ipairs(labels) do
					if lastText[entry[1]] ~= entry[3] then
						entry[2]:SetText(entry[3])
						lastText[entry[1]] = entry[3]
					end
				end
			end,
		})
	end

	print(
		"PROJECT_A_LOBBY_READY",
		game.PlaceId == 8304191830 and "macros=BLOCKED" or "lobby=BLOCKED",
		"recipes=" .. #recipeNames,
		"menus=" .. #menuNames
	)
end

--// Macro engine -------------------------------------------------------------

if game.PlaceId ~= 8304191830 then
	assert(type(hookmetamethod) == "function", "hookmetamethod is not supported")
end

if _G.Config.mode ~= "time" then
	_G.Config.mode = "wave"
end
_G.Config.timeout = math.clamp(_G.Config.timeout, 10, 180)
_G.Config.returnWave = math.clamp(math.floor(_G.Config.returnWave), 1, 1000000)

local macroFolder = mainFolder
local allowedRemotes =
	{ spawn_unit = true, upgrade_unit_ingame = true, sell_unit_ingame = true, change_priority = true }
local actionNames =
	{ spawn_unit = "Place", upgrade_unit_ingame = "Upgrade", sell_unit_ingame = "Sell", change_priority = "Target" }

local Macro = {
	State = "idle",
	Data = nil,
	Pending = 0,
	ReturnTicket = 0,
	StartTicket = 0,
}
_G.TowerMacro = Macro

local unitKeys = {}
local foundUnits = {}
local serial = 0
local generation = 0
local sequence = 0
local recordStart = 0
local level = nil
local statusLabel, detailsLabel, logLabel
local nameBox, profileList, playToggle
local lobbyConnection
local settingsReady = false
local syncingControls = false
local history = {}

function getUnits()
	local folder = workspace:FindFirstChild("_UNITS")
	if folder then
		return folder:GetChildren()
	end
	return {}
end

local function isMine(unit)
	return unit:IsA("Model")
		and getValue(unit:FindFirstChild("_stats"), "player") == game:GetService("Players").LocalPlayer
end

function getCash()
	return tonumber(getValue(game:GetService("Players").LocalPlayer:FindFirstChild("_stats"), "resource")) or 0
end

function getWave()
	return tonumber(getValue(workspace, "_wave_num")) or 0
end

function getWaveTime()
	return tonumber(getValue(workspace, "_wave_time")) or 0
end

local function setMessage(text, isError)
	Macro.Message = text
	Macro.MessageError = isError
end

local function addLog(text)
	table.insert(history, 1, text)
	if #history > 7 then
		table.remove(history)
	end
end

local function saveSettings()
	if not settingsReady or Macro.State == "destroyed" or not _G.Config.autoSave then
		return
	end
	local ok, err = pcall(SaveConfig)
	if not ok then
		setMessage("Settings not saved: " .. tostring(err), true)
	end
end

local function getUnitInfo(unit)
	if not unitKeys[unit] then
		serial = serial + 1
		unitKeys[unit] = tostring(serial)
	end
	local stats = unit:FindFirstChild("_stats")
	local pos = unit:GetPivot().Position
	return {
		k = unitKeys[unit],
		id = getValue(stats, "id") or unit.Name,
		uuid = getValue(stats, "uuid"),
		spawn = unit:GetAttribute("_SPAWN_UNIT_UUID"),
		p = { pos.X, pos.Y, pos.Z },
	}
end

local function findUnit(ref)
	local cached = foundUnits[ref.k]
	if cached and cached.Parent == workspace:FindFirstChild("_UNITS") and isMine(cached) then
		return cached
	end

	local best, bestDistance
	local point = Vector3.new(table.unpack(ref.p))
	for _, unit in ipairs(getUnits()) do
		if isMine(unit) then
			local stats = unit:FindFirstChild("_stats")
			local sameId = (getValue(stats, "id") or unit.Name) == ref.id
			local sameUuid = not ref.uuid or getValue(stats, "uuid") == ref.uuid
			if sameId and sameUuid then
				local taken = false
				for key, other in pairs(foundUnits) do
					if key ~= ref.k and other == unit then
						taken = true
						break
					end
				end
				local distance = (unit:GetPivot().Position - point).Magnitude
				if not taken and (not bestDistance or distance < bestDistance) then
					best = unit
					bestDistance = distance
				end
			end
		end
	end

	if best and bestDistance <= 8 then
		foundUnits[ref.k] = best
		return best
	end
	error("Unit not found: " .. tostring(ref.id), 0)
end

local function encode(v, seen, depth)
	seen = seen or {}
	depth = depth or 0
	assert(depth < 24, "Data nesting limit exceeded")

	local kind = typeof(v)
	if kind == "nil" then
		return { t = "nil" }
	elseif kind == "string" or kind == "boolean" then
		return v
	elseif kind == "number" then
		assert(v == v and math.abs(v) < math.huge, "Invalid number")
		return v
	elseif kind == "CFrame" then
		return { t = kind, v = { v:GetComponents() } }
	elseif kind == "Vector3" then
		return { t = kind, v = { v.X, v.Y, v.Z } }
	elseif kind == "Vector2" then
		return { t = kind, v = { v.X, v.Y } }
	elseif kind == "Color3" then
		return { t = kind, v = { v.R, v.G, v.B } }
	elseif kind == "EnumItem" then
		local enumName = tostring(v.EnumType):gsub("^Enum%.", "")
		return { t = kind, e = enumName, v = v.Name }
	elseif kind == "Instance" then
		local unit = v
		while unit and unit.Parent ~= workspace:FindFirstChild("_UNITS") do
			unit = unit.Parent
		end
		if unit and isMine(unit) then
			local path = {}
			local child = v
			while child ~= unit do
				table.insert(path, 1, child.Name)
				child = child.Parent
			end
			return { t = "unit", ref = getUnitInfo(unit), path = path }
		end
		if v == game:GetService("Players").LocalPlayer then
			return { t = "player" }
		end
		error("Unsupported instance: " .. v:GetFullName(), 0)
	elseif kind == "table" then
		assert(not seen[v], "Cyclic data")
		seen[v] = true
		local list = {}
		for key, item in pairs(v) do
			assert(#list < 256, "Table size limit exceeded")
			table.insert(list, { encode(key, seen, depth + 1), encode(item, seen, depth + 1) })
		end
		seen[v] = nil
		return { t = "table", v = list }
	end
	error("Unsupported type: " .. kind, 0)
end

local function decode(v)
	if type(v) ~= "table" then
		return v
	end

	if v.t == "nil" then
		return nil
	elseif v.t == "CFrame" then
		return CFrame.new(table.unpack(v.v))
	elseif v.t == "Vector3" then
		return Vector3.new(table.unpack(v.v))
	elseif v.t == "Vector2" then
		return Vector2.new(table.unpack(v.v))
	elseif v.t == "Color3" then
		return Color3.new(table.unpack(v.v))
	elseif v.t == "EnumItem" then
		return Enum[v.e][v.v]
	elseif v.t == "player" then
		return game:GetService("Players").LocalPlayer
	elseif v.t == "unit" then
		local object = findUnit(v.ref)
		for _, name in ipairs(v.path) do
			object = object:FindFirstChild(name)
			assert(object, "Unit child not found: " .. name)
		end
		return object
	end

	assert(v.t == "table", "Invalid macro data type")
	local result = {}
	for _, pair in ipairs(v.v) do
		result[decode(pair[1])] = decode(pair[2])
	end
	return result
end

local function profilePath(name)
	name = tostring(name or "default")
	name = name:gsub("^%s+", "")
	name = name:gsub("%s+$", "")
	assert(#name > 0 and #name <= 70 and not name:find('[%c<>:"/\\|?*]') and not name:find("%.%."), "Invalid file name")
	return macroFolder .. "/" .. name .. ".json"
end

local function getMacroName()
	if nameBox then
		return nameBox.Value
	end
	return "default"
end

function isGameFinished()
	return getValue(workspace:FindFirstChild("_DATA"), "GameFinished") == true
end

local function getMapInfo()
	assert(game.PlaceId ~= 8304191830, "Macros are disabled in the lobby")
	local mapConfig = workspace:FindFirstChild("_MAP_CONFIG")
	assert(mapConfig and getValue(mapConfig, "IsLobby") == false, "Enter a match first")
	if level then
		return level
	end

	local remote = mapConfig:FindFirstChild("GetLevelData")
	assert(remote, "Map data remote not found")

	local done = false
	local result, err
	maid.OneShots:Spawn(function()
		local ok, data = pcall(function()
			return Network:Send(remote)
		end)
		if ok then
			result = data
		else
			err = data
		end
		done = true
	end)

	local deadline = os.clock() + 8
	repeat
		task.wait(0.05)
	until done or os.clock() >= deadline or Macro.State == "destroyed"
	assert(done and type(result) == "table" and result.id and result.map, tostring(err or "Unable to read map data"))

	level = {
		place = game.PlaceId,
		id = result.id,
		map = result.map,
		difficulty = result._difficulty or "",
		title = (result._location_name or result.map) .. " / " .. (result.name or result.id),
	}
	return level
end

local function checkMacro(data)
	assert(
		type(data) == "table" and data.version == 1 and type(data.map) == "table" and type(data.actions) == "table",
		"Invalid macro file"
	)
	assert(
		type(data.map.id) == "string" and type(data.map.map) == "string" and type(data.map.place) == "number",
		"Invalid map data"
	)
	assert(#data.actions <= 5000, "Macro exceeds 5000 actions")

	local lastAt = -1
	for index, a in ipairs(data.actions) do
		assert(type(a) == "table" and allowedRemotes[a.remote] and type(a.args) == "table", "Invalid macro action")
		assert(type(a.at) == "number" and a.at == a.at and a.at >= lastAt and a.at < 86400, "Invalid macro timing")
		assert(type(a.wave) == "number" and a.wave >= 0 and a.wave < 100000, "Invalid wave data")
		assert(
			type(a.timer) == "number" and a.timer > -86400 and a.timer < 86400,
			"Invalid wave timer at action " .. index
		)
		assert(type(a.cost) == "number" and a.cost >= 0 and a.cost < 1e12, "Invalid unit cost")
		if a.remote == "spawn_unit" then
			assert(type(a.unit) == "table" and type(a.unit.k) == "string", "Missing placement data")
		end
		if a.remote == "change_priority" then
			assert(type(a.priority) == "string" and type(a.target) == "table", "Missing target priority data")
		end
		lastAt = a.at
	end
	return data
end

function Macro:List()
	local names = {}
	if isfolder(macroFolder) then
		for _, path in ipairs(listfiles(macroFolder)) do
			local name = path:match("([^/\\]+)%.json$")
			if name and pcall(profilePath, name) then
				table.insert(names, name)
			end
		end
	end
	table.sort(names)
	return names
end

function Macro:RefreshProfiles(selected)
	local names = self:List()
	if profileList then
		profileList:SetValues(names)
		if selected then
			profileList:SetValue(selected)
		end
	end
	return names
end

function Macro:Delete(name)
	assert(self.State == "idle" and self.Pending == 0, "Stop before deleting")
	name = name or getMacroName()
	local path = profilePath(name)
	assert(isfile(path), "Macro file not found")
	delfile(path)
	_G.Config.playMacro = false
	self.StartTicket = self.StartTicket + 1
	if self.LoadedName == name then
		self.Data = nil
		self.LoadedName = nil
		self.RecordingName = nil
		self.Saved = false
		self.PlaySession = nil
		self.FailedAction = nil
		self.Completed = false
		self.LastCompleted = 0
		unitKeys = {}
		foundUnits = {}
	end
	local names = self:RefreshProfiles()
	_G.Config.profile = names[1] or "default"
	if profileList then
		profileList:SetValue(names[1])
	end
	if nameBox then
		nameBox:SetValue(_G.Config.profile)
	end
	saveSettings()
	setMessage("Deleted: " .. name)
end

function Macro:Backup()
	if not self.Data or #self.Data.actions == 0 then
		return
	end
	local data = table.clone(self.Data)
	data.actions = table.clone(self.Data.actions)
	table.sort(data.actions, function(a, b)
		return a.seq < b.seq
	end)
	data.recordingName = self.RecordingName or self.LoadedName or getMacroName()
	writefile(settingsFolder .. "/recording.json", game:GetService("HttpService"):JSONEncode(data))
end

function Macro:Save(name)
	assert(self.State == "idle", "Stop before saving")
	assert(self.Data, "No macro available")
	assert(self.Pending == 0, "Waiting for action confirmation")
	local backedUp, backupError = pcall(self.Backup, self)
	if not backedUp then
		addLog("Backup failed: " .. tostring(backupError))
	end

	table.sort(self.Data.actions, function(a, b)
		return a.seq < b.seq
	end)
	checkMacro(self.Data)

	local path = profilePath(name or getMacroName())
	writefile(path, game:GetService("HttpService"):JSONEncode(self.Data))
	self.Saved = true
	self.LoadedName = path:match("([^/]+)%.json$")
	self:RefreshProfiles(self.LoadedName)
	setMessage("Saved: " .. path)
	return path
end

function Macro:Load(name, recovery)
	assert(self.State == "idle", "Stop first")
	assert(
		not recovery or not self.Data or self.Saved or #self.Data.actions == 0,
		"Save the current macro before recovering another recording"
	)
	name = name or getMacroName()

	local raw = readfile(recovery and settingsFolder .. "/recording.json" or profilePath(name))
	assert(#raw < 8 * 1024 * 1024, "File exceeds size limit")
	local data = checkMacro(game:GetService("HttpService"):JSONDecode(raw))
	if recovery then
		name = data.recordingName or name
		profilePath(name)
		local base = #name <= 55 and name .. "_recovered" or "recovered_" .. os.time()
		local suffix = 1
		while isfile(profilePath(name)) do
			name = base .. "_" .. suffix
			suffix = suffix + 1
		end
		self.RecordingName = name
	end

	self.Data = data
	self.Saved = not recovery
	self.LoadedName = name
	unitKeys = {}
	foundUnits = {}
	self.PlaySession = nil
	self.FailedAction = nil
	self.Completed = false
	self.LastCompleted = 0
	if nameBox then
		nameBox:SetValue(name)
	end
	setMessage((recovery and "Recovered " or "Loaded ") .. #data.actions .. " actions")
	return data
end

function Macro:Record()
	assert(game.PlaceId ~= 8304191830, "Macros are disabled in the lobby")
	assert(self.State == "idle", "Stop first")
	assert(not self.Data or self.Saved or #self.Data.actions == 0, "Save the current macro before recording a new one")
	_G.Config.playMacro = false
	saveSettings()

	self.State = "preparing"
	local ok, info = pcall(getMapInfo)
	if self.State ~= "preparing" then
		return
	end
	self.State = "idle"
	assert(ok, info)
	assert(not isGameFinished(), "This match has ended")

	-- dont overwrite old macro, add _2 _3 ...
	local recordName = getMacroName()
	profilePath(recordName)
	local baseName = recordName
	local suffix = 2
	while isfile(profilePath(recordName)) do
		if #baseName <= 60 then
			recordName = baseName .. "_" .. suffix
		else
			recordName = "macro_" .. os.time() .. "_" .. suffix
		end
		suffix = suffix + 1
	end

	self.RecordingName = recordName
	self.LoadedName = recordName
	if nameBox then
		nameBox:SetValue(recordName)
	end

	generation = generation + 1
	sequence = 0
	serial = 0
	unitKeys = {}
	foundUnits = {}
	history = {}
	self.Data = { version = 1, map = info, actions = {}, created = os.time() }
	self.PlaySession = nil
	self.FailedAction = nil
	self.Completed = false
	self.LastCompleted = 0
	self.Pending = 0
	self.Saved = false
	recordStart = os.clock()
	self.State = "recording"
	setMessage("Recording: Place / Upgrade / Sell")
	addLog("Recording started at wave " .. getWave())
end

local function snapshotUnits()
	local result = {}
	for _, unit in ipairs(getUnits()) do
		if isMine(unit) then
			result[unit] = true
		end
	end
	return result
end

local function findNewUnit(before, args)
	local point
	for i = 1, args.n do
		if typeof(args[i]) == "CFrame" then
			point = args[i].Position
		end
		if typeof(args[i]) == "Vector3" then
			point = args[i]
		end
	end

	local best, bestDistance
	for _, unit in ipairs(getUnits()) do
		if not before[unit] and isMine(unit) then
			local uuid = getValue(unit:FindFirstChild("_stats"), "uuid")
			if type(args[1]) ~= "string" or uuid == args[1] then
				local distance = 0
				if point then
					distance = (unit:GetPivot().Position - point).Magnitude
				end
				if not bestDistance or distance < bestDistance then
					best = unit
					bestDistance = distance
				end
			end
		end
	end
	return best
end

local UnitData
local function getCost(a, unit)
	if not UnitData then
		UnitData = require(game:GetService("ReplicatedStorage").src.Data.Units)
	end
	local stats = unit and unit:FindFirstChild("_stats")
	local ref = a.target or a.unit or {}
	local unitConfig = UnitData[getValue(stats, "id") or ref.id]
	if not unitConfig then
		return a.cost or 0
	end

	local baseCost = unitConfig.cost
	local multiplier = 1
	if a.remote == "upgrade_unit_ingame" then
		local tier = a.level or ((tonumber(getValue(stats, "upgrade")) or 0) + 1)
		local upgrade = unitConfig.upgrade and unitConfig.upgrade[tier]
		baseCost = upgrade and upgrade.cost
		multiplier = tonumber(getValue(stats, "upgrade_cost_multiplier")) or 1
	elseif a.remote ~= "spawn_unit" then
		return a.cost or 0
	end

	local modifiers = workspace:FindFirstChild("_DATA")
	modifiers = modifiers and modifiers:FindFirstChild("LevelModifiers")
	local scale = tonumber(getValue(modifiers, "player_cost_scale")) or 1
	if type(baseCost) == "number" then
		return math.max(0, math.ceil(baseCost * multiplier * scale))
	end
	return a.cost or 0
end

function getActionGap(previous, current)
	if not previous then
		return 0
	end
	local gap = math.max(0, current.at - previous.at)
	if previous.wave == current.wave then
		return gap
	end
	return math.min(gap, 1)
end

--// Macro recording ----------------------------------------------------------

local function captureBefore(remoteName, args)
	local before = {}
	if typeof(args[1]) == "Instance" then
		local stats = args[1].FindFirstChild(args[1], "_stats")
		if stats then
			for _, name in ipairs({ "upgrade", "priority", "total_spent" }) do
				local value = stats.FindFirstChild(stats, name)
				if value then
					before[name] = value.Value
				end
			end
		end
	end
	if remoteName == "spawn_unit" then
		before.units = {}
		local folder = workspace.FindFirstChild(workspace, "_UNITS")
		if folder then
			for _, unit in ipairs(folder.GetChildren(folder)) do
				before.units[unit] = true
			end
		end
	end
	return before
end

local function startCapture(remote, args, calledAt, before)
	if Macro.State ~= "recording" or remote.Parent ~= remotes or not allowedRemotes[remote.Name] then
		return
	end
	assert(#Macro.Data.actions < 5000, "Reached 5000 actions")

	sequence = sequence + 1
	local a = {
		seq = sequence,
		remote = remote.Name,
		at = (calledAt or os.clock()) - recordStart,
		wave = getWave(),
		timer = getWaveTime(),
		cost = 0,
		args = encode(args),
	}

	local unit
	if typeof(args[1]) == "Instance" then
		unit = args[1]
	end
	local stats = unit and unit:FindFirstChild("_stats")
	local context = {
		a = a,
		data = Macro.Data,
		gen = generation,
		args = args,
		unit = unit,
		upgrade = before and before.upgrade or tonumber(getValue(stats, "upgrade")) or 0,
		priority = before and before.priority or getValue(stats, "priority"),
		spent = before and before.total_spent or tonumber(getValue(stats, "total_spent")) or 0,
	}
	if remote.Name == "spawn_unit" then
		context.before = before and before.units or snapshotUnits()
	end
	if unit and isMine(unit) then
		a.target = getUnitInfo(unit)
	end

	Macro.Pending = Macro.Pending + 1
	return context
end

local function confirmCapture(context)
	maid.OneShots:Spawn(function()
		local ok, err = pcall(function()
			local a = context.a
			local unit = context.unit
			local deadline = os.clock() + 5
			local success = false

			repeat
				if a.remote == "spawn_unit" then
					unit = findNewUnit(context.before, context.args)
					success = unit ~= nil
				elseif a.remote == "upgrade_unit_ingame" then
					success = unit
						and unit.Parent
						and (tonumber(getValue(unit:FindFirstChild("_stats"), "upgrade")) or 0) > context.upgrade
				elseif a.remote == "change_priority" then
					success = unit
						and unit.Parent
						and getValue(unit:FindFirstChild("_stats"), "priority") ~= context.priority
				else
					success = unit and (unit.Parent ~= workspace:FindFirstChild("_UNITS") or not isMine(unit))
				end
				if success or generation ~= context.gen then
					break
				end
				task.wait(0.05)
			until os.clock() >= deadline

			if generation ~= context.gen then
				return
			end
			assert(success, "Unable to confirm " .. a.remote)

			local stats = unit and unit:FindFirstChild("_stats")
			if a.remote == "spawn_unit" then
				a.unit = getUnitInfo(unit)
				a.cost = tonumber(getValue(stats, "total_spent")) or 0
			elseif a.remote == "upgrade_unit_ingame" then
				a.level = getValue(stats, "upgrade")
				local spent = tonumber(getValue(stats, "total_spent")) or context.spent
				a.cost = math.max(0, spent - context.spent)
			elseif a.remote == "change_priority" then
				a.priority = getValue(stats, "priority")
			end
			if a.cost == 0 then
				a.cost = getCost(a, unit)
			end

			table.insert(context.data.actions, a)
			local backedUp, backupError = pcall(Macro.Backup, Macro)
			if not backedUp then
				setMessage("Backup failed: " .. tostring(backupError), true)
			end
			local extra = a.priority and " " .. a.priority or ""
			addLog(string.format("%03d  W%d  %.1fs  %s%s", a.seq, a.wave, a.at, actionNames[a.remote], extra))
		end)

		if generation == context.gen then
			Macro.Pending = math.max(0, Macro.Pending - 1)
			if not ok then
				setMessage("Action skipped: " .. tostring(err), true)
			end
		end
	end)
end

local function onRemoteCalled(remote, args, calledAt, before)
	local ok, context = pcall(startCapture, remote, args, calledAt, before)
	if not ok then
		setMessage("Recording failed: " .. tostring(context), true)
	elseif context then
		task.defer(confirmCapture, context)
	end
end

-- hook only once per client, re-run just swaps the callback
local bridge = _G.TowerMacroBridge
if bridge and bridge.version ~= 3 then
	bridge.macro = nil
	bridge.capture = nil
	bridge = nil
end
if not bridge then
	bridge = { hooked = false, version = 3 }
	_G.TowerMacroBridge = bridge
end
if game.PlaceId ~= 8304191830 and not bridge.hooked then
	local oldNamecall
	oldNamecall = hookmetamethod(
		game,
		"__namecall",
		newcclosure(function(self, ...)
			if
				game.PlaceId ~= 8304191830
				and getnamecallmethod() == "InvokeServer"
				and bridge.macro
				and bridge.macro.State == "recording"
				and self.Parent == bridge.remotes
				and bridge.allowed[self.Name]
			then
				local args = table.pack(...)
				local calledAt = os.clock()
				local ok, before = pcall(bridge.snapshot, self.Name, args)
				task.defer(bridge.capture, self, args, calledAt, ok and before or nil)
			end
			return oldNamecall(self, ...)
		end)
	)
	bridge.hooked = true
end
bridge.macro = Macro
bridge.remotes = remotes
bridge.allowed = allowedRemotes
bridge.capture = onRemoteCalled
bridge.snapshot = captureBefore

--// Macro playback -----------------------------------------------------------

function Macro:Stop()
	if self.State == "destroyed" then
		return
	end
	_G.Config.playMacro = false
	saveSettings()

	if self.State == "recording" or self.State == "stopping" then
		self.State = "stopping"
		setMessage("Waiting for the last action")
		local deadline = os.clock() + 6
		repeat
			task.wait(0.05)
		until self.Pending == 0 or os.clock() >= deadline or self.State == "destroyed"
		if self.State == "destroyed" then
			return
		end
		self.State = "idle"
		self:Save(self.RecordingName)
		self.Saved = true
	else
		generation = generation + 1
		self.State = "idle"
		setMessage("Stopped")
	end
end

local function checkStillPlaying(token)
	assert(game.PlaceId ~= 8304191830, "Macros are disabled in the lobby")
	assert(Macro.State == "playing" and generation == token, "Playback stopped")
	assert(not isGameFinished(), "Match ended")
end

local function invokeRemote(remote, args, token)
	local done = false
	local result
	maid.OneShots:Spawn(function()
		result = table.pack(pcall(function()
			return Network:Send(remote, table.unpack(args, 1, args.n))
		end))
		done = true
	end)

	local deadline = os.clock() + 15
	repeat
		checkStillPlaying(token)
		task.wait(0.05)
	until done or os.clock() >= deadline

	assert(done, "Remote timed out; stopped to prevent duplicate actions")
	assert(result[1], tostring(result[2]))
	assert(result[2] ~= false, "Server rejected the action; playback stopped")
end

local function isActionDone(a, unit, before, args, oldUpgrade)
	if a.remote == "spawn_unit" then
		local spawned = findNewUnit(before, args)
		if spawned then
			foundUnits[a.unit.k] = spawned
			return true
		end
		return false
	elseif a.remote == "upgrade_unit_ingame" then
		return unit and unit.Parent and (tonumber(getValue(unit:FindFirstChild("_stats"), "upgrade")) or 0) > oldUpgrade
	elseif a.remote == "change_priority" then
		return unit and unit.Parent and getValue(unit:FindFirstChild("_stats"), "priority") == a.priority
	end
	return unit and (unit.Parent ~= workspace:FindFirstChild("_UNITS") or not isMine(unit))
end

function Macro:Play(startIndex)
	assert(game.PlaceId ~= 8304191830, "Macros are disabled in the lobby")
	assert(self.State == "idle", "Stop first")

	local name = getMacroName()
	if not self.Data or (self.LoadedName and self.LoadedName ~= name) then
		assert(isfile(profilePath(name)), "No saved macro named '" .. name .. "'. Record and save a macro first.")
		assert(
			not self.Data or self.Saved or #self.Data.actions == 0,
			"Save the current macro before loading another one"
		)
		self:Load(name)
	end

	local data = checkMacro(self.Data)
	assert(#data.actions > 0, "Macro has no actions")
	startIndex = startIndex or 1
	assert(
		type(startIndex) == "number"
			and startIndex == math.floor(startIndex)
			and startIndex >= 1
			and startIndex <= #data.actions,
		"Invalid resume action"
	)
	if startIndex > 1 then
		assert(self.PlaySession == game.JobId, "Resume is only available in the same match")
	end

	self.State = "preparing"
	local ok, current = pcall(getMapInfo)
	if self.State ~= "preparing" then
		return
	end
	self.State = "idle"
	assert(ok, current)

	local sameMap = current.place == data.map.place
		and current.id == data.map.id
		and current.map == data.map.map
		and current.difficulty == data.map.difficulty
	assert(sameMap, "Map, stage, or difficulty does not match the macro")
	assert(not isGameFinished(), "This match has ended")
	if startIndex == 1 and _G.Config.mode == "wave" then
		assert(getWave() <= data.actions[1].wave, "Starting wave has passed; start a new match")
	end

	generation = generation + 1
	local token = generation
	local mode = _G.Config.mode
	local playStart = os.clock()
	if startIndex > 1 then
		playStart = os.clock() - data.actions[startIndex].at
	end
	foundUnits = {}
	self.State = "playing"

	-- resume: find the units that are still alive from earlier actions
	if startIndex > 1 then
		local alive = {}
		for i = 1, startIndex - 1 do
			local a = data.actions[i]
			if a.remote == "spawn_unit" then
				alive[a.unit.k] = a.unit
			elseif a.remote == "sell_unit_ingame" and a.target then
				alive[a.target.k] = nil
			end
		end
		for i = 1, startIndex - 1 do
			local a = data.actions[i]
			if a.remote == "spawn_unit" and alive[a.unit.k] then
				pcall(findUnit, alive[a.unit.k])
			end
		end
	end

	self.PlaySession = game.JobId
	self.FailedAction = nil
	self.Completed = false
	self.LastCompleted = startIndex - 1

	maid.OneShots:Spawn(function()
		local lastSent
		local success, err = pcall(function()
			for index = startIndex, #data.actions do
				local a = data.actions[index]
				self.CurrentAction = index
				self.CurrentRemote = a.remote

				-- wait until it's time for this action
				local giveUpAt = os.clock() + 1800
				while true do
					checkStillPlaying(token)
					local due
					if mode == "time" then
						due = os.clock() - playStart >= a.at
					else
						due = getWave() > a.wave or (getWave() == a.wave and getWaveTime() <= a.timer)
					end
					if due and lastSent then
						due = os.clock() - lastSent >= getActionGap(data.actions[index - 1], a)
					end
					if due then
						break
					end
					assert(os.clock() < giveUpAt, "Wait exceeded 30 minutes")
					setMessage(string.format("Waiting %d/%d · W%d · %.1fs", index, #data.actions, a.wave, a.at))
					task.wait(0.1)
				end

				local args = decode(a.args)
				assert(type(args.n) == "number" and args.n >= 0 and args.n <= 256, "Invalid argument count")
				local unit = a.target and findUnit(a.target) or nil
				local stats = unit and unit:FindFirstChild("_stats")

				local alreadyDone = false
				if a.remote == "upgrade_unit_ingame" and unit and a.level then
					alreadyDone = (tonumber(getValue(stats, "upgrade")) or 0) >= a.level
				elseif a.remote == "change_priority" and unit then
					alreadyDone = getValue(stats, "priority") == a.priority
				end

				if alreadyDone then
					lastSent = os.clock()
				else
					local cost = getCost(a, unit)
					local cashDeadline = os.clock() + _G.Config.timeout
					while getCash() + 0.01 < cost do
						checkStillPlaying(token)
						assert(os.clock() < cashDeadline, "Insufficient cash before timeout")
						setMessage(string.format("Waiting for cash %d / %d", getCash(), cost))
						task.wait(0.15)
					end
					checkStillPlaying(token)

					local remote = remotes:FindFirstChild(a.remote)
					assert(remote and remote:IsA("RemoteFunction"), "Remote not found: " .. a.remote)
					local before
					if a.remote == "spawn_unit" then
						before = snapshotUnits()
					end
					local oldUpgrade = unit and tonumber(getValue(stats, "upgrade")) or 0
					lastSent = os.clock()

					if a.remote == "change_priority" then
						assert(unit and type(a.priority) == "string", "Missing target priority data")
						-- priority cycles one step per call, so keep clicking until it matches
						local tries = 1
						if args.n == 1 then
							tries = 8
						end
						for _ = 1, tries do
							local oldPriority = getValue(unit:FindFirstChild("_stats"), "priority")
							if oldPriority == a.priority then
								break
							end
							invokeRemote(remote, args, token)
							local deadline = os.clock() + 6
							repeat
								checkStillPlaying(token)
								if getValue(unit:FindFirstChild("_stats"), "priority") ~= oldPriority then
									break
								end
								task.wait(0.05)
							until os.clock() >= deadline
						end
					else
						invokeRemote(remote, args, token)
					end

					local verified = false
					local deadline = os.clock() + 6
					repeat
						checkStillPlaying(token)
						verified = isActionDone(a, unit, before, args, oldUpgrade)
						if verified then
							break
						end
						task.wait(0.05)
					until os.clock() >= deadline
					assert(verified, "Server action was not observed; check placement, cooldown, or available cash")
				end

				self.LastCompleted = index
				addLog(string.format("Play %d/%d · %s", index, #data.actions, a.remote))
			end
		end)

		if generation == token and self.State ~= "destroyed" then
			self.State = "idle"
			self.Completed = success
			if success then
				self.FailedAction = nil
				setMessage("Playback complete")
			else
				self.FailedAction = self.CurrentAction
				setMessage(
					string.format(
						"Action %d/%d (%s): %s",
						self.CurrentAction or startIndex,
						#data.actions,
						self.CurrentRemote or "unknown",
						tostring(err)
					),
					true
				)
			end
		end
	end)
end

function Macro:Resume()
	assert(self.FailedAction, "No failed action to resume")
	assert(self.PlaySession == game.JobId, "Resume is only available in the same match")
	return self:Play(self.FailedAction)
end

function Macro:ReturnToLobby()
	assert(game.PlaceId ~= 8304191830, "Macros are disabled in the lobby")
	assert(self.State ~= "destroyed" and self.State ~= "returning", "Already returning to the lobby")
	if self.State == "recording" or self.State == "stopping" then
		self:Stop()
	end

	generation = generation + 1
	local token = generation
	self.State = "returning"
	setMessage("Returning to lobby at wave " .. getWave())

	local ok, err = pcall(function()
		local url = "https://games.roblox.com/v1/games?universeIds=" .. tostring(game.GameId)
		local data = game:GetService("HttpService"):JSONDecode(game:HttpGet(url))
		local lobbyPlace = data.data and data.data[1] and tonumber(data.data[1].rootPlaceId)
		assert(lobbyPlace and lobbyPlace > 0 and lobbyPlace ~= game.PlaceId, "Unable to find the lobby place")
		if generation ~= token or self.State == "destroyed" then
			return
		end

		local TeleportService = game:GetService("TeleportService")
		if lobbyConnection then
			lobbyConnection:Disconnect()
		end
		lobbyConnection = TeleportService.TeleportInitFailed:Connect(function(who, _, reason, placeId)
			if
				who == game:GetService("Players").LocalPlayer
				and placeId == lobbyPlace
				and generation == token
				and self.State ~= "destroyed"
			then
				lobbyConnection:Disconnect()
				lobbyConnection = nil
				self.State = "idle"
				setMessage("Return to lobby failed: " .. tostring(reason), true)
			end
		end)
		maid.Events.TeleportFailure = lobbyConnection
		TeleportService:Teleport(lobbyPlace, game:GetService("Players").LocalPlayer)
	end)

	if not ok and generation == token and self.State ~= "destroyed" then
		if lobbyConnection then
			lobbyConnection:Disconnect()
			lobbyConnection = nil
		end
		self.State = "idle"
		setMessage("Return to lobby failed: " .. tostring(err), true)
	end
	return ok
end

function Macro:Destroy()
	if self.State == "destroyed" then
		return
	end
	if self.Data and not self.Saved then
		pcall(self.Backup, self)
	end
	generation = generation + 1
	self.State = "destroyed"
	if lobbyConnection then
		lobbyConnection:Disconnect()
		lobbyConnection = nil
	end
	if bridge.macro == self then
		bridge.macro = nil
		bridge.capture = nil
	end
	local ui = Library
	Library = nil
	if ui then
		ui:Unload()
	end
	if _G.TowerMacro == self then
		_G.TowerMacro = nil
	end
end

--// Gameplay -----------------------------------------------------------------

do
	local GameplayTab = Window:AddTab("Gameplay")
	local cardBox = GameplayTab:AddLeftGroupbox("Auto Pick Card")
	local priorityBox = GameplayTab:AddRightGroupbox("Pick Order")
	local cardStatus = cardBox:AddLabel("Waiting for cards", true)
	local lastCardStatus = "Waiting for cards"
	local function setCardStatus(text)
		if text ~= lastCardStatus then
			cardStatus:SetText(text)
			lastCardStatus = text
		end
	end
	local picker = { Options = {}, Serial = 0, Picked = 0, Attempts = 0, RetryAt = 0, Expires = 0 }
	local priorityControls = {}
	local cardNames = {
		"None",
		"Double Attack",
		"Double Range",
		"Double Attack, Half Range",
		"Double Attack, Double Range",
		"New Path",
	}
	local knownCards = {}
	for _, name in ipairs(cardNames) do
		knownCards[name] = true
	end
	for _, name in ipairs({
		"Attack",
		"Range",
		"Cooldown",
		"Active Cooldown",
		"Boss Damage",
		"Yen",
		"Random Blessings",
		"Random Curses",
		"Enemy Speed",
		"Enemy Health",
		"Enemy Regen",
		"Enemy Shield",
		"Explosive Deaths",
	}) do
		for _, tier in ipairs({ "I", "II", "III" }) do
			local title = name .. " " .. tier
			table.insert(cardNames, title)
			knownCards[title] = true
		end
	end

	local function normalizeCard(title)
		return tostring(title):gsub("^[%+%-]%s*", ""):gsub("^%s+", ""):gsub("%s+$", "")
	end

	-- Follow the saved order, then choose the first card allowed by Type.
	local function chooseCard(options)
		local ranked = {}
		for rank, title in ipairs(_G.Config.cardPriority) do
			if type(title) == "string" and title ~= "None" and not ranked[normalizeCard(title)] then
				ranked[normalizeCard(title)] = rank
			end
		end
		local ids = {}
		for id, option in pairs(options) do
			if type(option) == "table" and type(option.title) == "string" then
				table.insert(ids, id)
			end
		end
		table.sort(ids, function(a, b)
			local na, nb = tonumber(a), tonumber(b)
			if na and nb and na ~= nb then
				return na < nb
			end
			return tostring(a) < tostring(b)
		end)
		local best, bestRank, fallback
		for _, id in ipairs(ids) do
			local option = options[id]
			local eligible = _G.Config.cardType == "Any"
				or (_G.Config.cardType == "Buff" and option.option_type == "Good")
				or (_G.Config.cardType == "Debuff" and option.option_type == "Bad")
			if eligible then
				fallback = fallback or id
				local rank = ranked[normalizeCard(option.title)]
				if rank and (not bestRank or rank < bestRank) then
					best, bestRank = id, rank
				end
			end
		end
		return best or fallback
	end

	local function choosePlayerCard(options, rogue)
		local leading, highest = {}, 0
		for id, option in pairs(options) do
			local votes = tonumber(getValue(rogue, tostring(id))) or 0
			if votes > highest then
				highest = votes
				leading = { [id] = option }
			elseif votes > 0 and votes == highest then
				leading[id] = option
			end
		end
		return chooseCard(leading), highest
	end

	if not table.find({ "Any", "Buff", "Debuff" }, _G.Config.cardType) then
		_G.Config.cardType = "Any"
	end
	for i = 1, 5 do
		local title = _G.Config.cardPriority[i]
		if type(title) ~= "string" or title == "" then
			title = "None"
		end
		_G.Config.cardPriority[i] = title
		if not knownCards[title] then
			knownCards[title] = true
			table.insert(cardNames, title)
		end
	end
	table.sort(cardNames)
	cardBox:AddToggle("Gameplay_AutoPickCard", {
		Text = "Enable",
		Default = _G.Config.autoPickCard,
		Callback = function(enabled)
			_G.Config.autoPickCard = enabled
			saveSettings()
		end,
	})
	cardBox:AddToggle("Gameplay_FollowPlayerCard", {
		Text = "Follow Players",
		Tooltip = "Wait for a team vote, then follow the leading card. Ties use your pick order.",
		Default = _G.Config.followPlayerCard,
		Callback = function(enabled)
			_G.Config.followPlayerCard = enabled
			saveSettings()
		end,
	})
	cardBox:AddDropdown("Gameplay_CardType", {
		Text = "Type",
		Values = { "Any", "Buff", "Debuff" },
		Default = _G.Config.cardType,
		Callback = function(value)
			_G.Config.cardType = value
			saveSettings()
		end,
	})
	priorityBox:AddLabel("Priority first; otherwise first available.", true)
	for index = 1, 5 do
		local slot = index
		priorityControls[slot] = priorityBox:AddDropdown("Gameplay_CardPriority" .. slot, {
			Text = "Priority " .. slot,
			Values = cardNames,
			Default = _G.Config.cardPriority[slot],
			Callback = function(value)
				_G.Config.cardPriority[slot] = value
				saveSettings()
			end,
		})
	end

	local function receiveCards(duration, options)
		if type(options) ~= "table" then
			return
		end
		picker.Serial = picker.Serial + 1
		picker.Options = {}
		picker.Attempts, picker.RetryAt = 0, 0
		picker.Expires = os.clock() + math.max(1, tonumber(duration) or 30)
		local added = false
		for id, option in pairs(options) do
			if type(option) == "table" and type(option.title) == "string" then
				picker.Options[id] = { title = option.title, option_type = option.option_type }
				local title = normalizeCard(option.title)
				if not knownCards[title] then
					knownCards[title] = true
					table.insert(cardNames, title)
					added = true
				end
			end
		end
		if added then
			table.sort(cardNames)
			for _, control in ipairs(priorityControls) do
				control:SetValues(cardNames)
			end
		end
		setCardStatus("Cards ready")
	end

	local serverEvents = endpoints:FindFirstChild("server_to_client")
	local showOptions = serverEvents and serverEvents:FindFirstChild("show_roguelike_options")
	local showResult = serverEvents and serverEvents:FindFirstChild("show_roguelike_vote_result")
	if showOptions then
		Network:Retrieve(showOptions, receiveCards)
	else
		setCardStatus("Card event unavailable")
	end
	if showResult then
		Network:Retrieve(showResult, function(option)
			picker.Options = {}
			picker.Picked = picker.Serial
			if type(option) == "table" and type(option.title) == "string" then
				setCardStatus("Picked: " .. normalizeCard(option.title))
			end
		end)
	end

	Scheduler:Add({
		Name = "Auto Pick Card",
		Priority = 50,
		Cooldown = 0.25,
		When = function()
			return game.PlaceId ~= 8304191830
				and (_G.Config.autoPickCard or _G.Config.followPlayerCard)
				and Macro.State ~= "destroyed"
				and next(picker.Options) ~= nil
				and picker.Picked ~= picker.Serial
				and picker.Attempts < 3
				and os.clock() >= picker.RetryAt
				and os.clock() < picker.Expires
		end,
		Run = function()
			local data = workspace:FindFirstChild("_DATA")
			local rogue = data and data:FindFirstChild("Roguelike")
			if getValue(rogue, "WaitingForRoguelikeChoice") ~= true then
				return
			end
			local id
			if _G.Config.followPlayerCard then
				local votes
				id, votes = choosePlayerCard(picker.Options, rogue)
				if votes == 0 then
					setCardStatus("Waiting for player vote")
					return
				end
			else
				id = chooseCard(picker.Options)
			end
			if not id then
				setCardStatus("No card matches type")
				return
			end
			local remote = remotes:FindFirstChild("select_roguelike_option")
			if not remote or not isFunctionRemote(remote) then
				setCardStatus("Card remote unavailable")
				return
			end
			local serial = picker.Serial
			local title = normalizeCard(picker.Options[id].title)
			picker.Attempts = picker.Attempts + 1
			local done, result = false, nil
			maid.OneShots:Spawn(function()
				result = table.pack(pcall(Network.Send, Network, remote, id))
				done = true
			end)
			local deadline = math.min(os.clock() + 8, picker.Expires)
			repeat
				task.wait(0.05)
			until done or os.clock() >= deadline or Macro.State == "destroyed" or picker.Serial ~= serial
			if picker.Serial ~= serial or Macro.State == "destroyed" then
				return
			end
			if not done then
				picker.Picked = serial
				setCardStatus("Pick timed out")
			elseif result[1] and result[2] ~= false then
				picker.Picked = serial
				setCardStatus("Voted: " .. title)
			else
				picker.RetryAt = os.clock() + 1
				setCardStatus(picker.Attempts >= 3 and "Pick failed" or "Retrying pick")
			end
		end,
	})
end

--// Macro controls -----------------------------------------------------------

local MacroTab = Window:AddTab("Macro")
local controlsBox = MacroTab:AddLeftGroupbox("Macro Controls")
local playbackBox = MacroTab:AddLeftGroupbox("Playback")
local statusBox = MacroTab:AddRightGroupbox("Status")
local recentBox = MacroTab:AddRightGroupbox("Recent Actions")
local returnBox = MacroTab:AddRightGroupbox("Return to Lobby")

local savedMacros = Macro:List()
local firstMacro = savedMacros[1] or "default"
if _G.Config.profile ~= "" and pcall(profilePath, _G.Config.profile) then
	firstMacro = _G.Config.profile
end
Macro.SelectedProfile = firstMacro

local function safe(callback)
	return function(...)
		local ok, err = pcall(callback, ...)
		if not ok then
			setMessage(tostring(err), true)
			if Library then
				Library:Notify(tostring(err), 4)
			end
		end
	end
end

nameBox = controlsBox:AddInput("TowerMacro_Name", {
	Text = "Macro Name",
	Default = firstMacro,
	Finished = true,
	Callback = function(selected)
		if selected ~= Macro.SelectedProfile then
			Macro.SelectedProfile = selected
			Macro.StartTicket = Macro.StartTicket + 1
		end
		if pcall(profilePath, selected) then
			_G.Config.profile = selected
		end
		saveSettings()
	end,
})
profileList = controlsBox:AddDropdown("TowerMacro_Profiles", {
	Text = "Saved Macros",
	Values = savedMacros,
	AllowNull = true,
	Callback = safe(function(selected)
		assert(Macro.State == "idle", "Stop first")
		if selected then
			nameBox:SetValue(selected)
		end
	end),
})
controlsBox:AddButton({ Text = "New Recording", Func = safe(function()
	Macro:Record()
end) })
controlsBox:AddButton({ Text = "Stop / Save Recording", Func = safe(function()
	Macro:Stop()
end) })
controlsBox:AddButton({ Text = "Save Macro", Func = safe(function()
	Macro:Save()
end) })
controlsBox:AddButton({ Text = "Load Macro", Func = safe(function()
	Macro:Load()
end) })
controlsBox:AddButton({ Text = "Delete Macro", Func = safe(function()
	Macro:Delete()
end) })
controlsBox:AddButton({ Text = "Recover Last Recording", Func = safe(function()
	Macro:Load(nil, true)
end) })
controlsBox:AddButton({ Text = "Refresh Saved Macros", Func = safe(function()
	Macro:RefreshProfiles()
end) })
controlsBox:AddLabel("Folder: project a macro · Use a different name to save another macro.", true)
controlsBox:AddLabel("Record before placing the first unit to replay the full match.", true)

local timingDefault = 1
if _G.Config.mode == "time" then
	timingDefault = 2
end
playbackBox:AddDropdown("TowerMacro_Timing", {
	Text = "Timing",
	Values = { "Wave", "Time" },
	Default = timingDefault,
	Callback = safe(function(selected)
		assert(Macro.State == "idle", "Stop first")
		if selected == "Time" then
			_G.Config.mode = "time"
		else
			_G.Config.mode = "wave"
		end
		saveSettings()
	end),
})
playbackBox:AddSlider("TowerMacro_Timeout", {
	Text = "Cash Wait Timeout (seconds)",
	Default = _G.Config.timeout,
	Min = 10,
	Max = 180,
	Rounding = 0,
	Callback = function(n)
		_G.Config.timeout = n
		saveSettings()
	end,
})
playToggle = playbackBox:AddToggle("TowerMacro_Play", {
	Text = "Play Macro",
	Default = _G.Config.playMacro,
	Callback = safe(function(enabled)
		if syncingControls then
			return
		end
		local state = Macro.State
		assert(
			state == "idle" or state == "playing" or state == "preparing" or state == "returning",
			"Stop recording first"
		)
		_G.Config.playMacro = enabled
		Macro.StartTicket = Macro.StartTicket + 1
		if not enabled and (state == "playing" or state == "preparing") then
			Macro:Stop()
		end
		saveSettings()
	end),
})
playbackBox:AddToggle("TowerMacro_AutoReplay", {
	Text = "Auto Replay",
	Default = _G.Config.autoReplay,
	Callback = function(enabled)
		_G.Config.autoReplay = enabled
		saveSettings()
	end,
})
playbackBox:AddToggle("TowerMacro_AutoSkipWave", {
	Text = "Auto Skip Wave",
	Default = _G.Config.autoSkipWave,
	Callback = function(enabled)
		_G.Config.autoSkipWave = enabled
		saveSettings()
	end,
})
playbackBox:AddToggle("TowerMacro_AutoStartGame", {
	Text = "Auto Start Game",
	Default = _G.Config.autoStartGame,
	Callback = function(enabled)
		_G.Config.autoStartGame = enabled
		saveSettings()
	end,
})

returnBox:AddToggle("TowerMacro_AutoReturnLobby", {
	Text = "Return to Lobby at Wave",
	Default = _G.Config.autoReturnLobby,
	Callback = function(enabled)
		_G.Config.autoReturnLobby = enabled
		Macro.ReturnTicket = Macro.ReturnTicket + 1
		saveSettings()
	end,
})
returnBox:AddInput("TowerMacro_ReturnWave", {
	Text = "Return at Wave",
	Default = tostring(_G.Config.returnWave),
	Numeric = true,
	Finished = true,
	Callback = safe(function(text)
		local n = tonumber(text)
		assert(n and n == math.floor(n) and n >= 1 and n <= 1000000, "Enter a whole wave number from 1 to 1000000")
		_G.Config.returnWave = n
		Macro.ReturnTicket = Macro.ReturnTicket + 1
		saveSettings()
	end),
})
returnBox:AddLabel("Leave when the wave reaches this number. This takes priority over Auto Replay.", true)

playbackBox:AddLabel("Auto Replay votes Replay after the match. Keep Play Macro on to run the next match.", true)
playbackBox:AddButton({ Text = "Stop Playback", Func = safe(function()
	Macro:Stop()
end) })
playbackBox:AddButton({ Text = "Resume Failed Action", Func = safe(function()
	Macro:Resume()
end) })
playbackBox:AddButton({
	Text = "Save Settings",
	Func = safe(function()
		SaveConfig()
		setMessage("Settings saved")
	end),
})

detailsLabel = statusBox:AddLabel("Reading map data", true)
statusLabel = statusBox:AddLabel("Ready", true)
logLabel = recentBox:AddLabel("No actions yet", true)

Library:OnUnload(function()
	Library = nil
	if _G.TowerLobby then
		_G.TowerLobby.OnUnload()
	end
	Macro:Destroy()
	local currentThread = coroutine.running()
	for _, thread in ipairs(_G.Thread or {}) do
		if thread ~= currentThread then
			pcall(task.cancel, thread)
		end
	end
	_G.Thread = {}
	maid:Destroy()
	if _G.ProjectAMaid == maid then
		_G.ProjectAMaid = nil
	end
end)

local SettingsTab = Window:AddTab("Settings")
ThemeManager:SetLibrary(Library)
ThemeManager:SetFolder(mainFolder .. "/ui")
Library.LayoutFile = mainFolder .. "/ui/layout.json"
ThemeManager:BuildMenuSection(SettingsTab)
ThemeManager:ApplyToTab(SettingsTab)
local settingsBox = SettingsTab:AddRightGroupbox("Anime Adventures")
settingsBox:AddLabel("Menu key: End (change it in Menu).", true)
settingsBox:AddToggle("Settings_AutoSave", {
	Text = "Auto Save",
	Tooltip = "Save gameplay changes automatically.",
	Default = _G.Config.autoSave,
	Callback = safe(function(enabled)
		if _G.Config.autoSave == enabled then
			return
		end
		_G.Config.autoSave = enabled
		-- Persist only this preference when switching off; keep unsaved gameplay changes in memory.
		writefile(preferencesFile, game:GetService("HttpService"):JSONEncode({ autoSave = enabled }))
		if enabled then
			SaveConfig()
		end
	end),
})
settingsBox:AddButton({
	Text = "Save Settings",
	Func = safe(function()
		SaveConfig()
		Library:SaveLayout()
		Library:Notify("Settings and layout saved", 3)
	end),
})
Library:SetWatermark("Project A | Anime Adventures")
Library:SetWatermarkVisibility(true)
Library:LoadLayout()
if game.PlaceId ~= 8304191830 then
	MacroTab:ShowTab()
end
Library:Toggle(true)

if isfile(profilePath(getMacroName())) then
	local ok, err = pcall(Macro.Load, Macro)
	if ok then
		Macro:RefreshProfiles(getMacroName())
	else
		setMessage(tostring(err), true)
	end
end
settingsReady = true
saveSettings()

--// Match automation ---------------------------------------------------------

local voteStates = {}

local function getVotePrompt(name)
	local playerGui = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
	local prompt = playerGui and playerGui:FindFirstChild(name)
	if not prompt or not prompt:IsA("ScreenGui") or not prompt.Enabled then
		return
	end
	local holder = prompt:FindFirstChild("Holder")
	if not holder or not holder.Visible then
		return
	end
	return prompt
end

local function sendVote(remoteName)
	assert(game.PlaceId ~= 8304191830, "Macros are disabled in the lobby")
	local remote = remotes:FindFirstChild(remoteName)
	assert(remote and remote:IsA("RemoteFunction"), "Vote remote not found: " .. remoteName)
	return Network:Send(remote)
end

local function autoVote(configKey, promptName, remoteName, voteKey)
	if not _G.Config[configKey] then
		return
	end
	local prompt = getVotePrompt(promptName)
	if not prompt then
		voteStates[remoteName] = nil
		return
	end

	local state = voteStates[remoteName]
	if not state or state.key ~= voteKey then
		state = { key = voteKey, attempts = 0, retryAt = 0 }
		voteStates[remoteName] = state
	end
	if state.sent or state.pending or state.attempts >= 3 or os.clock() < state.retryAt then
		return
	end

	state.pending = true
	state.attempts = state.attempts + 1
	maid.OneShots:Spawn(function()
		local ok, result = pcall(sendVote, remoteName)
		if Macro.State == "destroyed" or voteStates[remoteName] ~= state then
			return
		end
		state.pending = false
		if ok and result ~= false then
			state.sent = true
			if promptName == "VoteSkip" and prompt.Parent then
				prompt.Enabled = false
			end
		else
			state.retryAt = os.clock() + 2
			if state.attempts >= 3 then
				setMessage("Auto vote failed: " .. remoteName, true)
			end
		end
	end)
	maid.OneShots:Delay(8, function()
		if Macro.State ~= "destroyed" and voteStates[remoteName] == state and state.pending then
			state.pending = false
			state.sent = true
			setMessage("Auto vote timed out: " .. remoteName, true)
		end
	end)
end

local function sendReplayVote()
	assert(game.PlaceId ~= 8304191830, "Macros are disabled in the lobby")
	local remote = remotes:FindFirstChild("set_game_finished_vote")
	if not remote then
		return "unavailable"
	end

	local done = false
	local accepted = false
	maid.OneShots:Spawn(function()
		local ok, result = pcall(function()
			return Network:Send(remote, "replay")
		end)
		accepted = ok and result ~= false
		done = true
	end)

	local deadline = os.clock() + 8
	repeat
		task.wait(0.1)
	until done or os.clock() >= deadline or Macro.State == "destroyed"
	if not done then
		return "timeout"
	end
	if accepted then
		return "accepted"
	end
	return "rejected"
end

Macro.Round = 1
Macro.WasFinished = isGameFinished()
Macro.LastWave = getWave()
Macro.MapReady = false
Macro.ShouldReturn = false
Macro.ReplaySent = false
Macro.ReplayTries = 0
Macro.NextReplay = 0

do
	Scheduler:Add({
		Name = "Round State",
		Priority = 100,
		Cooldown = 0.2,
		When = function()
			return Macro.State ~= "destroyed" and game.PlaceId ~= 8304191830
		end,
		Run = function()
			if Macro.State == "destroyed" or game.PlaceId == 8304191830 then
				return
			end
			pcall(function()
				Macro.Finished = isGameFinished()
				Macro.Wave = getWave()
				if (Macro.WasFinished and not Macro.Finished) or Macro.Wave < Macro.LastWave then
					Macro.Round = Macro.Round + 1
					Macro.PlayTicket = nil
					Macro.ReplaySent = false
					Macro.ReplayTries = 0
					Macro.NextReplay = 0
					Macro.LobbyTicket = nil
					Macro.PlaySession = nil
					Macro.FailedAction = nil
					Macro.Completed = false
					level = nil
					voteStates = {}
				end
				Macro.WasFinished = Macro.Finished
				Macro.LastWave = Macro.Wave
				Macro.MapReady = getValue(workspace:FindFirstChild("_MAP_CONFIG"), "IsLobby") == false
					and getValue(workspace:FindFirstChild("_MAP_CONFIG"), "MapLoaded") == true
					and getValue(workspace, "SERVER_READY") ~= false
				Macro.ShouldReturn = Macro.MapReady and _G.Config.autoReturnLobby and Macro.Wave >= _G.Config.returnWave
				if Macro.ShouldReturn then
					local ticket = Macro.Round .. ":" .. Macro.ReturnTicket .. ":" .. _G.Config.returnWave
					if Macro.LobbyTicket ~= ticket and Macro.State ~= "returning" then
						Macro.LobbyTicket = ticket
						maid.OneShots:Spawn(function()
							local ok, err = pcall(Macro.ReturnToLobby, Macro)
							if not ok then
								setMessage("Return to lobby failed: " .. tostring(err), true)
							end
						end)
					end
				end
			end)
		end,
	})
end

do
	Scheduler:Add({
		Name = "Skip Wave",
		Priority = 0,
		Cooldown = 0.5,
		When = function()
			return Macro.State ~= "destroyed" and game.PlaceId ~= 8304191830
		end,
		Run = function()
			if Macro.State == "destroyed" or game.PlaceId == 8304191830 then
				return
			end
			pcall(function()
				if
					_G.Config.autoSkipWave
					and Macro.MapReady
					and not Macro.Finished
					and not Macro.ShouldReturn
					and Macro.State ~= "returning"
				then
					if getValue(workspace:FindFirstChild("_DATA"), "GameStarted") == true then
						autoVote("autoSkipWave", "VoteSkip", "vote_wave_skip", Macro.Round .. ":" .. getWave())
					end
				end
			end)
		end,
	})
end

do
	Scheduler:Add({
		Name = "Start Match",
		Priority = 0,
		Cooldown = 0.5,
		When = function()
			return Macro.State ~= "destroyed" and game.PlaceId ~= 8304191830
		end,
		Run = function()
			if Macro.State == "destroyed" or game.PlaceId == 8304191830 then
				return
			end
			pcall(function()
				if
					_G.Config.autoStartGame
					and Macro.MapReady
					and not Macro.Finished
					and not Macro.ShouldReturn
					and Macro.State ~= "returning"
				then
					if
						getValue(workspace:FindFirstChild("_DATA"), "GameStarted") ~= true
						and workspace._DATA.VoteStart.VotingFinished.Value ~= true
					then
						autoVote("autoStartGame", "VoteStart", "vote_start", tostring(Macro.Round))
					end
				end
			end)
		end,
	})
end

do
	Scheduler:Add({
		Name = "Replay Match",
		Priority = 0,
		Cooldown = 0.5,
		When = function()
			return Macro.State ~= "destroyed" and game.PlaceId ~= 8304191830
		end,
		Run = function()
			if Macro.State == "destroyed" or game.PlaceId == 8304191830 then
				return
			end
			pcall(function()
				if
					_G.Config.autoReplay
					and Macro.State == "idle"
					and Macro.MapReady
					and Macro.Finished
					and not Macro.ShouldReturn
					and not Macro.ReplaySent
					and Macro.ReplayTries < 3
					and os.clock() >= Macro.NextReplay
				then
					local round = Macro.Round
					Macro.ReplaySent = true
					Macro.ReplayTries = Macro.ReplayTries + 1
					local result = sendReplayVote()
					if Macro.State == "destroyed" or Macro.Round ~= round then
						return
					end
					if result == "accepted" then
						setMessage("Replay requested ? waiting for the next match")
					elseif result == "rejected" then
						Macro.ReplaySent = false
						Macro.NextReplay = os.clock() + 5
						if Macro.ReplayTries < 3 then
							setMessage("Replay vote failed ? retrying", true)
						else
							setMessage("Replay vote failed after 3 attempts", true)
						end
					elseif result == "timeout" then
						setMessage("Replay vote timed out", true)
					else
						setMessage("Replay is not available in this match", true)
					end
				end
			end)
		end,
	})
end

do
	Scheduler:Add({
		Name = "Macro Playback",
		Priority = 0,
		Cooldown = 0.5,
		When = function()
			return Macro.State ~= "destroyed" and game.PlaceId ~= 8304191830
		end,
		Run = function()
			if Macro.State == "destroyed" or game.PlaceId == 8304191830 then
				return
			end
			pcall(function()
				if
					_G.Config.playMacro
					and Macro.State == "idle"
					and Macro.MapReady
					and not Macro.Finished
					and not Macro.ShouldReturn
				then
					if Macro.PlaySession == game.JobId and (Macro.FailedAction or Macro.Completed) then
						return
					end
					local ticket = Macro.Round .. ":" .. Macro.StartTicket
					if Macro.PlayTicket ~= ticket then
						Macro.PlayTicket = ticket
						local ok, err = pcall(Macro.Play, Macro)
						if not ok then
							setMessage(tostring(err), true)
						end
					end
				end
			end)
		end,
	})
end

-- Update status labels only when their text changes.
do
	if game.PlaceId ~= 8304191830 then
		local ok, err = pcall(getMapInfo)
		if not ok then
			setMessage(tostring(err), true)
		end
	end
	local lastDetails, lastStatus, lastLog
	Scheduler:Add({
		Name = "Macro UI",
		Priority = 0,
		Cooldown = 0.25,
		When = function()
			return Macro.State ~= "destroyed"
		end,
		Run = function()
			if playToggle.Value ~= _G.Config.playMacro then
				syncingControls = true
				playToggle:SetValue(_G.Config.playMacro)
				syncingControls = false
			end

			local actionCount = Macro.Data and #Macro.Data.actions or 0
			local mapTitle = game.PlaceId == 8304191830 and "Lobby - Macros disabled"
				or level and level.title
				or "Map data unavailable"
			local detailsText = string.format(
				"%s\nWave %d · Cash %d · %d actions · %s",
				mapTitle,
				getWave(),
				getCash(),
				actionCount,
				Macro.State
			)
			local statusText = (Macro.MessageError and "Error: " or "") .. (Macro.Message or "Ready")
			local logText = #history > 0 and table.concat(history, "\n") or "No actions yet"

			if detailsText ~= lastDetails then
				detailsLabel:SetText(detailsText)
				lastDetails = detailsText
			end
			if statusText ~= lastStatus then
				statusLabel:SetText(statusText)
				lastStatus = statusText
			end
			if logText ~= lastLog then
				logLabel:SetText(logText)
				lastLog = logText
			end
		end,
	})
end

setMessage(
	game.PlaceId == 8304191830 and "Macros are disabled in the lobby" or "Ready - Record before placing the first unit"
)
--// Start scheduler ----------------------------------------------------------

maid.mainthread:Spawn(function()
	while not Scheduler.Stopped do
		Scheduler:Tick()
		task.wait(Scheduler.Interval)
	end
end)
print("TOWER_MACRO_READY")
return Macro
