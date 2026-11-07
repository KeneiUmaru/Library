-- Ethos-style UI library (restyled from the Delta Hub GUI2LUA dump). Responsive: desktop, compact, mobile drawer.
-- Usage: local Library = loadstring(...)(); local Window = Library:CreateWindow({Title = "ETHOS SUITE", Badge = "GHOUL://RE"})
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

-- Colors sampled from the Ethos reference screenshot.
local Theme = {
	Background = Color3.fromRGB(11, 11, 15), -- window body, sidebar, inputs, footer
	Panel = Color3.fromRGB(18, 18, 24), -- header, sections, badges
	Border = Color3.fromRGB(35, 36, 44),
	Hover = Color3.fromRGB(62, 64, 76),
	Scrollbar = Color3.fromRGB(90, 90, 97),
	Accent = Color3.fromRGB(216, 159, 79),
	AccentRing = Color3.fromRGB(187, 138, 71),
	OnAccent = Color3.fromRGB(19, 14, 7),
	Text = Color3.fromRGB(230, 230, 230),
	SubText = Color3.fromRGB(170, 170, 180),
	Muted = Color3.fromRGB(120, 120, 135),
	Warn = Color3.fromRGB(230, 180, 80),
	Good = Color3.fromRGB(100, 210, 130),
}
local FONT = "rbxasset://fonts/families/GothamSSm.json"
local W = Enum.FontWeight
local AUTO_Y, AUTO_X, AUTO_NONE = Enum.AutomaticSize.Y, Enum.AutomaticSize.X, Enum.AutomaticSize.None
local BY_ORDER = Enum.SortOrder.LayoutOrder
local HORIZONTAL = Enum.FillDirection.Horizontal
local CENTER_Y = Enum.VerticalAlignment.Center
local POINTER = { [Enum.UserInputType.MouseButton1] = true, [Enum.UserInputType.Touch] = true }
local FAST = TweenInfo.new(0.12)
local FOLD = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local NAV = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) -- sidebar/content reflow
local HEADER_H, FOOTER_H, TOOLBAR_H = 44, 25, 32
local LAYOUTS = { Auto = true, Single = true, Double = true }
local WINDOW_LAYOUTS = { Auto = true, Sidebar = true, Topbar = true }
local COMPACT_MODES = { Auto = true, Full = true, Compact = true, Mobile = true }
-- Section transition durations (seconds, before speed scaling).
local MOVE = { structure = 0.28, columns = 0.32, width = 0.24, insert = 0.20 }
-- Presentation styles: every geometry value components use comes from one of these token sets. Colors stay in
-- Theme; the header (44px, folds to 44px) and status bar are shared by both styles.
--   Modern: the spacious section-card layout of the Ethos reference.
--   Classic: the original compact layout (Delta Hub dump geometry: 155px sidebar, 25px tabs, 8px gaps, 20px fields).
local STYLE_TOKENS = {
	Modern = {
		SidebarWidth = 200, SidebarPad = { 15, 19, 10, 10 }, CategoryGap = 10, CategoryHeaderHeight = 28, CategoryTextSize = 16,
		TabHeight = 28, DrawerTabHeight = 36, TabTextSize = 14, Underline = true,
		PagePad = { 8, 7, 9, 9 }, PagePadMobile = { 6, 5, 6, 6 },
		SectionGap = 10, SectionMin = 300, LoneMax = 720,
		SectionPad = { 15, 14, 14, 14 }, SectionPadMobile = { 12, 12, 12, 12 },
		SectionHeaderHeight = 20, SectionTitleSize = 18, SectionHeaderGap = 10, SectionCorner = 3, BorderThickness = 1, BorderTransparency = 0,
		RowGap = 10, TitleSize = 14, TitleHeight = 16, DescriptionSize = 14, DescriptionLineHeight = 1.07, DescriptionSpacing = 5,
		RowMinHeight = 0, ControlMinWidth = 82, ControlRowHeight = 28,
		CheckSize = 20, CheckHolder = 28, CheckRing = true, CheckCorner = 2,
		ControlHeight = 32, ButtonTextSize = 14, ControlCorner = 3,
		FieldHeight = 32, FieldWidthScale = 0.45, FieldMaxWidth = 202, FieldTextSize = 14, FieldInset = 10, StackBelow = 300, StackGap = 6,
		KeyHeight = 28, KeyMinWidth = 28, KeyTextSize = 13, ValueHeight = 26, ValueMinWidth = 36,
		SliderTrack = 6, SliderGap = 10, OptionsPad = { 12, 12, 10, 10 }, OptionsGap = 10, LabelSize = 14,
	},
	Classic = {
		SidebarWidth = 155, SidebarPad = { 10, 10, 3, 6 }, CategoryGap = 4, CategoryHeaderHeight = 28, CategoryTextSize = 14,
		TabHeight = 25, DrawerTabHeight = 34, TabTextSize = 13, Underline = false,
		PagePad = { 15, 15, 10, 10 }, PagePadMobile = { 8, 8, 6, 6 },
		SectionGap = 8, SectionMin = 260, LoneMax = 760,
		SectionPad = { 8, 8, 0, 8 }, SectionPadMobile = { 8, 8, 0, 8 },
		SectionHeaderHeight = 24, SectionTitleSize = 14, SectionHeaderGap = 4, SectionCorner = 0, BorderThickness = 1, BorderTransparency = 0.25,
		RowGap = 8, TitleSize = 13, TitleHeight = 15, DescriptionSize = 12, DescriptionLineHeight = 1.15, DescriptionSpacing = 0,
		RowMinHeight = 30, ControlMinWidth = 36, ControlRowHeight = 20,
		CheckSize = 20, CheckHolder = 20, CheckRing = false, CheckCorner = 1,
		ControlHeight = 28, ButtonTextSize = 12, ControlCorner = 0,
		FieldHeight = 22, FieldWidthScale = 0.4, FieldMaxWidth = 120, FieldTextSize = 13, FieldInset = 5, StackBelow = 240, StackGap = 4,
		KeyHeight = 20, KeyMinWidth = 20, KeyTextSize = 13, ValueHeight = 20, ValueMinWidth = 24,
		SliderTrack = 4, SliderGap = 6, OptionsPad = { 8, 8, 6, 6 }, OptionsGap = 6, LabelSize = 12,
	},
}
local STYLE_TWEEN = TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) -- style switch
local SCHEMA = 2 -- SaveManager data version; v1 was the flat {X, Y, Folded, Locked, Page} table
local ICON = {
	close = "rbxassetid://6031094678",
	minimize = "rbxassetid://10734896206",
	check = "rbxassetid://6031094667",
	chevron = "rbxassetid://6031091008", -- points right; rotated 90 = down
	updown = "rbxassetid://10709797508",
	gear = "rbxassetid://3926307971", -- sprite sheet, see GEAR_RECT
}
local GEAR_RECT = { Vector2.new(324, 124), Vector2.new(36, 36) }

---------------------------------------------------------------- Maid
-- Deterministic cleanup. Give() accepts connections, Instances (Tweens are cancelled first), threads,
-- functions, and anything with Destroy/Clean (nested Maids). Clean() runs newest-first, each task
-- isolated in pcall, and is idempotent; giving to an already-cleaned Maid cleans the task immediately.
local Maid = {}
Maid.__index = Maid
function Maid.new() return setmetatable({ _tasks = {}, _dead = false }, Maid) end
local function cleanTask(t)
	local kind = typeof(t)
	if kind == "RBXScriptConnection" then
		t:Disconnect()
	elseif kind == "Instance" then
		if t:IsA("Tween") then t:Cancel() end
		t:Destroy()
	elseif kind == "thread" then
		if coroutine.status(t) ~= "dead" then task.cancel(t) end
	elseif kind == "function" then
		t()
	elseif kind == "table" then
		if type(t.Destroy) == "function" then t:Destroy() elseif type(t.Clean) == "function" then t:Clean() end
	end
end
function Maid:Give(t)
	if self._dead then
		pcall(cleanTask, t)
	else
		table.insert(self._tasks, t)
	end
	return t
end
function Maid:Clean()
	self._dead = true
	local tasks = self._tasks
	self._tasks = {}
	for i = #tasks, 1, -1 do
		local ok, err = pcall(cleanTask, tasks[i])
		if not ok then warn("[Ethos] cleanup task failed: " .. tostring(err)) end
	end
end
Maid.Destroy = Maid.Clean

---------------------------------------------------------------- AnimationManager
-- Every UI tween goes through Play(): it cancels whatever tween currently drives the same property,
-- scales durations by Speed, and jumps straight to the end under Reduced Motion (Roblox setting, or
-- the ReducedMotion field when set). onDone runs only when the animation actually finishes.
local AnimationManager = {}
AnimationManager.__index = AnimationManager
function AnimationManager.new(settings)
	settings = settings or {}
	return setmetatable({ Speed = settings.Speed or 1, ReducedMotion = settings.ReducedMotion, _running = {} }, AnimationManager)
end
function AnimationManager:IsReduced()
	if self.ReducedMotion ~= nil then return self.ReducedMotion end
	local ok, on = pcall(function() return GuiService.ReducedMotionEnabled end)
	return ok and on == true
end
function AnimationManager:Play(obj, info, props, onDone)
	local running = self._running[obj]
	if running then
		for prop in pairs(props) do
			if running[prop] then running[prop]:Cancel() end
		end
	end
	if self:IsReduced() or self.Speed <= 0 then
		for k, v in pairs(props) do obj[k] = v end
		if onDone then onDone() end
		return nil
	end
	local scaled = TweenInfo.new(info.Time / self.Speed, info.EasingStyle, info.EasingDirection, info.RepeatCount, info.Reverses, info.DelayTime / self.Speed)
	local t = TweenService:Create(obj, scaled, props)
	running = self._running[obj] or {}
	self._running[obj] = running
	for prop in pairs(props) do running[prop] = t end
	t.Completed:Once(function(state)
		for prop in pairs(props) do
			if running[prop] == t then running[prop] = nil end
		end
		if next(running) == nil and self._running[obj] == running then self._running[obj] = nil end
		if state == Enum.PlaybackState.Completed and onDone then onDone() end
	end)
	t:Play()
	return t
end
-- Cancels the tweens driving these properties of obj (props: list of names; nil = all of obj's tweens).
function AnimationManager:Stop(obj, props)
	local running = self._running[obj]
	if not running then return end
	if props then
		for _, prop in ipairs(props) do
			if running[prop] then running[prop]:Cancel() end
		end
	else
		for _, t in pairs(running) do t:Cancel() end
	end
end
function AnimationManager:CancelAll()
	local all = self._running
	self._running = {}
	for _, running in pairs(all) do
		for _, t in pairs(running) do t:Cancel() end
	end
end

---------------------------------------------------------------- helpers
local function new(class, props, children)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		if k ~= "Parent" then o[k] = v end
	end
	for _, c in ipairs(children or {}) do c.Parent = o end
	o.Parent = props.Parent
	return o
end
local function corner(r) return new("UICorner", { CornerRadius = UDim.new(0, r) }) end
local function stroke(color, thickness)
	return new("UIStroke", { Color = color or Theme.Border, Thickness = thickness or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end
local function padding(l, r, t, b)
	return new("UIPadding", { PaddingLeft = UDim.new(0, l or 0), PaddingRight = UDim.new(0, r or 0), PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or 0) })
end
local function hlist(pad, halign, valign)
	return new("UIListLayout", { FillDirection = HORIZONTAL, VerticalAlignment = valign or CENTER_Y, HorizontalAlignment = halign or Enum.HorizontalAlignment.Left, Padding = UDim.new(0, pad or 0), SortOrder = BY_ORDER })
end
local function vlist(pad) return new("UIListLayout", { Padding = UDim.new(0, pad or 0), SortOrder = BY_ORDER }) end
local function label(props)
	props.BackgroundTransparency = 1
	props.FontFace = props.FontFace or Font.new(FONT)
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	props.TextTruncate = props.TextTruncate or Enum.TextTruncate.AtEnd
	return new("TextLabel", props)
end
local function inside(obj, p)
	local a, s = obj.AbsolutePosition, obj.AbsoluteSize
	return obj.Visible and p.X >= a.X and p.Y >= a.Y and p.X <= a.X + s.X and p.Y <= a.Y + s.Y
end
-- Hover only for mouse; on touch MouseEnter fires and never clears.
local function hover(obj, fn)
	obj.MouseEnter:Connect(function()
		if UIS:GetLastInputType() ~= Enum.UserInputType.Touch then fn(true) end
	end)
	obj.MouseLeave:Connect(function() fn(false) end)
end
-- Small boxes (key, value) grow with their text.
local function autoWidth(box, textObj, minW, maxW)
	local function fit()
		local lo = type(minW) == "function" and minW() or minW
		box.Size = UDim2.fromOffset(math.clamp(textObj.TextBounds.X + 16, lo, maxW), box.Size.Y.Offset)
	end
	textObj:GetPropertyChangedSignal("TextBounds"):Connect(fit)
	fit()
	return fit
end
local function scrollIntoView(scroll, obj)
	local top = obj.AbsolutePosition.Y - scroll.AbsolutePosition.Y
	if top < 0 or top + obj.AbsoluteSize.Y > scroll.AbsoluteSize.Y then
		scroll.CanvasPosition = Vector2.new(0, math.max(0, scroll.CanvasPosition.Y + top - 10))
	end
end
-- scrollIntoView, then (phones) once the on-screen keyboard is up, scroll the field clear of it.
local function keepVisible(scroll, obj)
	scrollIntoView(scroll, obj)
	task.delay(0.35, function()
		if not obj.Parent or not UIS.OnScreenKeyboardVisible then return end
		local kbTop = UIS.OnScreenKeyboardPosition.Y - GuiService:GetGuiInset().Y
		local bottom = obj.AbsolutePosition.Y + obj.AbsoluteSize.Y + 8
		if bottom > kbTop then
			scroll.CanvasPosition = Vector2.new(0, scroll.CanvasPosition.Y + (bottom - kbTop))
		end
	end)
end
local function iconImage(props)
	props.BackgroundTransparency = 1
	props.AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5)
	props.Position = props.Position or UDim2.fromScale(0.5, 0.5)
	return new("ImageLabel", props)
end
-- Dark field used by dropdown/input/keybind/value boxes.
local function field(props)
	props.BackgroundColor3, props.BorderSizePixel, props.ClipsDescendants = Theme.Background, 0, true
	return new("Frame", props, { corner(3), stroke() })
end
-- Accepts both AddX(opts) and AddX("Id", opts); Text is an alias of Title.
local function args(a, b)
	local o
	if type(a) == "string" then
		o = b or {}
		o.Id = o.Id or a
	else
		o = a or {}
	end
	o.Title = o.Title or o.Text or o.Id
	return o
end
local function num(v) return type(v) == "number" and v == v and math.abs(v) < 1e6 end

local Library = { Theme = Theme, Maid = Maid, AnimationManager = AnimationManager }

-- Storage adapter over executor file APIs. Returns nil (the window then keeps state for this session only)
-- when the APIs are missing or the path is unsafe: relative, no "..", no drive letters, simple characters.
-- Save writes "<name>.tmp.json", reads it back to verify, copies the last good file to "<name>.bak.json", then writes
-- the real file. Load falls back to .tmp (a save that didn't finish, verified when written, so newer), then .bak.
-- Executors have no atomic rename, so this narrows but does not remove the window for a torn write.
function Library.FileStorage(path)
	if not (readfile and writefile and isfile) then return nil end
	if type(path) ~= "string" or path == "" or #path > 200 or path:find("%.%.") or path:find("^[/\\]") or path:find(":")
		or not path:match("^[%w_%-%./\\ ]+$") or path:match("[/\\]$") then
		warn("[Ethos] FileStorage: unsafe path rejected: " .. tostring(path))
		return nil
	end
	local function read(p)
		if not isfile(p) then return nil end
		local ok, data = pcall(function() return HttpService:JSONDecode(readfile(p)) end)
		return ok and type(data) == "table" and data or nil
	end
	local function ensureFolders()
		if not (makefolder and isfolder) then return end
		local dir = ""
		for part in path:gmatch("([^/\\]+)[/\\]") do
			dir = dir == "" and part or dir .. "/" .. part
			if not isfolder(dir) then makefolder(dir) end
		end
	end
	-- Executors filter file extensions ("cfg.json.tmp" is an illegal path), so siblings keep the real one.
	local stem, ext = path:match("^(.*)(%.[%w]+)$")
	if not stem then stem, ext = path, ".json" end
	local tmp, bak = stem .. ".tmp" .. ext, stem .. ".bak" .. ext
	return {
		Path = path,
		Load = function() return read(path) or read(tmp) or read(bak) end,
		Save = function(data)
			local json = HttpService:JSONEncode(data)
			ensureFolders()
			writefile(tmp, json)
			if readfile(tmp) ~= json then error("FileStorage: temp file did not verify") end
			if read(path) then writefile(bak, readfile(path)) end -- keep the last good copy
			writefile(path, json)
			if delfile then pcall(delfile, tmp) end
		end,
	}
end

function Library:CreateWindow(opts)
	opts = opts or {}
	local maid = Maid.new()
	local anim = AnimationManager.new({ Speed = opts.AnimationSpeed, ReducedMotion = opts.ReducedMotion })
	local keybinds, pages, badges, statuses, components = {}, {}, {}, 0, {}
	local searchRecords, refreshSearch, notify, favorites = {}, nil, nil, { list = {}, set = {} }
	local componentOrder, optionPanels = {}, {} -- registration order: restore and callbacks run in this order
	-- pos: where the window is drawn (clamped to the screen). wantPos: where the user put it (nil = centered);
	-- a smaller screen moves pos, never wantPos, so rotating back restores the user's spot.
	local drag, capturing, popup, current, pos, wantPos, size, manualSize, pendingSave
	-- Restore = "Deferred" (default): saved values show at once, callbacks run after the building script yields.
	-- "Silent": values only, no callbacks. "Immediate": callbacks fire while components are being created (pre-Phase 3).
	local restoreMode = (opts.Restore == "Silent" or opts.Restore == "Immediate") and opts.Restore or "Deferred"
	local restoreQueue, restorePending, restoreScheduled = {}, {}, false
	local rememberOptions = opts.RememberOptions == true -- also save which option panels are open
	local TOUCH_HIT = math.round(44 * math.clamp(opts.TouchHitboxScale or 1, 0.5, 2)) -- resize grip target on touch
	local minimized, drawerOpen, order, lastClick, restoring = false, false, 0, 0, false
	local locked, sizeLocked, layoutMode = opts.Locked == true, opts.SizeLocked == true, LAYOUTS[opts.Layout] and opts.Layout or "Auto"
	-- Presentation. Preferences (saved): compactPref, sidebarPref, transitionsOn, transitionSpeed.
	-- Effective (measured, never saved): presentation "Full" | "Compact" | "Mobile", navDrawer (sidebar shown as a drawer).
	local compactPref = COMPACT_MODES[opts.CompactMode] and opts.CompactMode or "Auto"
	-- Presentation style ("Modern" | "Classic"): independent of layout, navigation mode, size, scale and theme. Saved.
	local stylePref = STYLE_TOKENS[opts.PresentationStyle] and opts.PresentationStyle or "Modern"
	local style -- the active token set, STYLE_TOKENS[stylePref]
	local sidebarPref = opts.SidebarCollapsed == true
	local windowLayoutPref = WINDOW_LAYOUTS[opts.WindowLayout] and opts.WindowLayout or "Auto"
	local transitionsOn = opts.SectionTransitions ~= false
	local tabAnimations = opts.TabAnimations ~= false
	local tabSpeed = num(opts.TabAnimationSpeed) and math.clamp(opts.TabAnimationSpeed, 0.25, 4) or 1
	local gridMax = num(opts.MaxSectionGridWidth) and math.max(240, opts.MaxSectionGridWidth) or 1040
	local equalRows = opts.EqualRowHeight == true
	local fitContent = opts.FitWindowToContent == true
	local transitionSpeed = type(opts.SectionTransitionSpeed) == "number" and math.clamp(opts.SectionTransitionSpeed, 0.25, 4) or 1
	local presentation, navDrawer
	local layoutReady = false -- section transitions start once the building script has yielded
	local headerDirty, statusDirty, selDirty = true, true, true
	local autoSave = opts.AutoSave ~= false
	local SNAP = opts.Snap or 12 -- px from a screen edge that snaps the window to it; 0 turns it off
	-- Size limits. MIN: preferred minimum (the automatic size never goes below it). COMPACT_MIN: how small a manual
	-- resize may go; below MIN the layout turns Compact/Mobile. Both are cut down further to fit the screen.
	local MIN = opts.MinSize or Vector2.new(420, 260)
	local COMPACT_MIN = opts.CompactMinSize or Vector2.new(math.min(320, MIN.X), math.min(220, MIN.Y))
	local MAX = opts.MaxSize or Vector2.new(1400, 900)
	-- UI scale of the window (UIScale inside it). Layout math runs in unscaled units; measurements read from
	-- AbsoluteSize are divided by it.
	local scale = type(opts.Scale) == "number" and math.clamp(opts.Scale, 0.5, 2) or 1
	local function px(v) return v / scale end
	local stats = { relayouts = 0, draws = 0, header = 0, status = 0, selectable = 0 } -- audit counters (GetDiagnostics)
	local function nextOrder() order += 1; return order end
	local function connect(signal, fn) return maid:Give(signal:Connect(fn)) end
	local function animate(obj, info, props, onDone) return anim:Play(obj, info, props, onDone) end
	-- Style bindings: each component registers how its own instances read the tokens. A style switch re-runs them on
	-- the same instances (nothing is rebuilt): tweened on the visible page and the chrome, assigned elsewhere.
	-- sty() is the one way presentation properties are written, so a running switch and a later plain update never
	-- fight: an assignment first stops that property's tween, and AnimationManager cancels older tweens.
	local styleBindings, styleAnimating = {}, false
	local function sty(obj, props)
		if styleAnimating then
			animate(obj, STYLE_TWEEN, props)
		else
			local names = {}
			for k in pairs(props) do names[#names + 1] = k end
			anim:Stop(obj, names)
			for k, v in pairs(props) do obj[k] = v end
		end
	end
	local function bindStyle(page, inst, fn)
		table.insert(styleBindings, { page = page, inst = inst, fn = fn })
		fn(style)
	end
	-- Touch never gets a row shorter than 36px, whatever the style.
	local function rowMin(t) return UIS.TouchEnabled and math.max(36, t.RowMinHeight) or t.RowMinHeight end

	---------------------------------------------------------------- SaveManager storage
	-- Backend: opts.Storage {Load, Save}; without one, state lives in `shared` for this game session only.
	local backend, sessionOnly = opts.Storage, false
	if not (type(backend) == "table" and backend.Load and backend.Save) then
		sessionOnly = true
		shared.EthosSession = type(shared.EthosSession) == "table" and shared.EthosSession or {}
		local bucket, key = shared.EthosSession, opts.SaveKey or opts.Title or "DELTA HUB"
		backend = { Load = function() return bucket[key] end, Save = function(d) bucket[key] = d end }
	end
	local function migrate(data)
		if type(data) ~= "table" then return { Version = SCHEMA, Profile = "default", Profiles = {} } end
		if data.Version == nil then -- v1 adapter data: the flat window table
			return { Version = SCHEMA, Profile = "default", Profiles = { default = { Window = data, Values = {} } } }
		end
		if type(data.Profiles) ~= "table" then data.Profiles = {} end
		if type(data.Profile) ~= "string" or data.Profile == "" then data.Profile = "default" end
		data.Version = SCHEMA
		return data
	end
	local function sanitize(p)
		p = type(p) == "table" and p or {}
		if type(p.Window) ~= "table" then p.Window = {} end
		if type(p.Values) ~= "table" then p.Values = {} end
		return p
	end
	local store
	do
		local ok, data = pcall(backend.Load)
		if not ok then warn("[Ethos] load failed, starting fresh: " .. tostring(data)) end
		store = migrate(ok and data or nil)
	end
	local prof = sanitize(store.Profiles[store.Profile])
	store.Profiles[store.Profile] = prof
	-- Window fields that must be known before the first layout (fold and page are restored later).
	-- Missing or invalid fields fall back to the CreateWindow options (that is also what Reset gives).
	local defaults = { Locked = locked, SizeLocked = sizeLocked, Layout = layoutMode, Compact = compactPref, Sidebar = sidebarPref, WindowLayout = windowLayoutPref, TabAnimations = tabAnimations, TabSpeed = tabSpeed, GridMax = gridMax, EqualRows = equalRows, FitContent = fitContent, Transitions = transitionsOn, Speed = transitionSpeed, Style = stylePref }
	local function readWindow(w)
		favorites.list, favorites.set = {}, {}
		if type(w.Favorites) == "table" then
			for _, id in ipairs(w.Favorites) do
				if type(id) == "string" and #id > 0 and #id <= 1000 and not favorites.set[id] and #favorites.list < 200 then
					favorites.set[id] = true
					table.insert(favorites.list, id)
				end
			end
		end
		if type(w.Locked) == "boolean" then locked = w.Locked else locked = defaults.Locked end
		if type(w.SizeLocked) == "boolean" then sizeLocked = w.SizeLocked else sizeLocked = defaults.SizeLocked end
		layoutMode = LAYOUTS[w.Layout] and w.Layout or defaults.Layout
		compactPref = COMPACT_MODES[w.CompactMode] and w.CompactMode or defaults.Compact
		stylePref = (w.Style == "Modern" or w.Style == "Classic") and w.Style or defaults.Style
		if type(w.SidebarCollapsed) == "boolean" then sidebarPref = w.SidebarCollapsed else sidebarPref = defaults.Sidebar end
		-- Older profiles keep their collapse behavior through Auto; explicit saved layouts take precedence.
		if WINDOW_LAYOUTS[w.WindowLayout] then
			windowLayoutPref = w.WindowLayout
		elseif w.WindowLayout == nil and type(w.SidebarCollapsed) == "boolean" then
			windowLayoutPref = "Auto" -- honor legacy saved navigation even if new defaults differ
		else
			windowLayoutPref = defaults.WindowLayout
		end
		if type(w.TabAnimations) == "boolean" then tabAnimations = w.TabAnimations else tabAnimations = defaults.TabAnimations end
		tabSpeed = num(w.TabAnimationSpeed) and math.clamp(w.TabAnimationSpeed, 0.25, 4) or defaults.TabSpeed
		gridMax = num(w.MaxSectionGridWidth) and w.MaxSectionGridWidth >= 240 and w.MaxSectionGridWidth or defaults.GridMax
		if type(w.EqualRowHeight) == "boolean" then equalRows = w.EqualRowHeight else equalRows = defaults.EqualRows end
		if type(w.FitWindowToContent) == "boolean" then fitContent = w.FitWindowToContent else fitContent = defaults.FitContent end
		if type(w.Transitions) == "boolean" then transitionsOn = w.Transitions else transitionsOn = defaults.Transitions end
		transitionSpeed = num(w.TransitionSpeed) and math.clamp(w.TransitionSpeed, 0.25, 4) or defaults.Speed
		manualSize = num(w.W) and num(w.H) and Vector2.new(w.W, w.H) or nil
		wantPos = num(w.X) and num(w.Y) and Vector2.new(w.X, w.Y) or nil -- clamped to the screen on layout
	end
	readWindow(prof.Window)
	style = STYLE_TOKENS[stylePref] -- the saved style is known before anything is built: no flash of the other style
	local function savedExpanded(key)
		return rememberOptions and type(prof.Window.Expanded) == "table" and table.find(prof.Window.Expanded, key) ~= nil
	end
	local SaveManager = { SessionOnly = sessionOnly, OnSaved = nil } -- OnSaved(ok, err) runs after every write

	local function snapshot()
		local values = table.clone(prof.Values) -- keeps values of components not created this run
		for _, key in ipairs(componentOrder) do values[key] = components[key].encode() end
		local expanded
		if rememberOptions then
			expanded = {}
			for _, panel in ipairs(optionPanels) do
				if panel.Options:IsOpen() then table.insert(expanded, panel.key) end
			end
		end
		return {
			Window = {
				X = wantPos and wantPos.X, Y = wantPos and wantPos.Y, W = manualSize and manualSize.X, H = manualSize and manualSize.Y,
				Folded = minimized, Locked = locked, SizeLocked = sizeLocked, Layout = layoutMode, Page = current and current.key,
				Expanded = expanded, CompactMode = compactPref, SidebarCollapsed = sidebarPref, WindowLayout = windowLayoutPref,
				Transitions = transitionsOn, TransitionSpeed = transitionSpeed, Style = stylePref,
				TabAnimations = tabAnimations, TabAnimationSpeed = tabSpeed,
				MaxSectionGridWidth = gridMax, EqualRowHeight = equalRows, FitWindowToContent = fitContent,
				Favorites = table.clone(favorites.list),
			},
			Values = values,
		}
	end
	-- Runs a user callback in its own thread: errors are reported with a traceback and never stop the caller.
	local function fire(label, fn, ...)
		if type(fn) ~= "function" then return end
		task.spawn(function(...)
			local ok, err = xpcall(fn, debug.traceback, ...)
			if not ok then warn("[Ethos] " .. label .. " callback failed: " .. tostring(err)) end
		end, ...)
	end
	local function flush()
		if pendingSave then
			if coroutine.status(pendingSave) ~= "dead" and pendingSave ~= coroutine.running() then task.cancel(pendingSave) end
			pendingSave = nil
		end
		prof = snapshot()
		store.Profiles[store.Profile] = prof
		local ok, err = pcall(backend.Save, store)
		if not ok then
			warn("[Ethos] save failed: " .. tostring(err))
			if notify then notify("Could not save the profile.", "error") end
		end
		fire("OnSaved", SaveManager.OnSaved, ok, not ok and tostring(err) or nil)
		return ok
	end
	-- Debounced auto-save: bursts of changes (slider drags) write once, 0.5s after the last one starts.
	local function markDirty()
		if restoring or not autoSave or pendingSave or maid._dead then return end
		pendingSave = task.delay(0.5, flush)
	end

	---------------------------------------------------------------- instances
	local gui = maid:Give(new("ScreenGui", {
		Name = "kenei_ui", ResetOnSpawn = false, IgnoreGuiInset = false, DisplayOrder = opts.DisplayOrder or 100,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = opts.Parent or Players.LocalPlayer:WaitForChild("PlayerGui"),
	}))
	-- Safe area: lay out inside the region Roblox reports as free of the top bar and device cutouts (notches,
	-- rounded corners). Older clients without ScreenInsets keep the GUI inset behaviour above.
	pcall(function() gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets end)
	-- Exact, synchronous text widths: TextBounds of a hidden, never-truncated label (verified to match
	-- GetTextBoundsAsync) — no estimate, no wait, no one-frame flicker.
	local measurer = new("TextLabel", { Name = "Measure", Parent = gui, Visible = false, AutomaticSize = AUTO_X, Size = UDim2.fromOffset(0, 20), BackgroundTransparency = 1 })
	local function textWidth(text, size, face)
		measurer.FontFace, measurer.TextSize, measurer.Text = face, size, text
		return math.ceil(measurer.TextBounds.X)
	end
	-- Everything sits in a full-size root so layout and clamping read one rect (and tests can shrink it).
	local root = new("Frame", { Name = "Root", Parent = gui, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })

	local window = new("Frame", { Name = "Window", Parent = root, BackgroundColor3 = Theme.Background, BorderSizePixel = 0 }, {
		corner(4),
		new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2, Transparency = 0.7 }),
	})
	local windowScale = new("UIScale", { Parent = window, Scale = scale })
	local topbar = new("Frame", {
		Name = "Topbar", Parent = window, Size = UDim2.new(1, 0, 0, HEADER_H), BackgroundColor3 = Theme.Panel,
		BorderSizePixel = 0, ZIndex = 10, Active = true,
	}, {
		corner(4),
		-- squares off the header's bottom corners
		new("Frame", { Name = "Fill", Position = UDim2.new(0, 0, 1, -6), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = Theme.Panel, BorderSizePixel = 0 }),
		new("Frame", { Name = "Line", Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Theme.Border, BorderSizePixel = 0 }),
	})
	local base = new("Frame", { Name = "Base", Parent = topbar, BackgroundTransparency = 1, ClipsDescendants = true }, {
		hlist(6),
		label({ Name = "Title", Text = opts.Title or "DELTA HUB", TextSize = 16, FontFace = Font.new(FONT, W.Bold), TextColor3 = Theme.Text, AutomaticSize = AUTO_X, Size = UDim2.fromScale(0, 1) }),
		new("Frame", { Name = "Gap", BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 1), LayoutOrder = 1 }),
	})
	local titleLabel = base.Title
	local accent = opts.Badge and new("TextLabel", {
		Name = "Badge", Parent = base, Text = opts.Badge, TextSize = 12, FontFace = Font.new(FONT, W.Bold),
		TextColor3 = Theme.OnAccent, BackgroundColor3 = Theme.Accent, BorderSizePixel = 0,
		AutomaticSize = AUTO_X, Size = UDim2.fromOffset(0, 16), LayoutOrder = 2, -- even height: centers exactly in the 44px header
	}, { corner(2), padding(4, 4) })
	local control = new("Frame", {
		Name = "Control", Parent = topbar, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0),
		Size = UDim2.new(0, 60, 1, 0), BackgroundTransparency = 1,
	}, { hlist(4, Enum.HorizontalAlignment.Right) })
	local function iconButton(name, image, layoutOrder, iconSize)
		local b = new("TextButton", { Name = name, Parent = control, Text = "", BackgroundTransparency = 1, Size = UDim2.fromOffset(28, 28), LayoutOrder = layoutOrder })
		local icon = iconImage({ Parent = b, Image = image, ImageColor3 = Theme.Muted, Size = UDim2.fromOffset(iconSize, iconSize) })
		local scale = new("UIScale", { Parent = b })
		hover(b, function(on)
			animate(icon, FAST, { ImageColor3 = on and Theme.Text or Theme.Muted })
			if not on then animate(scale, FAST, { Scale = 1 }) end
		end)
		b.InputBegan:Connect(function(i)
			if POINTER[i.UserInputType] then animate(scale, FAST, { Scale = 0.88 }) end
		end)
		b.InputEnded:Connect(function(i)
			if POINTER[i.UserInputType] then animate(scale, FAST, { Scale = 1 }) end
		end)
		return b, icon
	end
	local minimizeBtn, minimizeIcon = iconButton("Minimize", ICON.minimize, 1, 18)
	local closeBtn = iconButton("Close", ICON.close, 2, 20)
	-- Overflow (···): appears when header badges don't fit; lists what was hidden.
	local moreBtn = new("TextButton", { Name = "More", Parent = control, Text = "", BackgroundTransparency = 1, Size = UDim2.fromOffset(28, 28), LayoutOrder = 0, Visible = false })
	for i = -1, 1 do
		new("Frame", { Parent = moreBtn, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, i * 5, 0.5, 0), Size = UDim2.fromOffset(3, 3), BackgroundColor3 = Theme.Muted, BorderSizePixel = 0 }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	end
	hover(moreBtn, function(on)
		for _, d in ipairs(moreBtn:GetChildren()) do animate(d, FAST, { BackgroundColor3 = on and Theme.Text or Theme.Muted }) end
	end)

	-- Search lives in the shared 44px header for both navigation layouts.
	local search = { open = false }
	search.field = new("Frame", { Name = "SearchField", Parent = control, Size = UDim2.fromOffset(0, 28), BackgroundColor3 = Theme.Background, BorderSizePixel = 0, ClipsDescendants = true, Visible = false, LayoutOrder = -2 }, { corner(3), stroke() })
	search.box = new("TextBox", { Name = "NavigationSearch", Parent = search.field, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", PlaceholderText = "Search pages and settings", PlaceholderColor3 = Theme.Muted, TextColor3 = Theme.Text, TextSize = 13, FontFace = Font.new(FONT), ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left }, { padding(8, 8) })
	search.button = new("TextButton", { Name = "SearchToggle", Parent = control, Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromOffset(28, 28), LayoutOrder = -1 })
	do
		local lens = new("Frame", { Name = "Lens", Parent = search.button, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(12, 12), BackgroundTransparency = 1 }, { corner(6), stroke(Theme.Muted, 1.5) })
		local handle = new("Frame", { Name = "Handle", Parent = search.button, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(20, 20), Size = UDim2.fromOffset(7, 2), Rotation = 45, BackgroundColor3 = Theme.Muted, BorderSizePixel = 0 }, { corner(1) })
		hover(search.button, function(on)
			animate(lens:FindFirstChildOfClass("UIStroke"), FAST, { Color = on and Theme.Text or Theme.Muted })
			animate(handle, FAST, { BackgroundColor3 = on and Theme.Text or Theme.Muted })
		end)
	end
	connect(search.field:GetPropertyChangedSignal("Size"), function() headerDirty = true end)

	-- Clips so the sliding drawer and the folding body never draw outside the window.
	local content = new("Frame", { Name = "Content", Parent = window, Position = UDim2.fromOffset(0, HEADER_H + 1), Size = UDim2.new(1, 0, 1, -(HEADER_H + 1)), BackgroundTransparency = 1, ClipsDescendants = true })
	-- Sidebar, status bar and veil reach the window's bottom corners, so they round them too (same color as the body).
	local sidebar = new("Frame", {
		Name = "SideBar", Parent = content, BackgroundColor3 = Theme.Background, BorderSizePixel = 0, ZIndex = 3, Active = true,
	}, {
		corner(4),
		new("Frame", { Name = "SideLine", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = Theme.Border, BorderSizePixel = 0 }),
	})
	local sideScroll = new("ScrollingFrame", {
		Name = "Scroll", Parent = sidebar, Size = UDim2.new(1, -1, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = AUTO_Y, ScrollingDirection = Enum.ScrollingDirection.Y,
	}, { vlist(10), padding(15, 19, 10, 10) })
	bindStyle(nil, sideScroll, function(t)
		local sp = t.SidebarPad
		sty(sideScroll:FindFirstChildOfClass("UIPadding"), { PaddingLeft = UDim.new(0, sp[1]), PaddingRight = UDim.new(0, sp[2]), PaddingTop = UDim.new(0, sp[3]), PaddingBottom = UDim.new(0, sp[4]) })
		sty(sideScroll:FindFirstChildOfClass("UIListLayout"), { Padding = UDim.new(0, t.CategoryGap) })
	end)

	search.favoritesNav = new("TextButton", { Name = "Favorites", Parent = sideScroll, Text = "Favorites", TextSize = 14, FontFace = Font.new(FONT, W.Medium), TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, AutoButtonColor = false, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = -1 }, { padding(10, 0) })
	hover(search.favoritesNav, function(on) animate(search.favoritesNav, FAST, { TextColor3 = on and Theme.Accent or Theme.SubText }) end)
	local indicatorLayer = new("Frame", { Name = "TabIndicatorLayer", Parent = sidebar, Size = UDim2.new(1, -1, 1, 0), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 2 })
	local indicator = new("Frame", { Name = "ActiveTabIndicator", Parent = indicatorLayer, BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Visible = false }, { corner(1) })
	local pageContainer = new("Frame", { Name = "PageContainer", Parent = content, BackgroundTransparency = 1, ClipsDescendants = true })
	-- Compact navigation: a toolbar with the menu button and the active page, shown while the sidebar is a drawer.
	local toolbar = new("Frame", { Name = "Toolbar", Parent = content, Size = UDim2.new(1, 0, 0, TOOLBAR_H), Position = UDim2.fromOffset(0, -TOOLBAR_H), BackgroundColor3 = Theme.Background, BorderSizePixel = 0, ZIndex = 4, Visible = false }, {
		new("Frame", { Name = "Line", Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Theme.Border, BorderSizePixel = 0 }),
	})
	local nav = new("TextButton", { Name = "Nav", Parent = toolbar, Text = "", BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 0), Size = UDim2.new(0, 36, 1, -1) })
	for i = -1, 1 do
		new("Frame", { Parent = nav, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, i * 5), Size = UDim2.fromOffset(14, 2), BackgroundColor3 = Theme.SubText, BorderSizePixel = 0 })
	end
	local crumb = label({ Name = "Crumb", Parent = toolbar, Position = UDim2.fromOffset(42, 0), Size = UDim2.new(1, -50, 1, -1), TextSize = 13, FontFace = Font.new(FONT, W.Medium), TextColor3 = Theme.Text, Text = "" })
	-- Dims the page behind the open drawer; a tap on it closes the drawer.
	local backdrop = new("TextButton", { Name = "Backdrop", Parent = content, Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 6, Visible = false })
	local footer = new("Frame", {
		Name = "StatusBar", Parent = content, AnchorPoint = Vector2.new(0, 1), BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0, ClipsDescendants = true, Visible = false,
	}, { hlist(0), corner(4) })
	local footerLine = new("Frame", { Name = "StatusLine", Parent = content, BackgroundColor3 = Theme.Border, BorderSizePixel = 0, Visible = false })
	-- Fades in over the body while folding (cheaper than fading every element) and blocks input while folded.
	local veil = new("Frame", { Name = "Veil", Parent = content, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Background, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 20, Active = true, Visible = false }, { corner(4) })
	do
	local toast = new("Frame", { Name = "Feedback", Parent = content, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -12), Size = UDim2.new(1, -24, 0, 42), BackgroundColor3 = Theme.Panel, BorderSizePixel = 0, ZIndex = 40, Visible = false }, { corner(3), stroke(Theme.Border), new("UISizeConstraint", { MaxSize = Vector2.new(340, 42) }) })
	local toastText = label({ Name = "Message", Parent = toast, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), TextSize = 13, TextColor3 = Theme.Text, TextWrapped = true, Text = "", ZIndex = 41 })
	local toastTimer, toastGeneration = nil, 0
	notify = function(message, kind, duration)
		if maid._dead then return end
		toastGeneration += 1
		local generation = toastGeneration
		if toastTimer and coroutine.status(toastTimer) ~= "dead" then task.cancel(toastTimer) end
		toastText.Text = tostring(message)
		toastText.TextColor3 = kind == "error" and Theme.Warn or (kind == "success" and Theme.Good or Theme.Text)
		toast.Visible = true
		toastTimer = task.delay(math.clamp(tonumber(duration) or 3, 0.5, 10), function()
			if not maid._dead and generation == toastGeneration then toast.Visible = false end
		end)
	end
	maid:Give(function() if toastTimer and coroutine.status(toastTimer) ~= "dead" then task.cancel(toastTimer) end end)
	end
	search.results = new("ScrollingFrame", { Name = "SearchResults", Parent = window, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, HEADER_H + 2), Size = UDim2.fromOffset(300, 0), BackgroundColor3 = Theme.Background, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = Theme.Scrollbar, CanvasSize = UDim2.new(), AutomaticCanvasSize = AUTO_Y, ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false, ZIndex = 35 }, { corner(3), stroke(), vlist(2), padding(4, 4, 4, 4) })
	local foldValue = new("NumberValue", { Name = "Fold", Parent = gui }) -- 0 expanded .. 1 folded, tweened
	-- Bottom-right resize grip: the six dots are only drawn; a separate invisible button takes the input.
	-- Mouse: the button covers the dots' 22px corner. Touch: it grows to TOUCH_HIT (44px) centered on the
	-- window corner, so inside the window it still covers only that 22px corner and the extra reach lies
	-- outside the window, where none of our controls are.
	local gripDots = new("Frame", { Name = "ResizeDots", Parent = window, AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 1, ZIndex = 30 })
	for _, d in ipairs({ { 4, 4 }, { 8, 4 }, { 4, 8 }, { 12, 4 }, { 8, 8 }, { 4, 12 } }) do
		new("Frame", { Parent = gripDots, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -d[1], 1, -d[2]), Size = UDim2.fromOffset(2, 2), BackgroundColor3 = Theme.Muted, BorderSizePixel = 0, ZIndex = 30 })
	end
	local grip = new("TextButton", { Name = "Resize", Parent = window, Text = "", BackgroundTransparency = 1, AutoButtonColor = false, ZIndex = 31 })
	local function sizeGripFor(inputType)
		-- touch-capable screens always get the big target, so the very first touch can't miss it
		local touch = UIS.TouchEnabled or inputType == Enum.UserInputType.Touch
		if touch then
			grip.AnchorPoint, grip.Position, grip.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(1, 1), UDim2.fromOffset(TOUCH_HIT, TOUCH_HIT)
		else
			grip.AnchorPoint, grip.Position, grip.Size = Vector2.new(1, 1), UDim2.fromScale(1, 1), UDim2.fromOffset(22, 22)
		end
	end
	sizeGripFor(UIS:GetLastInputType())
	hover(grip, function(on)
		for _, dot in ipairs(gripDots:GetChildren()) do animate(dot, FAST, { BackgroundColor3 = on and Theme.Text or Theme.Muted }) end
	end)

	---------------------------------------------------------------- window state
	-- Target size for clamping: folded is exactly the header, so top and bottom padding match.
	local function windowSize() return Vector2.new(size.X, minimized and HEADER_H or size.Y) end
	-- The only writer of window.Position. nil centers by the expanded size, so folding never re-centers.
	-- Positions live in screen pixels (the root isn't scaled); the window's drawn size is its logical size * scale.
	local function setPos(p)
		local vs, ws = root.AbsoluteSize, windowSize() * scale
		p = p or (vs - size * scale) / 2
		pos = Vector2.new(math.clamp(p.X, 0, math.max(0, vs.X - ws.X)), math.clamp(p.Y, 0, math.max(0, vs.Y - ws.Y)))
		window.Position = UDim2.fromOffset(math.round(pos.X), math.round(pos.Y)) -- whole pixels: no blurry 1px seams
	end
	local function snap(p)
		local vs, ws = root.AbsoluteSize, windowSize() * scale
		local x = p.X < SNAP and 0 or p.X > vs.X - ws.X - SNAP and vs.X - ws.X or p.X
		local y = p.Y < SNAP and 0 or p.Y > vs.Y - ws.Y - SNAP and vs.Y - ws.Y or p.Y
		return Vector2.new(x, y)
	end
	-- Three sizes: preferred (manualSize, or 800x500), effective limits (MinSize/MaxSize cut down to what the
	-- screen fits, keeping an 8px margin while the screen allows it), and the drawn size. Only a resize gesture or
	-- SetSize changes the preferred size, so a small screen shrinks the window without forgetting the user's size.
	-- Returns (effective minimum, effective maximum, effective compact minimum), all in logical units: the preferred
	-- MinSize, the CompactMinSize a manual resize may reach, and MaxSize, each cut down to what the screen fits.
	local function limits()
		local vs = root.AbsoluteSize / scale
		local availW = math.max(vs.X - 16, math.min(vs.X, 160)) -- tiny screens: use the whole width
		local availH = math.max(vs.Y - 16, math.min(vs.Y, HEADER_H + 60))
		local maxS = Vector2.new(math.min(MAX.X, availW), math.min(MAX.Y, availH))
		local minS = Vector2.new(math.min(MIN.X, maxS.X), math.min(MIN.Y, maxS.Y))
		return minS, maxS, Vector2.new(math.min(COMPACT_MIN.X, maxS.X), math.min(COMPACT_MIN.Y, maxS.Y))
	end
	-- The automatic size respects the preferred minimum; a size the user chose may go down to the compact minimum.
	local function computeSize()
		local minS, maxS, compactS = limits()
		local floor = manualSize and compactS or minS
		local want = manualSize or Vector2.new(800, 500)
		if fitContent and current and current.contentH and layoutReady then
			local toolbarHeight = navDrawer and TOOLBAR_H or 0
			local footerHeight = statuses > 0 and FOOTER_H + 1 or 0
			local contentHeight = math.max(60, current.contentH + (current.padY or 0))
			want = Vector2.new(want.X, HEADER_H + 1 + toolbarHeight + footerHeight + contentHeight)
		end
		size = Vector2.new(math.round(math.clamp(want.X, floor.X, maxS.X)), math.round(math.clamp(want.Y, floor.Y, maxS.Y)))
	end
	local function refreshGrip()
		grip.Visible = not minimized and not sizeLocked
		gripDots.Visible = grip.Visible
	end
	local popupReturn -- the control that had keyboard/gamepad focus when a popup opened
	local ownsSelection, focusTo, focusFallback -- keyboard/gamepad focus helpers (navigation block below)
	local function closePopup()
		if not popup then return end
		local sel = GuiService.SelectedObject
		local hadFocus = sel ~= nil and sel:IsDescendantOf(popup)
		popup:Destroy()
		popup = nil
		local ret = popupReturn
		popupReturn = nil
		if hadFocus and ret then -- next frame, after the engine has finished handling the key that closed it
			task.defer(function()
				if ret.Parent then GuiService.SelectedObject = ret end
			end)
		end
	end
	-- Drawer navigation (Compact/Mobile, or a collapsed sidebar): the same sidebar slides in over the page,
	-- below the toolbar, with a dimmed backdrop. Docked placement is done by layoutChrome.
	local function setDrawer(open, instant)
		local was = drawerOpen
		drawerOpen = (open and navDrawer) and true or false
		selDirty = true
		-- an open drawer keeps keyboard/gamepad selection inside it; docked, selection may leave the sidebar
		local behavior = drawerOpen and Enum.SelectionBehavior.Stop or Enum.SelectionBehavior.Escape
		sidebar.SelectionBehaviorUp, sidebar.SelectionBehaviorDown = behavior, behavior
		sidebar.SelectionBehaviorLeft, sidebar.SelectionBehaviorRight = behavior, behavior
		if ownsSelection and was ~= drawerOpen and ownsSelection() then
			task.defer(function() focusTo(drawerOpen and focusFallback and focusFallback() or nav) end)
		end
		if not navDrawer then
			anim:Stop(backdrop)
			backdrop.Visible, backdrop.BackgroundTransparency = false, 1
			return
		end
		local target = UDim2.fromOffset(drawerOpen and 0 or -(sidebar.Size.X.Offset + 2), TOOLBAR_H)
		if drawerOpen then
			sidebar.Visible, backdrop.Visible = true, true
			closePopup()
		end
		if instant then
			anim:Stop(sidebar, { "Position" }) -- a running slide must not land after the jump
			anim:Stop(backdrop)
			sidebar.Position, sidebar.Visible = target, drawerOpen
			backdrop.BackgroundTransparency, backdrop.Visible = drawerOpen and 0.45 or 1, drawerOpen
			return
		end
		animate(sidebar, NAV, { Position = target }, function()
			if not drawerOpen and navDrawer then sidebar.Visible = false end
		end)
		animate(backdrop, NAV, { BackgroundTransparency = drawerOpen and 0.45 or 1 }, function()
			if not drawerOpen then backdrop.Visible = false end
		end)
	end

	-- Draws the fold at its current progress. Height is rounded so the bottom edge never sits on a half pixel.
	local function paintFold()
		local a = foldValue.Value
		window.Size = UDim2.fromOffset(size.X, math.round(size.Y + (HEADER_H - size.Y) * a))
		local closed = window.Size.Y.Offset <= HEADER_H + 4
		-- folded: drop the square filler and divider so the header shows its own four rounded corners
		topbar.Fill.Visible, topbar.Line.Visible = not closed, not closed
		veil.Visible, veil.BackgroundTransparency = a > 0, 1 - a
		if content.Visible ~= (a < 1) then
			content.Visible = a < 1 -- fully folded: body takes no input and isn't drawn
			selDirty = true
		end
	end
	foldValue.Changed:Connect(paintFold)

	local function setFolded(v, instant)
		minimized = v and true or false
		closePopup()
		if drag and drag.resize then drag = nil end -- folding ends a resize in progress
		if minimized then
			setDrawer(false, true)
			if search.toggle and search.open then search.toggle(false) end
		end
		refreshGrip()
		if instant then
			anim:Stop(foldValue, { "Value" }) -- cancels a running fold
			foldValue.Value = minimized and 1 or 0
		else
			animate(foldValue, FOLD, { Value = minimized and 1 or 0 }) -- the latest request wins, from wherever it is now
		end
		paintFold()
		setPos(wantPos) -- unfolding near the bottom edge pulls the window back on screen
		local img = minimized and ICON.chevron or ICON.minimize
		if minimizeIcon.Image ~= img then -- minus <-> down chevron, cross-faded
			minimizeIcon.Image, minimizeIcon.Rotation = img, minimized and 90 or 0
			minimizeIcon.Size = UDim2.fromOffset(minimized and 14 or 18, minimized and 14 or 18)
			minimizeIcon.ImageTransparency = instant and 0 or 1
			animate(minimizeIcon, FAST, { ImageTransparency = 0 })
		end
		markDirty()
	end

	---------------------------------------------------------------- LayoutManager + SectionTransitionController
	-- Every page draws its sections on an absolutely positioned canvas (no UIListLayout owns them), so this block is
	-- the single owner of section rectangles. computeTargets() decides the layout from the measured canvas width,
	-- the sections' measured heights and their MinWidth/MaxWidth/FullWidth/Side; the transition controller then
	-- eases each section from where it is on screen to its target. One RenderStepped stepper serves the whole
	-- window and does nothing while nothing is moving. Rectangles are canvas-local offsets, so scrolling, the GUI
	-- inset and nesting never enter the math.
	local KIND_RANK = { height = 1, width = 2, insert = 3, structure = 3, instant = 4 }
	local layoutHeader, layoutStatus, debugStatus, navStep, refreshFit -- defined with the header/status/navigation code below
	local function markPage(p, kind)
		if not p.pending or KIND_RANK[kind] > KIND_RANK[p.pending] then p.pending = kind end
	end
	local function markAll(kind)
		for _, p in ipairs(pages) do markPage(p, kind) end
	end

	-- Pixel accuracy: the canvas width is floored once and each section height is rounded once (to the edge the
	-- renderer draws), so every target rectangle is whole pixels, every gap is exactly style.SectionGap and stacking
	-- never accumulates rounding error. Both are read in logical units (AbsoluteSize / scale).
	local function canvasWidth(p) return math.max(0, math.floor(px(p.canvas.AbsoluteSize.X) + 0.001)) end
	local function heightOf(s) return math.round(px(s.frame.AbsoluteSize.Y)) end
	local function naturalHeight(s)
		return math.max(0, math.round(px(s.list.AbsoluteContentSize.Y) + s.pad.PaddingTop.Offset + s.pad.PaddingBottom.Offset))
	end
	local function wantsDouble(p, W)
		if #p.sections < 2 or layoutMode == "Single" then return false end
		local minW = 0
		for _, s in ipairs(p.sections) do
			if not s.full then minW = math.max(minW, s.minW or style.SectionMin) end
		end
		-- hysteresis: keep the current answer until the width is 12px past the threshold
		return W >= minW * 2 + style.SectionGap + (p.effective == "Double" and -12 or 12)
	end
	-- Fills s.to for every section; returns true when the page switched between one and two columns.
	local function computeTargets(p)
		stats.relayouts += 1
		local W = canvasWidth(p)
		local required = 0
		for _, s in ipairs(p.sections) do
			if not s.full then required = math.max(required, s.minW or style.SectionMin) end
		end
		-- A caller's section minima can raise the soft cap when the viewport can accommodate them.
		local canFitDouble = wantsDouble(p, W)
		local needed = canFitDouble and required * 2 + style.SectionGap + (p.effective == "Double" and 0 or 12) or required
		local grid = math.min(W, math.max(gridMax, needed))
		local double = canFitDouble and wantsDouble(p, grid)
		if double then
			local hL, hR = 0, 0
			for _, s in ipairs(p.sections) do
				local h = equalRows and naturalHeight(s) or heightOf(s)
				if s.full then
					hL, hR = math.max(hL, hR) + h + style.SectionGap, math.max(hL, hR) + h + style.SectionGap
				else
					local side = s.side
					if not side then
						if math.abs(hL - hR) < 12 and s.autoSide then side = s.autoSide else side = hL <= hR and "Left" or "Right" end
					end
					s.autoSide = side
					if side == "Left" then hL += h + style.SectionGap else hR += h + style.SectionGap end
				end
			end
			p.assignDirty = false
			local l, r = 0, 0
			for _, s in ipairs(p.sections) do
				if not s.full then if s.autoSide == "Left" then l += 1 else r += 1 end end
			end
			if l == 0 or r == 0 then double = false end
		end
		local contentH = 0
		if not double then
			local lone, y = #p.sections == 1, 0
			for _, s in ipairs(p.sections) do
				local cap = lone and math.min(style.LoneMax, grid) or grid
				local w = math.min(W, cap, s.maxW or math.huge)
				s.to = { x = 0, y = y, w = w }
				y += heightOf(s) + style.SectionGap
			end
			contentH = math.max(0, y - style.SectionGap)
		else
			local cw = math.floor((grid - style.SectionGap) / 2)
			local capL, capR = 0, 0
			for _, s in ipairs(p.sections) do
				if not s.full then
					if s.autoSide == "Left" then capL = math.max(capL, s.maxW or math.huge) else capR = math.max(capR, s.maxW or math.huge) end
				end
			end
			local wl, wr = math.min(cw, capL), math.min(cw, capR)
			local ox = 0
			if equalRows then
				local left, right, y = {}, {}, 0
				local function flushRows()
					for i = 1, math.max(#left, #right) do
						local l, r = left[i], right[i]
						local h = math.max(l and naturalHeight(l) or 0, r and naturalHeight(r) or 0)
						if l then l.to = { x = ox, y = y, w = math.min(wl, l.maxW or wl), h = h } end
						if r then r.to = { x = ox + wl + style.SectionGap, y = y, w = math.min(wr, r.maxW or wr), h = h } end
						y += h + style.SectionGap
					end
					table.clear(left); table.clear(right)
				end
				for _, s in ipairs(p.sections) do
					if s.full then
						flushRows()
						local w = math.min(grid, s.maxW or grid)
						s.to = { x = ox, y = y, w = w }
						y += naturalHeight(s) + style.SectionGap
					elseif s.autoSide == "Left" then table.insert(left, s) else table.insert(right, s) end
				end
				flushRows()
				contentH = math.max(0, y - style.SectionGap)
			else
				local yl, yr = 0, 0
				for _, s in ipairs(p.sections) do
					local h = heightOf(s)
					if s.full then
						local top, w = math.max(yl, yr), math.min(grid, s.maxW or grid)
						s.to = { x = ox, y = top, w = w }
						yl, yr = top + h + style.SectionGap, top + h + style.SectionGap
					elseif s.autoSide == "Left" then
						s.to = { x = ox, y = yl, w = math.min(wl, s.maxW or wl) }
						yl += h + style.SectionGap
					else
						s.to = { x = ox + wl + style.SectionGap, y = yr, w = math.min(wr, s.maxW or wr) }
						yr += h + style.SectionGap
					end
				end
				contentH = math.max(0, math.max(yl, yr) - style.SectionGap)
			end
		end
		local eff = #p.sections == 0 and "Empty" or (double and "Double" or "Single")
		local switched = p.effective ~= nil and p.effective ~= eff
		p.effective, p.contentH = eff, contentH
		p.empty.Visible = p == current and eff == "Empty"
		return switched
	end
	-- Draws every section at progress e (0 = where it started, 1 = its target).
	local function drawSections(p, e)
		stats.draws += 1
		local W = canvasWidth(p)
		local bottom = p.contentH or 0
		for _, s in ipairs(p.sections) do
			local f, t = s.from or s.to, s.to
			local x = math.round(f.x + (t.x - f.x) * e)
			local y = math.round(f.y + (t.y - f.y) * e)
			local w = math.round(f.w + (t.w - f.w) * e)
			w = math.max(0, math.min(w, W - x)) -- never wider than the canvas, so nothing is cut off sideways mid-move
			local h = t.h and math.round((f.h or heightOf(s)) + (t.h - (f.h or heightOf(s))) * e) or nil
			s.cur = { x = x, y = y, w = w, h = h or heightOf(s) }
			s.frame.Position = UDim2.fromOffset(x, y)
			s.frame.AutomaticSize = h and AUTO_NONE or AUTO_Y
			s.frame.Size = UDim2.fromOffset(w, h or 0)
			bottom = math.max(bottom, y + heightOf(s))
		end
		-- the canvas covers both where sections are and where they are going: no vertical clipping mid-move
		p.canvas.Size = UDim2.new(1, 0, 0, bottom)
		p.scroll.CanvasSize = UDim2.fromOffset(0, bottom + p.padY)
	end
	local function canAnimate(p)
		return p == current and layoutReady and transitionsOn and not minimized and foldValue.Value == 0 and not anim:IsReduced()
	end
	-- Scroll anchoring: the first section visible at the top keeps its on-screen spot through a structural change,
	-- unless the user scrolled in the last 0.35s (never fight an active scroll gesture).
	local function captureAnchor(p)
		if os.clock() - (p.userScrollAt or 0) < 0.35 then return nil end
		local top = p.scroll.CanvasPosition.Y
		if top < 1 then return nil end
		for _, s in ipairs(p.sections) do
			if s.cur and s.cur.y + heightOf(s) > top then return { s = s, offset = s.cur.y - top } end
		end
	end
	local function applyAnchor(p, a)
		local viewH = px(p.scroll.AbsoluteSize.Y)
		local want = math.clamp(a.s.to.y - a.offset, 0, math.max(0, (p.contentH or 0) + p.padY - viewH))
		local d = want - p.scroll.CanvasPosition.Y
		if math.abs(d) < 1 then return end
		p.scroll.CanvasSize = UDim2.fromOffset(0, math.max(p.scroll.CanvasSize.Y.Offset, want + viewH)) -- so it isn't clamped
		p.selfScroll = true
		p.scroll.CanvasPosition = Vector2.new(0, want)
		p.selfScroll = false
		-- shift the starting points with the canvas so nothing jumps on screen
		for _, s in ipairs(p.sections) do s.from = { x = s.from.x, y = s.from.y + d, w = s.from.w, h = s.from.h } end
	end
	local function relayout(p, kind)
		local anchor = (kind == "structure" or kind == "insert") and p == current and captureAnchor(p)
		local switched = computeTargets(p)
		for _, s in ipairs(p.sections) do
			if not s.cur then s.cur = s.to end -- a new section appears in place; its neighbours move
		end
		if kind == "instant" or not canAnimate(p) then
			p.tr = nil
			for _, s in ipairs(p.sections) do s.from = s.to end
			drawSections(p, 1)
			return
		end
		if switched then
			kind = "columns"
			selDirty = true -- focus order follows the new columns
		end
		if kind == "height" and not p.tr then
			-- content changed its own height (an options panel animating): later sections follow in lockstep,
			-- easing would let the growing panel overlap them
			for _, s in ipairs(p.sections) do s.from = s.to end
			drawSections(p, 1)
			return
		end
		if kind ~= "height" and (kind ~= "width" or not p.tr) then
			-- restart from what is on screen now, so an interrupted move never snaps
			for _, s in ipairs(p.sections) do s.from = s.cur end
			p.tr = { t = 0, dur = (MOVE[kind] or MOVE.width) / math.max(0.05, transitionSpeed * anim.Speed) }
			if anchor then applyAnchor(p, anchor) end
		end
		-- width/height while moving: targets were updated above, the running move keeps its progress
	end
	local function finishMoves(p)
		if p.tr then
			p.tr = nil
			for _, s in ipairs(p.sections) do s.from = s.to end
			drawSections(p, 1)
		end
	end
	connect(RunService.RenderStepped, function(dt)
		if headerDirty and layoutHeader then headerDirty = false; layoutHeader() end
		if statusDirty and layoutStatus then statusDirty = false; layoutStatus() end
		if navStep then navStep() end
		for _, p in ipairs(pages) do
			-- hidden pages stay dirty until shown (selectPage lays them out then), so a resize only lays out one page
			if p.pending and p == current then
				local k = p.pending
				p.pending = nil
				relayout(p, k)
			end
			local tr = p.tr
			if tr then
				tr.t += dt
				local a = math.min(1, tr.t / tr.dur)
				drawSections(p, TweenService:GetValue(a, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out))
				if a >= 1 then finishMoves(p) end
			end
		end
		if refreshFit then refreshFit() end
		if debugStatus and current then
			local text = string.format("%s→%s · %s%s", layoutMode, current.effective or "?", presentation or "?", navDrawer and " · drawer" or "")
			if debugStatus.text ~= text then debugStatus.text = text; debugStatus:Set(text) end
		end
	end)

	---------------------------------------------------------------- presentation (Full / Compact / Mobile)
	-- Decided from the measured window, not from TouchEnabled. 16px hysteresis keeps it from flickering at a threshold.
	local function decidePresentation()
		local ww, vh = size.X, root.AbsoluteSize.Y
		if compactPref ~= "Auto" then
			if compactPref == "Full" and ww - style.SidebarWidth < 200 then return "Compact" end -- no room left for content
			return compactPref
		end
		local h = 16
		local wasMobile, wasFull = presentation == "Mobile", presentation == "Full"
		if (wasMobile and (ww < 460 + h or vh < 380 + h)) or (not wasMobile and (ww < 460 - h or vh < 380 - h)) then return "Mobile" end
		local need = style.SidebarWidth + 340
		if (wasFull and ww >= need - h) or (not wasFull and ww >= need + h) then return "Full" end
		return "Compact"
	end
	-- The category viewport owns clipping; tabs are usable only once fully revealed.
	local tabGroups = {}
	local function tabAvailable(tab)
		local group = tabGroups[tab]
		if not group then return true end
		if not group.requested or not group.items.Visible then return false end
		local row = tab.Parent
		local top, height = group.viewport.AbsolutePosition.Y, group.viewport.AbsoluteSize.Y
		return row.AbsolutePosition.Y >= top - 1 and row.AbsolutePosition.Y + row.AbsoluteSize.Y <= top + height + 1
	end
	local indicatorTarget, indicatorPage
	local function updateIndicator(smooth)
		local p = current
		local shown = p and style.Underline and tabAvailable(p.tab) and p.tab.AbsoluteSize.Y > 0
		if not shown then
			if indicator.Visible or anim._running[indicator] then anim:Stop(indicator) end
			indicator.Visible, indicatorPage, indicatorTarget = false, nil, nil
			return
		end
		local tab = p.tab
		-- All tab and category text is inset from this shared gutter. The indicator can glide across
		-- intervening rows without crossing their text; AbsolutePosition already accounts for scrolling.
		local x = px(tab.Parent.AbsolutePosition.X - indicatorLayer.AbsolutePosition.X)
		local y = px(tab.Parent.AbsolutePosition.Y - indicatorLayer.AbsolutePosition.Y) + (px(tab.Parent.AbsoluteSize.Y) - 14) / 2
		local target = UDim2.fromOffset(math.round(x), math.round(y))
		local dims = UDim2.fromOffset(2, 14)
		local changed = not indicatorTarget or indicatorTarget.pos ~= target or indicatorTarget.size ~= dims
		if changed then
			local moving = smooth and indicator.Visible and indicatorPage ~= p and tabAnimations and layoutReady and not anim:IsReduced() and anim.Speed > 0
			indicatorTarget = { pos = target, size = dims }
			if moving then
				animate(indicator, TweenInfo.new(0.24 / tabSpeed, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), { Position = target, Size = dims })
			else
				anim:Stop(indicator)
				indicator.Position, indicator.Size = target, dims
			end
		end
		indicator.Visible, indicatorPage = true, p
	end
	local function refreshTabs()
		local tall = navDrawer
		for _, p in ipairs(pages) do
			local base = tall and style.DrawerTabHeight or style.TabHeight
			local padTop = math.floor((base - style.TabTextSize) / 2)
			p.tab.TextSize = style.TabTextSize
			if not p.pressed then p.tab.BackgroundTransparency = p == current and not style.Underline and 0.82 or 1 end
			sty(p.tabRow, { Size = UDim2.new(1, 0, 0, base) })
			anim:Stop(p.tabPad, { "PaddingLeft" })
			p.tabPad.PaddingLeft = UDim.new(0, style.Underline and 10 or 0)
			sty(p.tabPad, { PaddingTop = UDim.new(0, padTop) })
		end
		updateIndicator(false)
	end
	local function sectionPadding(pad)
		local v = presentation == "Mobile" and style.SectionPadMobile or style.SectionPad
		sty(pad, { PaddingLeft = UDim.new(0, v[1]), PaddingRight = UDim.new(0, v[2]), PaddingTop = UDim.new(0, v[3]), PaddingBottom = UDim.new(0, v[4]) })
	end
	local function pagePadding(p)
		local v = presentation == "Mobile" and style.PagePadMobile or style.PagePad
		sty(p.pad, { PaddingLeft = UDim.new(0, v[1]), PaddingRight = UDim.new(0, v[2]), PaddingTop = UDim.new(0, v[3]), PaddingBottom = UDim.new(0, v[4]) })
		p.padY = v[3] + v[4]
	end
	-- Places sidebar/drawer, toolbar, page area and status bar. Animated (0.25s) only when the navigation or
	-- presentation actually changes; a property already animating toward the same layout is left alone.
	-- force: animate even though navigation/presentation stayed the same (a style switch changes the sidebar width).
	local function layoutChrome(smooth, force)
		local prevPres, prevNav = presentation, navDrawer
		presentation = decidePresentation()
		if windowLayoutPref == "Topbar" then
			navDrawer = true
		elseif windowLayoutPref == "Sidebar" then
			-- Keep the requested mode while falling back when a dock would crowd the content.
			local threshold = style.SidebarWidth + 340 + (prevNav == true and 16 or -16)
			navDrawer = size.X < threshold or root.AbsoluteSize.Y < 364
		else
			navDrawer = presentation ~= "Full" or sidebarPref
		end
		local changed = force or (prevNav ~= nil and (prevNav ~= navDrawer or prevPres ~= presentation))
		local function place(obj, props, onDone)
			if smooth and changed then
				animate(obj, NAV, props, onDone)
			elseif not anim._running[obj] then
				for k, v in pairs(props) do obj[k] = v end
				if onDone then onDone() end
			end
		end
		local sw, tb = navDrawer and 0 or style.SidebarWidth, navDrawer and TOOLBAR_H or 0
		local fh = statuses > 0 and FOOTER_H + 1 or 0
		backdrop.Position, backdrop.Size = UDim2.fromOffset(0, TOOLBAR_H), UDim2.new(1, 0, 1, -TOOLBAR_H)
		if navDrawer then
			local dw = math.clamp(size.X - 48, 160, 240)
			if prevNav ~= true then drawerOpen = false end
			sidebar.ZIndex, sidebar.Size = 7, UDim2.new(0, dw, 1, -TOOLBAR_H)
			toolbar.Visible = true
			place(sidebar, { Position = UDim2.fromOffset(drawerOpen and 0 or -(dw + 2), TOOLBAR_H) }, function()
				if navDrawer and not drawerOpen then sidebar.Visible = false end
			end)
		else
			setDrawer(false, true)
			sidebar.ZIndex, sidebar.Visible = 3, true
			if smooth and changed then
				place(sidebar, { Position = UDim2.fromOffset(0, 0), Size = UDim2.new(0, style.SidebarWidth, 1, 0) })
			else
				anim:Stop(sidebar, { "Size" })
				sidebar.Size = UDim2.new(0, style.SidebarWidth, 1, 0)
				place(sidebar, { Position = UDim2.fromOffset(0, 0) })
			end
		end
		place(toolbar, { Position = UDim2.fromOffset(0, navDrawer and 0 or -TOOLBAR_H) }, function() toolbar.Visible = navDrawer end)
		place(pageContainer, { Position = UDim2.fromOffset(sw, tb), Size = UDim2.new(1, -sw, 1, -(fh + tb)) })
		footer.Visible, footerLine.Visible = fh > 0, fh > 0
		-- stops 22px short of the right edge: the resize grip's dots sit in that corner, on top of the last cell
		place(footer, { Position = UDim2.new(0, sw, 1, 0), Size = UDim2.new(1, -sw - 22, 0, FOOTER_H) })
		place(footerLine, { Position = UDim2.new(0, sw, 1, -FOOTER_H - 1), Size = UDim2.new(1, -sw, 0, 1) })
		if prevPres ~= presentation then
			-- Mobile trims purely decorative padding; text sizes and control heights stay the same
			for _, p in ipairs(pages) do
				pagePadding(p)
				for _, s in ipairs(p.sections) do sectionPadding(s.pad) end
			end
		end
		refreshTabs()
		if layoutHeader then layoutHeader() else headerDirty = true end
		if layoutStatus then layoutStatus() else statusDirty = true end
		selDirty = true
	end

	local function applyLayout()
		local vs = root.AbsoluteSize
		if vs.X < 2 or vs.Y < 2 then return end
		local first = presentation == nil
		computeSize()
		paintFold()
		layoutChrome(not first)
		closePopup()
		setPos(wantPos)
	end

	local pageGeneration, pageMoving = 0, false
	local function resetPage(p, visible)
		anim:Stop(p.frame)
		p.frame.Visible, p.frame.Position = visible, UDim2.fromOffset(0, 0)
		p.shield.Visible = false
		p.empty.Visible = visible and p == current and #p.sections == 0
	end
	refreshFit = function()
		if not (fitContent and current and current.contentH and layoutReady) then return end
		local before = size
		computeSize()
		if size ~= before then
			paintFold()
			layoutChrome(true)
			setPos(wantPos)
		end
	end
	local function selectPage(page)
		local previous = current
		if previous == page then
			if navDrawer and drawerOpen then setDrawer(false) end
			return
		end
		pageGeneration += 1
		local generation = pageGeneration
		closePopup()
		local selected = GuiService.SelectedObject
		if previous and selected and selected:IsDescendantOf(previous.frame) then
			GuiService.SelectedObject = (navDrawer and nav) or page.tab
		end
		current = page
		local motion = previous and layoutReady and tabAnimations and not restoring and not minimized and not anim:IsReduced() and anim.Speed > 0
		pageMoving = motion and true or false
		for _, p in ipairs(pages) do
			resetPage(p, p == page)
			if p ~= page then finishMoves(p) end
			animate(p.tab, FAST, { TextColor3 = p == page and Theme.Text or (p.hovered and Theme.SubText or Theme.Muted) })
			animate(p.tab, FAST, { BackgroundTransparency = p == page and not style.Underline and 0.82 or 1 })
		end
		page.frame.Visible = true
		page.frame.ZIndex = 2
		page.pending = nil
		relayout(page, "instant")
		if motion then
			local direction = previous.category == page.category and (page.index > previous.index and 1 or -1) or 0
			page.frame.Position = UDim2.fromOffset(direction * 10, 8)
			animate(page.frame, TweenInfo.new(0.27 / tabSpeed, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(0, 0) }, function()
				if generation == pageGeneration then
					page.frame.Position = UDim2.fromOffset(0, 0)
					pageMoving = false
				end
			end)
		end
		updateIndicator(true)
		crumb.Text = page.category .. "  /  " .. page.name
		selDirty = true
		if navDrawer and drawerOpen then setDrawer(false) end
		markDirty()
	end

	---------------------------------------------------------------- keyboard / gamepad navigation
	-- Native Roblox selection (GuiService.SelectedObject) does the work: arrows / D-pad move, Enter / A activates.
	-- Native selection ignores hidden ancestors, so only controls that are actually on screen are marked Selectable,
	-- refreshed (coalesced, once per frame at most) whenever visibility changes. The window is a selection group
	-- that stops at its edge, so focus never wanders into the game's own UI. Nothing here runs or binds input
	-- unless focus is inside this window.
	local focusRing = maid:Give(new("Frame", { Name = "FocusRing", BackgroundTransparency = 1, Size = UDim2.new(1, 4, 1, 4), Position = UDim2.fromOffset(-2, -2) }, {
		corner(4), stroke(Theme.Accent, 2),
	}))
	local focusables, noFocus = {}, { [grip] = true, [backdrop] = true }
	local function considerFocusable(obj)
		if obj:IsA("ScrollingFrame") then
			obj.Selectable = false -- scroll by moving between controls; native selection scrolls them into view
		elseif obj:IsA("GuiButton") or obj:IsA("TextBox") then
			obj.SelectionImageObject = focusRing
			focusables[obj] = true
		end
	end
	for _, d in ipairs(gui:GetDescendants()) do considerFocusable(d) end
	connect(gui.DescendantAdded, function(d)
		considerFocusable(d)
		selDirty = true
	end)
	connect(gui.DescendantRemoving, function(d) focusables[d] = nil end)
	window.SelectionGroup, sidebar.SelectionGroup = true, true
	window.SelectionBehaviorUp, window.SelectionBehaviorDown = Enum.SelectionBehavior.Stop, Enum.SelectionBehavior.Stop
	window.SelectionBehaviorLeft, window.SelectionBehaviorRight = Enum.SelectionBehavior.Stop, Enum.SelectionBehavior.Stop
	local function isShown(obj)
		local o = obj
		while o and o ~= gui do
			if o:IsA("GuiObject") and not o.Visible then return false end
			o = o.Parent
		end
		return o == gui
	end
	local function refreshSelectable()
		stats.selectable += 1
		for obj in pairs(focusables) do
			if obj.Parent then
				obj.Selectable = not noFocus[obj] and isShown(obj) and tabAvailable(obj) and (not obj:IsDescendantOf(pageContainer) or (current and obj:IsDescendantOf(current.frame)))
			else
				focusables[obj] = nil
			end
		end
		if not current then return end
		-- Up/Down follow each section's controls in order (open option rows included), then continue into the
		-- section directly below/above in the same column; native geometry can skip a row, this cannot.
		local chains = {}
		local function flatten(list, out)
			for _, item in ipairs(list) do
				if type(item) == "table" then
					flatten(item, out)
				elseif item.Parent then
					item.NextSelectionUp, item.NextSelectionDown = nil, nil
					if item.Selectable then table.insert(out, item) end
				end
			end
			return out
		end
		for _, sec in ipairs(current.sections) do chains[sec] = flatten(sec.stops or {}, {}) end
		for _, sec in ipairs(current.sections) do
			local chain = chains[sec]
			for i, obj in ipairs(chain) do
				obj.NextSelectionUp, obj.NextSelectionDown = chain[i - 1], chain[i + 1]
			end
			if #chain > 0 and sec.to then
				local below, above
				for _, o in ipairs(current.sections) do
					if o ~= sec and o.to and #chains[o] > 0 and o.to.x < sec.to.x + sec.to.w and sec.to.x < o.to.x + o.to.w then
						if o.to.y > sec.to.y and (not below or o.to.y < below.to.y) then below = o end
						if o.to.y < sec.to.y and (not above or o.to.y > above.to.y) then above = o end
					end
				end
				if below then chain[#chain].NextSelectionDown = chains[below][1] end
				if above then chain[1].NextSelectionUp = chains[above][#chains[above]] end
			end
		end
	end
	ownsSelection = function()
		local sel = GuiService.SelectedObject
		return sel ~= nil and sel:IsDescendantOf(gui)
	end
	focusTo = function(obj)
		if not (obj and obj.Parent) then return end
		selDirty = false
		refreshSelectable()
		if obj.Selectable then GuiService.SelectedObject = obj end
	end
	focusFallback = function()
		if minimized then return minimizeBtn end
		if navDrawer then
			if not drawerOpen then return nav end
			return current and (tabAvailable(current.tab) and current.tab or current.group.header) or nav
		end
		return current and (tabAvailable(current.tab) and current.tab or current.group.header) or minimizeBtn
	end
	-- Search indexes existing pages and setting rows; selecting a result keeps their original instances.
	do
	local searchGeneration, searchTask = 0, nil
	search.resizeResults = function()
		if not search.results.Visible then return end
		local maxHeight = math.max(42, math.min(280, size.Y - HEADER_H - 12))
		search.results.Size = UDim2.fromOffset(math.max(120, math.min(340, size.X - 20)), math.min(maxHeight, search.resultHeight or 44))
	end
	search.targetWidth = function()
		local titleWidth = textWidth(titleLabel.Text, 16, titleLabel.FontFace)
		return math.min(220, math.max(64, size.X - 129 - titleWidth))
	end
	search.toggle = function(open, focusInput)
		if open == nil then open = not search.open end
		open = open == true
		if search.open == open then return end
		search.open = open
		if open then
			if minimized then setFolded(false) end
			if drawerOpen then setDrawer(false) end
			search.field.Visible = true
			if refreshSearch then refreshSearch() end
			local width = search.targetWidth()
			animate(search.field, TweenInfo.new(0.24, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(width, 28) }, function()
				if search.open and not maid._dead then
					if focusInput ~= false then
						search.box:CaptureFocus()
					elseif ownsSelection() then
						focusTo(search.results:FindFirstChild("SearchResult", true) or search.button)
					end
				end
			end)
		else
			local focused = ownsSelection() and (GuiService.SelectedObject == search.box or GuiService.SelectedObject:IsDescendantOf(search.results))
			search.box:ReleaseFocus()
			search.box.Text = ""
			search.results.Visible = false
			base.Visible = true
			animate(search.field, TweenInfo.new(0.20, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(0, 28) }, function()
				if not search.open then search.field.Visible = false; headerDirty, selDirty = true, true end
			end)
			if focused then GuiService.SelectedObject = search.button end
		end
		headerDirty, selDirty = true, true
	end
	search.button.Activated:Connect(function() search.toggle() end)
	search.favoritesNav.Activated:Connect(function()
		if search.open then search.box.Text = ""; refreshSearch() else search.toggle(true, false) end
	end)
	maid:Give(function() if searchTask and coroutine.status(searchTask) ~= "dead" then task.cancel(searchTask) end end)
	favorites.change = function(id, on)
		if type(id) ~= "string" or id == "" or #id > 1000 then return false end
		on = on == true
		if (favorites.set[id] == true) == on then return false end
		if on then
			if #favorites.list >= 200 then notify("Favorites are full.", "error"); return false end
			favorites.set[id] = true
			table.insert(favorites.list, id)
		else
			favorites.set[id] = nil
			local at = table.find(favorites.list, id)
			if at then table.remove(favorites.list, at) end
		end
		markDirty()
		if search.open then refreshSearch() end
		return true
	end
	search.navigate = function(entry, focused)
		searchGeneration += 1
		local generation = searchGeneration
		search.toggle(false)
		selectPage(entry.page)
		if entry.reveal then entry.reveal() end
		if entry.row then
			if searchTask and coroutine.status(searchTask) ~= "dead" then task.cancel(searchTask) end
			searchTask = task.spawn(function()
				RunService.Heartbeat:Wait()
				RunService.Heartbeat:Wait()
				if maid._dead or generation ~= searchGeneration or current ~= entry.page or not entry.row.Parent then return end
				scrollIntoView(entry.page.scroll, entry.row)
				if focused then focusTo(entry.row) end
			end)
		end
	end
	refreshSearch = function()
		for _, child in ipairs(search.results:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
		local query = string.lower(search.box.Text):match("^%s*(.-)%s*$")
		search.results.Visible = search.open
		if not search.results.Visible then selDirty = true; return end
		local matches = {}
		if query == "" then
			for _, id in ipairs(favorites.list) do
				local found
				for _, entry in ipairs(searchRecords) do
					if entry.favoriteId == id and entry.row and entry.row.Parent and entry.page.frame.Parent then found = entry; break end
				end
				table.insert(matches, { entry = found, id = id })
			end
		else
			for _, entry in ipairs(searchRecords) do
				if (not entry.row or entry.row.Parent) and entry.page.frame.Parent then
					local path = entry.page.category .. " / " .. entry.page.name .. (entry.title and " / " .. entry.title or "")
					local searchable, matched = string.lower(path), true
					for term in query:gmatch("%S+") do
						if not string.find(searchable, term, 1, true) then matched = false; break end
					end
					if matched then table.insert(matches, { entry = entry, id = entry.favoriteId }) end
				end
			end
		end
		if query == "" then
			label({ Name = "FavoritesHeading", Parent = search.results, Text = "Favorites", TextSize = 13, FontFace = Font.new(FONT, W.Medium), TextColor3 = Theme.Text, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 0 })
		end
		if #matches == 0 then
			label({ Name = "NoResults", Parent = search.results, Text = query == "" and "Search for a setting and choose Pin." or "No results", TextSize = 13, TextColor3 = Theme.Muted, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 1 })
		else
			for i, match in ipairs(matches) do
				local entry, id = match.entry, match.id
				local row = new("Frame", { Name = "SearchResultRow", Parent = search.results, Size = UDim2.new(1, 0, 0, 42), BackgroundColor3 = Theme.Panel, BackgroundTransparency = 0.2, BorderSizePixel = 0, LayoutOrder = i }, { corner(2) })
				local button = new("TextButton", { Name = "SearchResult", Parent = row, Text = "", BackgroundTransparency = 1, BorderSizePixel = 0, AutoButtonColor = false, Size = UDim2.new(1, id and -55 or 0, 1, 0) })
				local heading = label({ Name = "Title", Parent = button, Position = UDim2.fromOffset(6, 3), Size = UDim2.new(1, -12, 0, 17), Text = entry and (entry.title or entry.page.name) or "Unavailable setting", TextSize = 13, TextColor3 = entry and Theme.Text or Theme.Muted })
				label({ Name = "Path", Parent = button, Position = UDim2.fromOffset(6, 21), Size = UDim2.new(1, -12, 0, 16), Text = entry and (entry.page.category .. (entry.title and " / " .. entry.page.name or "")) or "Remove or restore its section", TextSize = 11, TextColor3 = Theme.Muted })
				if entry then
					hover(button, function(on) animate(heading, FAST, { TextColor3 = on and Theme.Accent or Theme.Text }) end)
					button.Activated:Connect(function() search.navigate(entry, ownsSelection()) end)
				else
					button.Selectable = false
					noFocus[button] = true
				end
				if id then
					local pinned = favorites.set[id] == true
					local pin = new("TextButton", { Name = "FavoriteAction", Parent = row, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -3, 0.5, 0), Size = UDim2.fromOffset(50, 34), Text = pinned and "Unpin" or "Pin", TextSize = 12, FontFace = Font.new(FONT), TextColor3 = pinned and Theme.Accent or Theme.SubText, BackgroundTransparency = 1, AutoButtonColor = false })
					pin.Activated:Connect(function()
						local focused = ownsSelection()
						favorites.change(id, not pinned)
						if focused and search.open then focusTo(search.box) end
					end)
				end
			end
		end
		-- Include both the Favorites heading and the empty-state message.
		local headingHeight = query == "" and 30 or 0 -- 28px plus the list gap
		local contentHeight = #matches == 0 and 36 or (#matches * 42 + math.max(0, #matches - 1) * 2)
		search.resultHeight = 8 + headingHeight + contentHeight -- vertical padding
		search.resizeResults()
		selDirty = true
	end
	connect(search.box:GetPropertyChangedSignal("Text"), refreshSearch)
	end

	-- Each frame: apply pending Selectable changes; if the focused control just got hidden (page switch, drawer,
	-- fold, collapsed options), move focus somewhere sensible instead of losing it.
	navStep = function()
		if pageMoving and anim:IsReduced() then
			pageGeneration += 1
			pageMoving = false
			for _, p in ipairs(pages) do resetPage(p, p == current) end
		end
		if anim:IsReduced() and anim._running[indicator] then
			anim:Stop(indicator)
			indicatorTarget = nil
		end
		updateIndicator(false)
		if selDirty then
			selDirty = false
			refreshSelectable()
		end
		local sel = GuiService.SelectedObject
		if sel and sel:IsDescendantOf(gui) and not (sel.Selectable and isShown(sel)) then focusTo(focusFallback()) end
	end
	-- Sliders: while one is focused, Left/Right (and D-pad) step its value instead of moving focus. Roblox's GUI
	-- navigation handles the arrow first: with nowhere to go, focus stays and the key handler below steps the value;
	-- if it moved focus off the slider, focus is put straight back and the step applied here. lastNudge stops a
	-- single press from stepping twice.
	local sliderRows = setmetatable({}, { __mode = "k" })
	local NUDGE = { [Enum.KeyCode.Left] = -1, [Enum.KeyCode.DPadLeft] = -1, [Enum.KeyCode.Right] = 1, [Enum.KeyCode.DPadRight] = 1 }
	local lastNudge, prevSel = 0, nil
	local function heldArrow()
		for code, dir in pairs(NUDGE) do
			if UIS:IsKeyDown(code) or UIS:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, code) then return dir end
		end
	end
	connect(GuiService:GetPropertyChangedSignal("SelectedObject"), function()
		local now = GuiService.SelectedObject
		local entry = prevSel and sliderRows[prevSel]
		if entry and now ~= prevSel and prevSel.Parent and prevSel.Selectable then
			local dir = heldArrow()
			if dir then
				local back = prevSel
				task.defer(function() GuiService.SelectedObject = back end)
				if os.clock() - lastNudge > 0.05 then
					lastNudge = os.clock()
					entry.nudge(dir)
				end
				return
			end
		end
		prevSel = now
	end)
	maid:Give(function()
		if ownsSelection() then GuiService.SelectedObject = nil end
	end)

	---------------------------------------------------------------- central input
	-- One drag at a time (window move, resize or slider); tracked by the input that started it.
	local function startDrag(input, move, stop, isResize)
		drag = { input = input, move = move, stop = stop, resize = isResize }
		move(input.Position)
	end
	local function endDrag()
		local d = drag
		drag = nil
		if d and d.stop then d.stop() end
	end
	local ENDED = { [Enum.UserInputState.End] = true, [Enum.UserInputState.Cancel] = true }
	-- True while another live pointer owns the drag. A drag whose input already ended or was cancelled
	-- (its InputEnded never reached us) is dropped here, so it can't block every later gesture.
	local function dragBusy()
		if drag and typeof(drag.input) == "Instance" and ENDED[drag.input.UserInputState] then endDrag() end
		return drag ~= nil
	end
	connect(UIS.InputChanged, function(i)
		if not drag then return end
		-- a touch the OS cancelled (or that ended where we missed it) stops the drag instead of sticking
		if typeof(drag.input) == "Instance" and ENDED[drag.input.UserInputState] then endDrag(); return end
		local touch = drag.input.UserInputType == Enum.UserInputType.Touch
		if (touch and i == drag.input) or (not touch and i.UserInputType == Enum.UserInputType.MouseMovement) then
			drag.move(i.Position)
		end
	end)
	connect(UIS.InputEnded, function(i)
		if drag and (i == drag.input or (i.UserInputType == Enum.UserInputType.MouseButton1 and drag.input.UserInputType == i.UserInputType)) then
			endDrag()
		end
	end)
	-- Hybrid devices: the grip's target follows the input actually being used.
	connect(UIS.LastInputTypeChanged, function(t)
		if t == Enum.UserInputType.Touch or t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.MouseButton1 then
			sizeGripFor(t)
		end
	end)
	connect(UIS.InputBegan, function(i, processed)
		if capturing then
			local kb = capturing
			if i.UserInputType == Enum.UserInputType.Keyboard then
				capturing = nil
				kb.finish(i.KeyCode)
			elseif POINTER[i.UserInputType] then -- clicking anywhere cancels the capture
				capturing = nil
				kb.finish(nil, true)
			end
			return
		end
		-- Back = gamepad B or Backspace (outside a text box), only while this window has focus: close the dropdown,
		-- then the drawer, then hand focus back to the game. Escape belongs to Roblox (it opens the game menu and
		-- clears GUI selection), so it only closes our overlays.
		if i.KeyCode == Enum.KeyCode.Escape then
			if popup then closePopup() elseif search.open then search.toggle(false) elseif drawerOpen then setDrawer(false) end
		elseif (i.KeyCode == Enum.KeyCode.ButtonB or (i.KeyCode == Enum.KeyCode.Backspace and not UIS:GetFocusedTextBox())) and ownsSelection() then
			if popup then
				closePopup()
			elseif search.open then
				search.toggle(false)
			elseif drawerOpen then
				setDrawer(false)
			else
				GuiService.SelectedObject = nil
			end
			return
		end
		local nudge = NUDGE[i.KeyCode] and sliderRows[GuiService.SelectedObject]
		if nudge then
			if os.clock() - lastNudge > 0.05 then
				lastNudge = os.clock()
				nudge.nudge(NUDGE[i.KeyCode])
			end
			return
		end
		-- FocusKey (optional): moves keyboard/gamepad focus into the window, or back out.
		if opts.FocusKey and i.KeyCode == opts.FocusKey and not processed and not UIS:GetFocusedTextBox() then
			if ownsSelection() then GuiService.SelectedObject = nil else focusTo(focusFallback()) end
			return
		end
		if processed or i.UserInputType ~= Enum.UserInputType.Keyboard or UIS:GetFocusedTextBox() then return end
		for _, kb in ipairs(keybinds) do
			if kb.Value == i.KeyCode then fire("keybind", kb.Callback, kb.Value) end
		end
	end)
	connect(root:GetPropertyChangedSignal("AbsoluteSize"), applyLayout)

	topbar.InputBegan:Connect(function(i)
		if not POINTER[i.UserInputType] or dragBusy() then return end
		local start = Vector2.new(i.Position.X, i.Position.Y)
		if inside(control, start) or inside(nav, start) then return end
		-- desktop: double-click the header to fold; touch uses the fold button
		if i.UserInputType == Enum.UserInputType.MouseButton1 then
			local now = os.clock()
			if now - lastClick < 0.3 then
				lastClick = 0
				setFolded(not minimized)
				return
			end
			lastClick = now
		end
		if locked then return end
		local origin = pos
		startDrag(i, function(p)
			local delta = Vector2.new(p.X, p.Y) - start
			if delta.Magnitude > 4 then lastClick = 0 end -- a drag is not half of a double-click
			setPos(snap(origin + delta))
		end, function()
			wantPos = pos -- a drag is the user choosing a spot
			markDirty()
		end)
	end)
	-- Resize keeps the top-left corner fixed, so it never moves a position-locked window.
	grip.InputBegan:Connect(function(i)
		if not POINTER[i.UserInputType] or dragBusy() or minimized or sizeLocked then return end
		closePopup()
		local start, from = Vector2.new(i.Position.X, i.Position.Y), size
		local before = manualSize -- the preference this gesture may change
		startDrag(i, function(p)
			local vs = root.AbsoluteSize
			local want = from + (Vector2.new(p.X, p.Y) - start) / scale -- pointer moves in screen px, sizes are logical
			manualSize = Vector2.new(math.min(want.X, (vs.X - pos.X) / scale), math.min(want.Y, (vs.Y - pos.Y) / scale)) -- not past the screen edge
			computeSize()
			paintFold()
			layoutChrome(true) -- navigation may collapse/expand as the window crosses a threshold
			setPos(pos)
		end, function()
			-- Remember what was applied, but only on axes the gesture really changed: on a narrow screen
			-- a height-only resize must not replace the preferred width with the clamped one.
			local pref = before or Vector2.new(800, 500)
			local changedX, changedY = size.X ~= from.X, size.Y ~= from.Y
			if changedX or changedY then
				manualSize = Vector2.new(changedX and size.X or pref.X, changedY and size.Y or pref.Y)
			else
				manualSize = before
			end
			computeSize()
			paintFold()
			markDirty()
		end, true)
	end)
	nav.Activated:Connect(function() setDrawer(not drawerOpen) end)
	backdrop.Activated:Connect(function() setDrawer(false) end)
	connect(window:GetPropertyChangedSignal("AbsoluteSize"), function() headerDirty = true end)
	minimizeBtn.Activated:Connect(function() setFolded(not minimized) end)
	closeBtn.Activated:Connect(function() maid:Clean() end)

	-- Dropdown list lives on the root so the page scroll can't clip it; flips up and clamps to the screen.
	-- isSelected(v) decides highlight; pick(v) returns true to keep the list open (multi-select).
	local function openList(anchor, options, isSelected, pick, searchable)
		closePopup()
		local searchHeight = searchable and 36 or 0
		local function placement()
			local vs, off = root.AbsoluteSize, root.AbsolutePosition
			local ap, as = anchor.AbsolutePosition - off, anchor.AbsoluteSize
			local w = math.min(math.max(as.X, 140), math.max(1, vs.X - 8))
			local h = math.max(1, math.min(math.max(1, #options) * 28 + 2 + searchHeight, 7 * 28 + 2 + searchHeight, vs.Y - 8))
			local x = math.clamp(ap.X + as.X - w, 4, math.max(4, vs.X - w - 4))
			local y = ap.Y + as.Y + 4
			if y + h > vs.Y - 4 then y = math.max(4, ap.Y - h - 4) end
			return x, y, w, h
		end
		local x, y, w, h = placement()
		popup = new("TextButton", { Name = "Popup", Parent = root, Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 50, AutoButtonColor = false })
		local overlay = popup
		popup.Activated:Connect(closePopup)
		noFocus[popup], popup.Selectable = true, false
		local focused = ownsSelection() and GuiService.SelectedObject
		local menu = new("Frame", {
			Name = "DropdownMenu", Parent = popup, Position = UDim2.fromOffset(x, y + 6), Size = UDim2.fromOffset(w, h),
			BackgroundColor3 = Theme.Background, BackgroundTransparency = 1, BorderSizePixel = 0, ClipsDescendants = true,
		}, { corner(3), stroke() })
		menu.SelectionGroup = true
		menu.SelectionBehaviorUp, menu.SelectionBehaviorDown = Enum.SelectionBehavior.Stop, Enum.SelectionBehavior.Stop
		menu.SelectionBehaviorLeft, menu.SelectionBehaviorRight = Enum.SelectionBehavior.Stop, Enum.SelectionBehavior.Stop
		local searchBox
		if searchable then
			searchBox = new("TextBox", {
				Name = "DropdownSearch", Parent = menu, Position = UDim2.fromOffset(6, 4), Size = UDim2.new(1, -12, 0, 28),
				Text = "", PlaceholderText = "Search...", PlaceholderColor3 = Theme.Muted, TextColor3 = Theme.Text,
				TextSize = 14, FontFace = Font.new(FONT), TextXAlignment = Enum.TextXAlignment.Left,
				ClearTextOnFocus = false, BackgroundColor3 = Theme.Panel, BorderSizePixel = 0,
			}, { corner(3), padding(9, 9) })
		end
		local list = new("ScrollingFrame", {
			Name = "DropdownList", Parent = menu, Position = UDim2.fromOffset(0, searchHeight), Size = UDim2.new(1, 0, 1, -searchHeight),
			BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = Theme.Scrollbar,
			CanvasSize = UDim2.new(), AutomaticCanvasSize = AUTO_Y, ScrollingDirection = Enum.ScrollingDirection.Y,
		}, { vlist(0), padding(0, 0, 1, 1) })
		local items, firstItem, selectedItem = {}, nil, nil
		local empty = label({ Name = "NoResults", Parent = list, Text = "No results", TextSize = 14, TextColor3 = Theme.Muted,
			Size = UDim2.new(1, 0, 0, 28), LayoutOrder = #options * 2 + 1, Visible = false })
		padding(10, 10).Parent = empty
		local function paint()
			local query = searchBox and string.lower(searchBox.Text) or ""
			local visible = 0
			for _, entry in ipairs(items) do
				local selected = isSelected(entry.value)
				entry.item.TextColor3 = selected and Theme.Accent or Theme.SubText
				entry.item.LayoutOrder = entry.index + (searchable and not selected and #options or 0)
				entry.item.Visible = query == "" or string.find(string.lower(tostring(entry.value)), query, 1, true) ~= nil
				if entry.item.Visible then visible += 1 end
			end
			empty.Visible = searchable and visible == 0
			selDirty = true
		end
		for i, v in ipairs(options) do
			local item = new("TextButton", {
				Parent = list, Text = tostring(v), TextSize = 14, FontFace = Font.new(FONT),
				TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
				BackgroundColor3 = Theme.Panel, BackgroundTransparency = 1, AutoButtonColor = false,
				Size = UDim2.new(1, 0, 0, 28), LayoutOrder = i,
			}, { padding(10, 10) })
			table.insert(items, { value = v, item = item, index = i })
			firstItem = firstItem or item
			if isSelected(v) then selectedItem = selectedItem or item end
			hover(item, function(on) animate(item, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = on and 0 or 1 }) end)
			item.Activated:Connect(function()
				if pick(v) then paint() else closePopup() end
			end)
		end
		paint()
		if searchBox then searchBox:GetPropertyChangedSignal("Text"):Connect(function() list.CanvasPosition = Vector2.zero; paint() end) end
		animate(menu, TweenInfo.new(0.18, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(x, y), BackgroundTransparency = 0 })
		local clip = anchor:FindFirstAncestorOfClass("ScrollingFrame")
		local function follow()
			if popup ~= overlay or not overlay.Parent then return end
			local shown = anchor.Parent ~= nil
			local o = anchor
			while shown and o and o ~= root do
				if o:IsA("GuiObject") and not o.Visible then shown = false end
				o = o.Parent
			end
			if shown and clip then
				local cy, ay = clip.AbsolutePosition.Y, anchor.AbsolutePosition.Y + anchor.AbsoluteSize.Y / 2
				shown = ay >= cy and ay <= cy + clip.AbsoluteSize.Y
			end
			if not shown then return closePopup() end
			local nx, ny, nw, nh = placement()
			anim:Stop(menu, { "Position" })
			menu.Position, menu.Size = UDim2.fromOffset(nx, ny), UDim2.fromOffset(nw, nh)
		end
		local conns = {
			anchor:GetPropertyChangedSignal("AbsolutePosition"):Connect(follow),
			anchor:GetPropertyChangedSignal("AbsoluteSize"):Connect(follow),
			root:GetPropertyChangedSignal("AbsoluteSize"):Connect(follow),
		}
		popup.Destroying:Connect(function()
			anim:Stop(menu)
			for _, entry in ipairs(items) do anim:Stop(entry.item) end
			for _, c in ipairs(conns) do c:Disconnect() end
		end)
		if focused then
			popupReturn = focused
			focusTo(selectedItem or firstItem or searchBox)
		end
	end

	---------------------------------------------------------------- component registry (SaveManager values)
	-- encode() -> JSON-safe value; decode(raw) -> {value} when valid, nil otherwise (stored data is untrusted).
	-- Deferred restore: callbacks for restored values run once the building script yields, in registration
	-- order (a toggle before its own options), each isolated; a key the user changed first is skipped.
	local function runRestore()
		restoreScheduled = false
		local queue = restoreQueue
		restoreQueue = {}
		for _, k in ipairs(queue) do
			if restorePending[k] and components[k] and not maid._dead then
				restorePending[k] = nil
				local ok, err = pcall(components[k].c._notify)
				if not ok then warn("[Ethos] restore of " .. k .. " failed: " .. tostring(err)) end
			end
		end
	end
	local function userChanged(k) restorePending[k] = nil end
	local function register(key, c, default, encode, decode)
		local k, n = key, 1
		while components[k] do
			n += 1
			k = key .. "#" .. n
		end
		components[k] = { c = c, default = default, encode = encode, decode = decode }
		table.insert(componentOrder, k)
		local raw = prof.Values[k]
		if raw ~= nil then
			local ok, box = pcall(decode, raw)
			if ok and box then
				local atDefault = HttpService:JSONEncode({ encode() })
				local applied, err = pcall(c._apply, box[1])
				if not applied then
					warn("[Ethos] restore of " .. k .. " failed: " .. tostring(err))
				elseif restoreMode == "Immediate" then
					pcall(c._notify)
				elseif restoreMode == "Deferred" and HttpService:JSONEncode({ encode() }) ~= atDefault then
					-- a value equal to the default gets no callback, same as a freshly created component
					restorePending[k] = true
					table.insert(restoreQueue, k)
					if not restoreScheduled then
						restoreScheduled = true
						task.defer(runRestore)
					end
				end
			end
		end
		return k
	end

	---------------------------------------------------------------- sections and components
	-- Builds the component API on an elements frame. Used for page sections and for toggle option panels.
	-- pathPrefix keys components without an Id; idPrefix namespaces ids (nested options: "ToggleId.").
	-- owned collects what this section registers (keys, keybinds, option panels) so Section:Destroy can undo it.
	-- stops: this section's focus stops in visual order (nested lists for option panels), linked by refreshSelectable.
	-- page: the page this belongs to, so a style switch animates only what is on screen.
	local function makeSection(elements, scroll, pathPrefix, idPrefix, owned, stops, page, sectionName, reveal)
		local function keyOf(o) return o.Id and (idPrefix .. o.Id) or (pathPrefix .. (o.Title ~= nil and o.Title ~= "" and o.Title or "?")) end
		local function track(o, c, default, encode, decode, rowFrame)
			local original = type(default) == "table" and table.clone(default) or default
			function c:Reset()
				local value = c.Value
				local same = type(value) == "table" and type(original) == "table" and HttpService:JSONEncode(value) == HttpService:JSONEncode(original) or (type(value) ~= "table" and value == original)
				if same then return false end
				c:Set(type(original) == "table" and table.clone(original) or original)
				return true
			end
			local k
			if o.Save == false then
				k = keyOf(o)
			else
				k = register(keyOf(o), c, default, encode, decode)
				table.insert(owned.keys, k)
			end
			local identity = o.Save == false and HttpService:JSONEncode({ "unsaved", page.key, sectionName, k }) or HttpService:JSONEncode({ "saved", k })
			local entry
			for _, item in ipairs(owned.search) do if item.row == rowFrame then entry = item; break end end
			if entry then
				local base, suffix = identity, 1
				local function inUse(id)
					for _, item in ipairs(searchRecords) do if item ~= entry and item.favoriteId == id then return true end end
				end
				while inUse(identity) do suffix += 1; identity = base .. "#" .. suffix end
				entry.favoriteId = identity
				function c:GetFavoriteId() return identity end
				function c:IsFavorite() return favorites.set[identity] == true end
				function c:SetFavorite(v) return favorites.change(identity, v == true) end
				if refreshSearch and search.open then refreshSearch() end
			end
			return k
		end
		-- SmartRowLayout: each wide control makes its own decision from measured text,
		-- available logical width and its control constraints. Width changes are coalesced.
		local wideRows, descriptionRows, rowCheckQueued = {}, {}, false
		local function applyStack(r)
			local t, width = style, math.floor(px(r.f.AbsoluteSize.X) + 0.5)
			if width <= 0 then return end
			local minControl = num(r.options.ControlMinWidth) and math.max(32, r.options.ControlMinWidth) or (t.FieldInset * 2 + t.FieldTextSize * 6)
			if UIS.TouchEnabled then minControl = math.max(minControl, 100) end
			local maxControl = num(r.options.ControlMaxWidth) and math.max(minControl, r.options.ControlMaxWidth) or math.max(minControl, t.FieldMaxWidth)
			local measureKey = tostring(t.TitleSize) .. ":" .. tostring(t.DescriptionSize)
			if r.measureKey ~= measureKey then
				r.measureKey = measureKey
				local titleWidth = textWidth(r.options.Title or "", t.TitleSize, r.title.FontFace)
				local wordWidth = 0
				for word in string.gmatch(r.options.Description or "", "%S+") do
					wordWidth = math.max(wordWidth, textWidth(word, t.DescriptionSize, r.title.FontFace))
				end
				r.textMin = math.max(t.TitleSize * 5, math.min(180, titleWidth), math.min(140, wordWidth))
			end
			local requested = r.options.RowLayout
			local requiredText = requested == "Inline" and t.TitleSize * 5 or r.textMin
			local fits = width >= minControl + t.RowGap + requiredText
			local stacked = requested == "Stacked" or requested == "FullWidth" or not fits
			local valueKey = tostring(r.valueText or "") .. ":" .. tostring(t.FieldTextSize)
			if r.valueKey ~= valueKey then
				r.valueKey = valueKey
				r.valueWidth = textWidth(r.valueText or "", t.FieldTextSize, r.title.FontFace) + t.FieldInset * 2 + 14
			end
			local preferred = math.clamp(math.max(math.floor(width * t.FieldWidthScale + 0.5), r.valueWidth), minControl, maxControl)
			local fieldWidth = stacked and math.min(width, num(r.options.ControlMaxWidth) and maxControl or width)
				or math.min(preferred, width - t.RowGap - requiredText)
			fieldWidth = math.max(0, math.floor(fieldWidth + 0.5))
			anim:Stop(r.right, { "Size" })
			anim:Stop(r.limit, { "MaxSize" })
			anim:Stop(r.list, { "Padding" })
			r.list.FillDirection = stacked and Enum.FillDirection.Vertical or HORIZONTAL
			r.flex.FlexMode = stacked and Enum.UIFlexMode.None or Enum.UIFlexMode.Fill
			r.group.Size = stacked and UDim2.new(1, 0, 0, 0) or UDim2.new(0, 0, 0, 0)
			r.list.Padding = UDim.new(0, stacked and t.StackGap or t.RowGap)
			r.right.Size = UDim2.fromOffset(fieldWidth, t.FieldHeight)
			r.limit.MaxSize = Vector2.new(math.max(fieldWidth, 1), t.FieldHeight)
		end
		local function checkStack()
			if rowCheckQueued then return end
			rowCheckQueued = true
			task.defer(function()
				rowCheckQueued = false
				if not elements.Parent or not page.frame.Visible then return end
				for _, r in ipairs(wideRows) do if r.f.Parent then applyStack(r) end end
				for _, r in ipairs(descriptionRows) do if r.view.Parent then r.update(false) end end
			end)
		end
		elements:GetPropertyChangedSignal("AbsoluteSize"):Connect(checkStack)
		local pageVisibility = page.frame:GetPropertyChangedSignal("Visible"):Connect(checkStack)
		elements.Destroying:Connect(function() pageVisibility:Disconnect() end)

		-- Title + wrapping description on the left, controls on the right; the whole row is the tap target.
		local function row(o, parent)
			local f = new("TextButton", {
				Name = o.Title or "Row", Parent = parent or elements, Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, LayoutOrder = nextOrder(),
			}, { hlist(0, nil, Enum.VerticalAlignment.Top) })
			table.insert(stops, f)
			local entry = { page = page, row = f, title = o.Title or "", reveal = reveal, section = sectionName }
			table.insert(searchRecords, entry)
			table.insert(owned.search, entry)
			local groupList = vlist(5)
			local group = new("Frame", { Name = "TextGroup", Parent = f, Size = UDim2.new(0, 0, 0, 0), AutomaticSize = AUTO_Y, BackgroundTransparency = 1, LayoutOrder = 1 }, {
				new("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }), groupList,
			})
			local title = label({ Name = "Title", Parent = group, Text = o.Title or "", TextSize = 14, FontFace = Font.new(FONT, W.Medium), TextColor3 = Theme.SubText, TextWrapped = true, TextTruncate = Enum.TextTruncate.None, TextYAlignment = Enum.TextYAlignment.Top, AutomaticSize = AUTO_Y, Size = UDim2.new(1, 0, 0, 16) })
			local desc, description
			if type(o.Description) == "string" and o.Description ~= "" then
				local view = new("Frame", { Name = "DescriptionView", Parent = group, BackgroundTransparency = 1,
					Size = UDim2.new(1, 0, 0, 0), ClipsDescendants = true, LayoutOrder = 1 })
				desc = label({
					Name = "Description", Parent = view, Text = o.Description, TextSize = 14, LineHeight = 1.07, TextColor3 = Theme.Muted,
					TextWrapped = true, TextTruncate = Enum.TextTruncate.None, TextYAlignment = Enum.TextYAlignment.Top,
					Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y,
				})
				local more = new("TextButton", { Name = "DescriptionDisclosure", Parent = group, Text = "Show more",
					TextSize = 13, FontFace = Font.new(FONT, W.Medium), TextColor3 = Theme.Accent,
					TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, AutoButtonColor = false,
					Size = UDim2.new(1, 0, 0, UIS.TouchEnabled and 36 or 22), LayoutOrder = 2, Visible = false })
				table.insert(stops, more)
				local mode = o.DescriptionMode or opts.DescriptionMode or "Auto"
				if mode ~= "Auto" and mode ~= "Short" and mode ~= "Full" then mode = "Auto" end
				local maxLines = num(o.DescriptionMaxLines) and o.DescriptionMaxLines or (num(opts.DescriptionMaxLines) and opts.DescriptionMaxLines or 2)
				maxLines = math.clamp(math.floor(maxLines), 1, 20)
				local expanded, targetHeight, lineKey, lineHeight = false, nil, nil, nil
				description = { view = view }
				function description.update(animateChange)
					if not view.Parent or view.AbsoluteSize.X <= 0 then return end
					local fullHeight = math.max(0, math.ceil(px(desc.TextBounds.Y)))
					if fullHeight <= 0 then return end
					local key = tostring(style.DescriptionSize) .. ":" .. tostring(style.DescriptionLineHeight)
					if key ~= lineKey then
						lineKey = key
						textWidth("Ag", style.DescriptionSize, desc.FontFace)
						lineHeight = math.max(1, math.ceil(measurer.TextBounds.Y * style.DescriptionLineHeight))
					end
					local limit = lineHeight * maxLines
					local constrained = px(view.AbsoluteSize.X) < 240
					local overflow = fullHeight > limit + 1 and (mode == "Short" or (mode == "Auto" and constrained))
					local height = overflow and not expanded and math.min(fullHeight, limit) or fullHeight
					if more.Visible ~= overflow then
						local returnFocus = not overflow and GuiService.SelectedObject == more
						more.Visible = overflow
						selDirty = true
						if returnFocus then focusTo(f) end
					end
					more.Text = expanded and "Show less" or "Show more"
					if targetHeight == height then return end
					targetHeight = height
					if animateChange and page == current and layoutReady then
						animate(view, TweenInfo.new(0.22, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out), { Size = UDim2.new(1, 0, 0, height) })
					else
						anim:Stop(view, { "Size" })
						view.Size = UDim2.new(1, 0, 0, height)
					end
				end
				table.insert(descriptionRows, description)
				desc:GetPropertyChangedSignal("TextBounds"):Connect(checkStack)
				view:GetPropertyChangedSignal("AbsoluteSize"):Connect(checkStack)
				view.Destroying:Connect(function() anim:Stop(view) end)
				more.Destroying:Connect(function() anim:Stop(more) end)
				more.Activated:Connect(function() expanded = not expanded; description.update(true) end)
				hover(more, function(on) animate(more, FAST, { TextColor3 = on and Theme.Text or Theme.Accent }) end)
			end
			-- at least 82px wide so descriptions wrap where the reference wraps, gear or not
			local right = new("Frame", { Name = "Right", Parent = f, BackgroundTransparency = 1, Size = UDim2.fromOffset(82, 28), AutomaticSize = AUTO_X, LayoutOrder = 2 }, {
				hlist(2, Enum.HorizontalAlignment.Right),
			})
			local info = { f = f, right = right, title = title, options = o }
			bindStyle(page, f, function(t)
				title.TextSize = t.TitleSize -- text sizes switch instantly (tweening them jitters); geometry tweens
				sty(title, { Size = UDim2.new(1, 0, 0, t.TitleHeight) })
				if desc then desc.TextSize, desc.LineHeight = t.DescriptionSize, t.DescriptionLineHeight; checkStack() end
				sty(groupList, { Padding = UDim.new(0, t.DescriptionSpacing) })
				sty(f, { Size = UDim2.new(1, 0, 0, rowMin(t)) })
				if info.wide then
					applyStack(info.wide)
				else
					sty(right, { Size = UDim2.fromOffset(t.ControlMinWidth, t.ControlRowHeight) })
				end
			end)
			return f, title, right, info
		end
		local function fieldCorner(box)
			bindStyle(page, box, function(t) sty(box:FindFirstChildOfClass("UICorner"), { CornerRadius = UDim.new(0, t.ControlCorner) }) end)
			return box
		end
		-- Dropdown/input column: 45% of the row, at most 202px like the reference (full width when stacked).
		local function wideRight(info)
			local f, right = info.f, info.right
			right.AutomaticSize = AUTO_NONE
			local limit = new("UISizeConstraint", { Parent = right, MaxSize = Vector2.new(style.FieldMaxWidth, style.FieldHeight) })
			local group = f:FindFirstChild("TextGroup")
			local r = { f = f, title = info.title, options = info.options, list = f:FindFirstChildOfClass("UIListLayout"), group = group, flex = group:FindFirstChildOfClass("UIFlexItem"), right = right, limit = limit }
			info.wide = r
			table.insert(wideRows, r)
			f:GetPropertyChangedSignal("AbsoluteSize"):Connect(checkStack)
			applyStack(r)
			checkStack()
			return fieldCorner(field({ Name = "Box", Parent = right, Size = UDim2.fromScale(1, 1) }))
		end
		local function textBox(parent, props)
			props.Parent, props.Size, props.BackgroundTransparency = parent, UDim2.fromScale(1, 1), 1
			props.TextSize, props.FontFace, props.TextColor3, props.ClearTextOnFocus = 14, Font.new(FONT), Theme.Text, false
			props.PlaceholderColor3 = Theme.Muted
			local tb = new("TextBox", props)
			bindStyle(page, tb, function(t) tb.TextSize = t.FieldTextSize end)
			return tb
		end

		local Section = {}
		function Section:AddButton(a, b)
			local o = args(a, b)
			local btnFrame = new("TextButton", {
				Name = "Button", Parent = elements, Text = o.Title or "Button", TextSize = 14, FontFace = Font.new(FONT, W.Medium),
				TextColor3 = Theme.SubText, BackgroundColor3 = Theme.Background, AutoButtonColor = false,
				Size = UDim2.new(1, 0, 0, 32), LayoutOrder = nextOrder(),
			}, { corner(3) })
			table.insert(stops, btnFrame)
			local s = stroke()
			s.Parent = btnFrame
			bindStyle(page, btnFrame, function(t)
				btnFrame.TextSize = t.ButtonTextSize
				sty(btnFrame, { Size = UDim2.new(1, 0, 0, UIS.TouchEnabled and math.max(32, t.ControlHeight) or t.ControlHeight) }) -- never shrink touch targets
				sty(btnFrame:FindFirstChildOfClass("UICorner"), { CornerRadius = UDim.new(0, t.ControlCorner) })
			end)
			local btn = {}
			hover(btnFrame, function(on)
				local h = on and not btn.Disabled
				s.Color, btnFrame.TextColor3 = h and Theme.Hover or Theme.Border, h and Theme.Text or Theme.SubText
			end)
			btnFrame.InputBegan:Connect(function(i)
				if POINTER[i.UserInputType] and not btn.Disabled then
					btnFrame.BackgroundColor3 = Theme.Border
					animate(btnFrame, TweenInfo.new(0.25), { BackgroundColor3 = Theme.Background })
				end
			end)
			-- Confirm = true: the first press arms the button for 3s ("Click again to confirm"), the second runs it.
			local armedUntil = 0
			local function disarm()
				armedUntil = 0
				btnFrame.Text = o.Title or "Button"
				animate(btnFrame, FAST, { TextColor3 = Theme.SubText })
			end
			btnFrame.Activated:Connect(function()
				if btn.Disabled then return end
				if o.Confirm then
					if os.clock() > armedUntil then
						armedUntil = os.clock() + 3
						btnFrame.Text = o.ConfirmText or "Click again to confirm"
						animate(btnFrame, FAST, { TextColor3 = Theme.Warn })
						task.delay(3, function()
							if armedUntil ~= 0 and os.clock() >= armedUntil and btnFrame.Parent then disarm() end
						end)
						return
					end
					disarm()
				end
				fire(o.Title or "button", o.Callback)
			end)
			function btn:SetDisabled(d)
				btn.Disabled = d and true or false
				btnFrame.TextTransparency = btn.Disabled and 0.5 or 0
				s.Transparency = btn.Disabled and 0.5 or 0
			end
			btn:SetDisabled(o.Disabled)
			return btn
		end

		-- Gear: Settings = function() and/or Toggle:AddOptions() (an inline panel that slides open under the row).
		function Section:AddToggle(a, b)
			local o = args(a, b)
			local f, title, right = row(o)
			-- Center the checkbox and optional gear alongside the complete text block.
			f:FindFirstChildOfClass("UIListLayout").VerticalAlignment = CENTER_Y
			local optionsOrder = nextOrder() -- reserved directly under the row for the options panel
			local gear, gearIcon
			local t = { Value = false }
			local function ensureGear()
				if gear then return end
				gear = new("TextButton", { Name = "Settings", Parent = right, Text = "", BackgroundTransparency = 1, Size = UDim2.fromOffset(24, 24) })
				gearIcon = iconImage({ Parent = gear, Image = ICON.gear, ImageRectOffset = GEAR_RECT[1], ImageRectSize = GEAR_RECT[2], ImageColor3 = Theme.Muted, Size = UDim2.fromOffset(14, 14) })
				hover(gear, function(on) animate(gearIcon, FAST, { ImageColor3 = on and Theme.Text or Theme.Muted }) end)
				gear.Activated:Connect(function()
					if t.Options then t.Options:Toggle() end
					fire("settings", o.Settings)
				end)
			end
			if o.Settings then ensureGear() end
			local holder = new("Frame", { Name = "Checkbox", Parent = right, BackgroundTransparency = 1, Size = UDim2.fromOffset(28, 28), LayoutOrder = 1 })
			-- checked look: accent fill, 2px gap, darker accent ring
			local ring = new("Frame", { Name = "Ring", Parent = holder, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(24, 24), BackgroundTransparency = 1, Visible = false }, {
				corner(4), stroke(Theme.AccentRing, 2),
			})
			local box = new("Frame", { Name = "Box", Parent = holder, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(20, 20), BackgroundColor3 = Theme.Background, BorderSizePixel = 0 }, { corner(2) })
			local border = stroke()
			border.Parent = box
			local icon = iconImage({ Parent = box, Image = ICON.check, ImageColor3 = Theme.OnAccent, Size = UDim2.fromOffset(18, 18), Visible = false })
			local function apply(v)
				t.Value = v
				animate(box, FAST, { BackgroundColor3 = v and Theme.Accent or Theme.Background })
				border.Color = v and Theme.Accent or Theme.Border
				ring.Visible, icon.Visible = v and style.CheckRing, v -- the outer ring is a Modern detail
				title.TextColor3 = v and Theme.Text or Theme.SubText
			end
			bindStyle(page, holder, function(tk)
				sty(holder, { Size = UDim2.fromOffset(tk.CheckHolder, tk.CheckHolder) })
				sty(box, { Size = UDim2.fromOffset(tk.CheckSize, tk.CheckSize) })
				sty(box:FindFirstChildOfClass("UICorner"), { CornerRadius = UDim.new(0, tk.CheckCorner) })
				ring.Visible = t.Value and tk.CheckRing
			end)
			local key
			-- _apply: value + visuals only (restores). _notify: run the callback with the current value.
			function t._apply(v) apply(not not v) end
			function t._notify() fire(key or o.Title or "toggle", o.Callback, t.Value) end
			function t:Set(v)
				apply(not not v)
				if key then userChanged(key) end
				t._notify()
				markDirty()
			end
			f.Activated:Connect(function() t:Set(not t.Value) end)
			apply(o.Default == true)
			key = track(o, t, o.Default == true, function() return t.Value end, function(v)
				if type(v) == "boolean" then return { v } end
			end, f)

			-- Returns the toggle's options panel: same component API as a section, values saved under "<key>.<id>".
			function t:AddOptions()
				if t.Options then return t.Options end
				ensureGear()
				local panel = new("Frame", { Name = "Options", Parent = elements, Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, ClipsDescendants = true, Visible = false, LayoutOrder = optionsOrder }, {
					padding(1, 1, 1, 1), -- room for the inner stroke inside the clip
				})
				local innerList, innerPad = vlist(10), padding(12, 12, 10, 10)
				local inner = new("Frame", { Name = "Inner", Parent = panel, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, BackgroundColor3 = Theme.Background, BorderSizePixel = 0 }, {
					corner(3), stroke(), innerList, innerPad,
				})
				bindStyle(page, inner, function(tk)
					local op = tk.OptionsPad
					sty(innerPad, { PaddingLeft = UDim.new(0, op[1]), PaddingRight = UDim.new(0, op[2]), PaddingTop = UDim.new(0, op[3]), PaddingBottom = UDim.new(0, op[4]) })
					sty(innerList, { Padding = UDim.new(0, tk.OptionsGap) })
					sty(inner:FindFirstChildOfClass("UICorner"), { CornerRadius = UDim.new(0, tk.ControlCorner) })
				end)
				local sub = {} -- the panel's stops, spliced in right after this toggle's row
				table.insert(stops, (table.find(stops, f) or #stops) + 1, sub)
				local Options
				Options = makeSection(inner, scroll, key .. ".", key .. ".", owned, sub, page, sectionName, function()
					if reveal then reveal() end
					if not Options:IsOpen() then Options:SetOpen(true, true) end
				end)
				local open = false
				-- Height tweens to the measured content, then hands back to AutomaticSize so later reflows stay correct.
				function Options:SetOpen(v, instant)
					open = v and true or false
					selDirty = true
					if rememberOptions then markDirty() end
					if instant then
						anim:Stop(panel, { "Size" })
						anim:Stop(gearIcon, { "Rotation" })
						gearIcon.Rotation = open and 90 or 0
						panel.Size, panel.AutomaticSize, panel.Visible = UDim2.new(1, 0, 0, 0), open and AUTO_Y or AUTO_NONE, open
						return
					end
					animate(gearIcon, FOLD, { Rotation = open and 90 or 0 })
					local h = math.round(px(panel.AbsoluteSize.Y))
					panel.AutomaticSize = AUTO_NONE
					panel.Size = UDim2.new(1, 0, 0, panel.Visible and h or 0)
					if open then
						panel.Visible = true
						animate(panel, FOLD, { Size = UDim2.new(1, 0, 0, math.round(px(inner.AbsoluteSize.Y)) + 2) }, function()
							if open then panel.Size, panel.AutomaticSize = UDim2.new(1, 0, 0, 0), AUTO_Y end
						end)
					else
						animate(panel, FOLD, { Size = UDim2.new(1, 0, 0, 0) }, function()
							if not open then panel.Visible = false; selDirty = true end
						end)
					end
				end
				function Options:Toggle() Options:SetOpen(not open) end
				function Options:IsOpen() return open end
				t.Options = Options
				local panelEntry = { key = key, Options = Options }
				table.insert(optionPanels, panelEntry)
				table.insert(owned.panels, panelEntry)
				if savedExpanded(key) then Options:SetOpen(true, true) end
				return Options
			end
			return t
		end

		-- Multi = true: Value is a list, the menu stays open and toggles items.
		function Section:AddDropdown(a, b)
			local o = args(a, b)
			local options = o.Options or {}
			local f, _, _, info = row(o)
			local box = wideRight(info)
			local text = label({ Parent = box, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -34, 1, 0), TextSize = 14, TextColor3 = Theme.SubText })
			local arrowIcon = iconImage({ Parent = box, Image = ICON.updown, ImageColor3 = Theme.SubText, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(12, 12) })
			bindStyle(page, text, function(tk)
				text.TextSize = tk.FieldTextSize
				sty(text, { Position = UDim2.fromOffset(tk.FieldInset, 0), Size = UDim2.new(1, -(tk.FieldInset * 2 + 14), 1, 0) })
				sty(arrowIcon, { Position = UDim2.new(1, -tk.FieldInset, 0.5, 0) })
			end)
			local d = {}
			local function show()
				local shown = d.Value
				if o.Multi then
					local picked = {}
					for _, v in ipairs(options) do
						if table.find(d.Value, v) then table.insert(picked, tostring(v)) end
					end
					shown = #picked > 0 and table.concat(picked, ", ") or nil
				end
				text.Text = shown ~= nil and tostring(shown) or "--"
				text.TextColor3 = shown ~= nil and Theme.Text or Theme.Muted
				if info.wide then info.wide.valueText = text.Text; checkStack() end
			end
			local key
			function d._apply(v)
				d.Value = o.Multi and table.clone(v or {}) or v
				show()
			end
			function d._notify() fire(key or o.Title or "dropdown", o.Callback, d.Value) end
			function d:Set(v)
				d._apply(v)
				if key then userChanged(key) end
				d._notify()
				markDirty()
			end
			function d:SetOptions(list)
				options = list
				show()
			end
			local function isSelected(v)
				return o.Multi and table.find(d.Value, v) ~= nil or (not o.Multi and d.Value == v)
			end
			local function pick(v)
				if not o.Multi then d:Set(v); return false end
				local list, at = table.clone(d.Value), table.find(d.Value, v)
				if at then table.remove(list, at) else table.insert(list, v) end
				d:Set(list)
				return true
			end
			f.Activated:Connect(function() openList(box, options, isSelected, pick, true) end)
			d.Value = o.Multi and table.clone(o.Default or {}) or o.Default
			show()
			key = track(o, d, d.Value, function()
				if o.Multi then return table.clone(d.Value) end
				if d.Value == nil then return false end -- false stands for "nothing selected" (JSON drops nil)
				return d.Value
			end, function(v)
				if o.Multi then
					if type(v) ~= "table" then return nil end
					local list = {}
					for _, item in ipairs(v) do
						if table.find(options, item) then table.insert(list, item) end
					end
					return { list }
				end
				if v == false then return { nil } end
				if table.find(options, v) then return { v } end
			end, f)
			return d
		end

		function Section:AddSlider(a, b)
			local o = args(a, b)
			local min, max, step = o.Min or 0, o.Max or 100, o.Step or 1
			assert(step > 0 and max >= min, "Slider: need Step > 0 and Max >= Min")
			local holderList = vlist(10)
			local holder = new("Frame", { Name = o.Title or "Slider", Parent = elements, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, LayoutOrder = nextOrder() }, { holderList })
			local sliderRow, _, right = row(o, holder)
			local valueBox = fieldCorner(field({ Name = "Value", Parent = right, Size = UDim2.fromOffset(36, 26) }))
			local input = textBox(valueBox, { Text = "" })
			noFocus[input] = true -- the row is the focus stop; Left/Right adjust it
			local refit = autoWidth(valueBox, input, function() return style.ValueMinWidth end, 80)
			local bar = new("Frame", { Name = "SliderBar", Parent = holder, Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = Theme.Background, BorderSizePixel = 0, LayoutOrder = nextOrder() }, { corner(3), stroke() })
			bindStyle(page, holder, function(tk)
				sty(holderList, { Padding = UDim.new(0, tk.SliderGap) })
				sty(bar, { Size = UDim2.new(1, 0, 0, tk.SliderTrack) })
				valueBox.Size = UDim2.fromOffset(valueBox.Size.X.Offset, tk.ValueHeight)
				refit()
			end)
			local fill = new("Frame", { Name = "Fill", Parent = bar, Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0 }, { corner(3) })
			-- Taller invisible grab area for touch; the drawn track stays 6px.
			local grab = new("Frame", { Name = "Hit", Parent = bar, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, Active = true })
			local s = {}
			local function apply(v)
				v = math.clamp(min + math.floor((math.clamp(v, min, max) - min) / step + 0.5) * step, min, max)
				v = tonumber(string.format("%.4f", v))
				local changed = v ~= s.Value
				s.Value = v
				fill.Size = UDim2.fromScale(max > min and (v - min) / (max - min) or 0, 1)
				input.Text = tostring(v)
				return changed
			end
			local key
			function s._apply(v) apply(v) end
			function s._notify() fire(key or o.Title or "slider", o.Callback, s.Value) end
			function s:Set(v)
				if apply(v) then
					if key then userChanged(key) end
					s._notify()
					markDirty()
				end
			end
			input.FocusLost:Connect(function()
				local n = tonumber(input.Text)
				if n then s:Set(n) else input.Text = tostring(s.Value); if notify then notify("Enter a valid number.", "error") end end
			end)
			grab.InputBegan:Connect(function(i)
				if not POINTER[i.UserInputType] or dragBusy() then return end
				scroll.ScrollingEnabled = false -- so a touch drag moves the slider, not the page
				startDrag(i, function(p)
					s:Set(min + (p.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X * (max - min))
				end, function() scroll.ScrollingEnabled = true end)
			end)
			apply(o.Default or min)
			sliderRows[sliderRow] = { nudge = function(dir) s:Set(s.Value + dir * step) end }
			key = track(o, s, s.Value, function() return s.Value end, function(v)
				if num(v) then return { v } end
			end, sliderRow)
			return s
		end

		-- Plain wrapping text (notes, status lines). Set(text) updates it.
		function Section:AddLabel(textOrOpts)
			local o = type(textOrOpts) == "table" and textOrOpts or { Text = textOrOpts }
			local l = label({
				Name = "Label", Parent = elements, Text = tostring(o.Text or o.Title or ""), TextColor3 = Theme.SubText, TextWrapped = true,
				TextTruncate = Enum.TextTruncate.None, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, LayoutOrder = nextOrder(),
			})
			bindStyle(page, l, function(tk) l.TextSize = tk.LabelSize end)
			return { Set = function(_, t) l.Text = tostring(t) end }
		end

		function Section:AddDivider()
			new("Frame", { Name = "Divider", Parent = elements, Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Theme.Border, BorderSizePixel = 0, LayoutOrder = nextOrder() })
		end

		function Section:AddInput(a, b)
			local o = args(a, b)
			local f, _, _, info = row(o)
			local box = wideRight(info)
			box.ClipsDescendants = true
			local tb = textBox(box, { Text = o.Default or "", PlaceholderText = o.Placeholder or "--", TextXAlignment = Enum.TextXAlignment.Left })
			noFocus[tb] = true -- the row is the focus stop; Enter/A puts the caret in the box
			bindStyle(page, tb, function(tk)
				sty(tb, { Position = UDim2.fromOffset(tk.FieldInset, 0), Size = UDim2.new(1, -2 * tk.FieldInset, 1, 0) })
			end)
			local inp = { Value = tb.Text }
			local key
			function inp._apply(v)
				tb.Text = tostring(v)
				inp.Value = tb.Text
			end
			function inp._notify() fire(key or o.Title or "input", o.Callback, inp.Value) end
			function inp:Set(v)
				inp._apply(v)
				if key then userChanged(key) end
				inp._notify()
				markDirty()
			end
			tb.FocusLost:Connect(function()
				if tb.Text ~= inp.Value then inp:Set(tb.Text) end
			end)
			tb.Focused:Connect(function() keepVisible(scroll, f) end)
			f.Activated:Connect(function() tb:CaptureFocus() end)
			key = track(o, inp, inp.Value, function() return inp.Value end, function(v)
				if type(v) == "string" then return { v } end
			end, f)
			return inp
		end

		-- Callback runs on key press; Changed runs on rebind. Escape cancels, Backspace/Delete clears.
		function Section:AddKeybind(a, b)
			local o = args(a, b)
			local f, _, right = row(o)
			local box = fieldCorner(field({ Name = "Key", Parent = right, Size = UDim2.fromOffset(28, 28) }))
			local text = new("TextLabel", { Parent = box, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, TextSize = 13, FontFace = Font.new(FONT, W.Medium), TextColor3 = Theme.SubText, Text = "" })
			local refit = autoWidth(box, text, function() return style.KeyMinWidth end, 110)
			bindStyle(page, box, function(tk)
				text.TextSize = tk.KeyTextSize
				box.Size = UDim2.fromOffset(box.Size.X.Offset, tk.KeyHeight)
				refit()
			end)
			local default = type(o.Default) == "string" and Enum.KeyCode[o.Default] or o.Default
			local kb = { Value = default, Callback = o.Callback or function() end }
			local function show() text.Text = kb.Value and kb.Value.Name or "None" end
			local key
			function kb._apply(k)
				kb.Value = k
				show()
			end
			-- restoring a key binding is a rebind, so it reports through Changed, never the key's action
			function kb._notify() fire(key or o.Title or "keybind", o.Changed, kb.Value) end
			function kb:Set(k)
				kb._apply(k)
				if key then userChanged(key) end
				kb._notify()
				markDirty()
			end
			function kb.finish(code, cancel)
				if cancel or code == Enum.KeyCode.Escape or code == Enum.KeyCode.Unknown then
					show()
				elseif code == Enum.KeyCode.Backspace or code == Enum.KeyCode.Delete then
					kb:Set(nil)
				else
					kb:Set(code)
				end
			end
			f.Activated:Connect(function()
				if not UIS.KeyboardEnabled then -- touch-only: no keys to bind, so a tap runs the action
					fire("keybind", kb.Callback, kb.Value)
					return
				end
				capturing = kb
				text.Text = "..."
			end)
			table.insert(keybinds, kb)
			table.insert(owned.keybinds, kb)
			show()
			key = track(o, kb, default, function() return kb.Value and kb.Value.Name or "None" end, function(v)
				if v == "None" then return { nil } end
				if type(v) ~= "string" then return nil end
				local ok, code = pcall(function() return Enum.KeyCode[v] end)
				if ok and code then return { code } end
			end, f)
			return kb
		end

		return Section
	end

	---------------------------------------------------------------- public API
	local Window = { Gui = gui, Maid = maid, Animations = anim }
	function Window:Destroy() maid:Clean() end
	function Window:Notify(message, kind, duration) notify(message, kind, duration) end
	function Window:GetFavorites() return table.clone(favorites.list) end
	function Window:SetFolded(v) setFolded(v) end
	function Window:IsFolded() return minimized end
	-- Locked: the header no longer drags the window (folding and resizing still work).
	function Window:SetLocked(v)
		locked = v and true or false
		markDirty()
	end
	function Window:IsLocked() return locked end
	-- SizeLocked: hides the resize grip.
	function Window:SetSizeLocked(v)
		sizeLocked = v and true or false
		refreshGrip()
		markDirty()
	end
	function Window:IsSizeLocked() return sizeLocked end
	-- Vector2 for a manual size, nil to go back to the automatic 800x500.
	function Window:SetSize(v)
		manualSize = typeof(v) == "Vector2" and v or nil
		computeSize()
		paintFold()
		layoutChrome(true)
		setPos(wantPos)
		markDirty()
	end
	function Window:GetSize() return size end
	-- Preferred = the user's/default size, Effective = what is drawn now, Min/Max = limits after fitting the screen.
	-- Min = preferred minimum (automatic size), CompactMin = how small a manual resize may go, both already cut
	-- down to the screen; Preferred is never changed by the screen.
	function Window:GetSizeInfo()
		local minS, maxS, compactS = limits()
		return { Preferred = manualSize or Vector2.new(800, 500), Effective = size, Min = minS, CompactMin = compactS, Max = maxS, Manual = manualSize ~= nil, Scale = scale }
	end
	-- UI scale of the window (0.5 .. 2). Layout keeps working in unscaled units.
	function Window:SetScale(v)
		assert(type(v) == "number", "scale must be a number")
		scale = math.clamp(v, 0.5, 2)
		windowScale.Scale = scale
		applyLayout()
		markAll("width")
	end
	-- Keyboard/gamepad focus: Focus() moves selection into the window (active tab, or the menu button when the
	-- sidebar is a drawer); Blur() hands it back to the game.
	function Window:Focus() focusTo(focusFallback()) end
	function Window:Blur()
		if ownsSelection() then GuiService.SelectedObject = nil end
	end
	function Window:IsFocused() return ownsSelection() end
	-- Back to the centered default position (size is kept).
	function Window:ResetPosition()
		wantPos = nil
		setPos(nil)
		markDirty()
	end
	-- "Auto": two columns when the sections' MinWidths fit side by side; "Single"; "Double", which shows one column
	-- while two can't fit and returns by itself when they can. Only this call changes the saved preference.
	function Window:SetLayout(m)
		assert(LAYOUTS[m], "Layout must be Auto, Single or Double")
		layoutMode = m
		for _, p in ipairs(pages) do p.assignDirty = true end
		markAll("structure")
		markDirty()
	end
	function Window:GetLayout() return layoutMode end
	-- What the current page actually shows: "Single", "Double" or "Empty".
	function Window:GetEffectiveLayout() return current and current.effective or "Empty" end
	-- Density preference; Auto also determines navigation when WindowLayout is Auto. Saved independently.
	function Window:SetCompactMode(m)
		assert(COMPACT_MODES[m], "Compact mode must be Auto, Full, Compact or Mobile")
		compactPref = m
		layoutChrome(true)
		markDirty()
	end
	function Window:GetCompactMode() return compactPref end
	function Window:GetEffectiveCompactMode() return presentation end
	-- Explicit navigation layout is independent of section columns and presentation style.
	function Window:SetWindowLayout(m)
		assert(WINDOW_LAYOUTS[m], "Window layout must be Auto, Sidebar or Topbar")
		windowLayoutPref = m
		closePopup()
		layoutChrome(true)
		markDirty()
	end
	function Window:GetWindowLayout() return windowLayoutPref end
	function Window:GetEffectiveWindowLayout() return navDrawer and "Topbar" or "Sidebar" end
	-- Legacy calls take control again via Auto, preserving their original responsive behavior.
	function Window:SetSidebarCollapsed(v)
		sidebarPref = v and true or false
		windowLayoutPref = "Auto"
		layoutChrome(true)
		markDirty()
	end
	-- True while the sidebar is not docked, whether by preference or for lack of space.
	function Window:IsSidebarCollapsed() return navDrawer == true end
	function Window:SetNavigationOpen(v) setDrawer(v) end
	function Window:IsNavigationOpen() return drawerOpen end
	function Window:SetTabAnimationsEnabled(v)
		tabAnimations = v == true
		if not tabAnimations then
			pageGeneration += 1
			pageMoving = false
			for _, p in ipairs(pages) do resetPage(p, p == current) end
			anim:Stop(indicator)
			indicatorTarget = nil
			updateIndicator(false)
		end
		markDirty()
	end
	function Window:SetTabAnimationSpeed(n)
		assert(num(n) and n > 0, "speed must be a positive number")
		tabSpeed = math.clamp(n, 0.25, 4)
		markDirty()
	end
	-- Requested width cap and optional row equalization are independent of navigation and style.
	function Window:SetMaxSectionGridWidth(v)
		assert(num(v) and v >= 240, "grid width must be at least 240")
		gridMax = v
		markAll("structure")
		markDirty()
	end
	function Window:GetMaxSectionGridWidth() return gridMax end
	function Window:SetEqualRowHeight(v)
		equalRows = v == true
		for _, p in ipairs(pages) do p.assignDirty = true end
		markAll("structure")
		markDirty()
	end
	function Window:GetEqualRowHeight() return equalRows end
	function Window:SetFitWindowToContent(v)
		fitContent = v == true
		computeSize()
		paintFold()
		layoutChrome(true)
		setPos(wantPos)
		markDirty()
	end
	function Window:GetFitWindowToContent() return fitContent end
	function Window:SetSectionTransitionsEnabled(v)
		transitionsOn = v and true or false
		if not transitionsOn then
			for _, p in ipairs(pages) do finishMoves(p) end
		end
		markDirty()
	end
	function Window:SetSectionTransitionSpeed(n)
		assert(type(n) == "number" and n > 0, "speed must be a positive number")
		transitionSpeed = math.clamp(n, 0.25, 4)
		markDirty()
	end
	-- Presentation style switch. Instances, values, callbacks and scroll positions are untouched: every styled
	-- property is re-applied from the tokens. Bindings on the visible page (and the shared chrome) tween; hidden
	-- pages are assigned instantly. Section placement then goes through the normal structure relayout, so
	-- positions move via SectionTransitionController and nothing under a UIListLayout is tweened directly.
	local function applyStyle(name, smooth)
		stylePref, style = name, STYLE_TOKENS[name]
		local animated = smooth and layoutReady and not minimized and foldValue.Value == 0 and not anim:IsReduced()
		local i = 1
		while i <= #styleBindings do
			local b = styleBindings[i]
			if b.inst.Parent == nil then
				table.remove(styleBindings, i) -- destroyed component
			else
				styleAnimating = animated and (b.page == nil or b.page == current)
				local ok, err = pcall(b.fn, style)
				if not ok then warn("[Ethos] style binding failed: " .. tostring(err)) end
				i += 1
			end
		end
		for _, p in ipairs(pages) do
			styleAnimating = animated and p == current
			pagePadding(p)
		end
		styleAnimating = animated
		refreshTabs()
		styleAnimating = false
		layoutChrome(animated, true)
		for _, p in ipairs(pages) do p.assignDirty = true end
		markAll("structure")
		selDirty, headerDirty, statusDirty = true, true, true
	end
	function Window:SetPresentationStyle(name)
		assert(STYLE_TOKENS[name], 'style must be "Modern" or "Classic"')
		if name == stylePref and style == STYLE_TOKENS[name] then return end
		applyStyle(name, true)
		markDirty() -- debounced save of the preference only
	end
	function Window:GetPresentationStyle() return stylePref end
	function Window:GetDiagnostics()
		local moving = 0
		for _, p in ipairs(pages) do
			if p.tr then moving += 1 end
		end
		return {
			RequestedLayout = layoutMode, EffectiveLayout = current and current.effective, CompactMode = compactPref,
			Presentation = presentation, SidebarPreference = sidebarPref, NavigationDrawer = navDrawer, DrawerOpen = drawerOpen,
			WindowLayout = windowLayoutPref, EffectiveWindowLayout = navDrawer and "Topbar" or "Sidebar",
			TransitionsEnabled = transitionsOn, TransitionSpeed = transitionSpeed, PagesMoving = moving,
			WindowSize = size, ContentWidth = current and canvasWidth(current), Scale = scale, Stats = table.clone(stats),
			PresentationStyle = stylePref, StyleBindings = #styleBindings,
		}
	end
	function Window:GetComponent(key) return components[key] and components[key].c end

	---------------------------------------------------------------- header priority layout
	-- Title, minimize and close always stay. When space runs out the outlined badges (last added first) move into
	-- the ··· overflow, then the game badge is shortened, then it moves to the overflow too. Natural widths are
	-- measured while a badge is shown at full size, estimated from its text otherwise.
	local hiddenHeader = {}
	local BOLD, REGULAR = Font.new(FONT, W.Bold), Font.new(FONT)
	-- Exact badge width: measured text + its padding (4+4 game badge, 6+6 outlined; the 1px stroke draws outside).
	local function widthOf(b)
		return textWidth(b.Text, 12, b == accent and BOLD or REGULAR) + (b == accent and 8 or 12)
	end
	-- A text change re-lays the header in the same frame, before anything is drawn with the old layout.
	local function watchBadge(b)
		b:GetPropertyChangedSignal("Text"):Connect(function()
			if layoutHeader then layoutHeader() end
		end)
	end
	if accent then watchBadge(accent) end
	function layoutHeader()
		stats.header += 1
		if search.resizeResults then search.resizeResults() end
		local GAP, titleW, winW = 6, textWidth(titleLabel.Text, 16, titleLabel.FontFace), size.X -- logical units
		if search.open then
			local limit = search.targetWidth()
			if search.field.Size.X.Offset > limit then anim:Stop(search.field, { "Size" }); search.field.Size = UDim2.fromOffset(limit, 28) end
			local cw = 96 + search.field.Size.X.Offset
			local baseWidth = math.max(0, winW - (15 + 10 + cw + 8))
			base.Visible, moreBtn.Visible = baseWidth >= 35, false
			base.Position, base.Size = UDim2.fromOffset(15, 0), UDim2.new(0, baseWidth, 1, 0)
			control.Size = UDim2.new(0, cw, 1, 0)
			return
		end
		base.Visible = true
		local function total(nOut, aW)
			local sum, count = 0, 0
			if aW and aW > 0 then sum += aW; count += 1 end
			for i = 1, nOut do sum += widthOf(badges[i]); count += 1 end
			return titleW + (count > 0 and (2 * GAP + sum + GAP * (count - 1)) or 0)
		end
		local function avail(more) return winW - 15 - 10 - (more and 124 or 92) - search.field.Size.X.Offset - (search.field.Visible and 4 or 0) - 8 end
		local full = accent and widthOf(accent) or nil
		local nOut, aW, more = #badges, full, false
		if total(nOut, aW) > avail(false) then
			more = true
			while nOut > 0 and total(nOut, aW) > avail(true) do nOut -= 1 end
			if aW and total(nOut, aW) > avail(true) then
				local room = avail(true) - titleW - 2 * GAP
				aW = room >= 44 and room or 0 -- shorten, or move to the overflow when too small to read
			end
		end
		table.clear(hiddenHeader)
		if accent then
			if aW == 0 then
				accent.Visible = false
				table.insert(hiddenHeader, accent.Text)
			else
				accent.Visible = true
				if aW < full then
					accent.AutomaticSize, accent.Size, accent.TextTruncate = AUTO_NONE, UDim2.fromOffset(aW, 16), Enum.TextTruncate.AtEnd
					table.insert(hiddenHeader, accent.Text) -- the overflow shows it in full
				else
					accent.AutomaticSize, accent.Size, accent.TextTruncate = AUTO_X, UDim2.fromOffset(0, 16), Enum.TextTruncate.None
				end
			end
		end
		for i, b in ipairs(badges) do
			b.Visible = i <= nOut
			if i > nOut then table.insert(hiddenHeader, b.Text) end
		end
		moreBtn.Visible = more
		local cw = (more and 124 or 92) + search.field.Size.X.Offset + (search.field.Visible and 4 or 0)
		control.Size = UDim2.new(0, cw, 1, 0)
		base.Position, base.Size = UDim2.fromOffset(15, 0), UDim2.new(1, -(15 + 10 + cw + 8), 1, 0)
	end
	local function noPick() return false end
	moreBtn.Activated:Connect(function()
		if #hiddenHeader > 0 then openList(moreBtn, table.clone(hiddenHeader), noPick, noPick) end
	end)

	-- Outlined pill after the title, e.g. "v0.0.0".
	function Window:AddBadge(text)
		local b = new("TextLabel", {
			Name = "Badge", Parent = base, Text = text, TextSize = 12, FontFace = Font.new(FONT), TextColor3 = Theme.Muted,
			BackgroundColor3 = Theme.Panel, BorderSizePixel = 0, AutomaticSize = AUTO_X, Size = UDim2.fromOffset(0, 16), LayoutOrder = 2 + nextOrder(),
		}, { corner(3), stroke(), padding(6, 6) })
		table.insert(badges, b)
		watchBadge(b)
		headerDirty = true
		return { Set = function(_, t) b.Text = t end }
	end

	---------------------------------------------------------------- status priority layout
	-- Statuses are shown by importance (critical first, then Priority, then the order they were added) while they
	-- fit; the rest collapse into a "+N" chip that opens the details. When not even one label fits, the shown
	-- statuses drop to their colored dots. The bar already stops short of the resize grip.
	local statusCells, hiddenStatus = {}, {}
	local statusMore = new("TextButton", {
		Name = "MoreStatus", Parent = footer, Text = "", AutoButtonColor = false, BackgroundTransparency = 1, AutomaticSize = AUTO_X,
		Size = UDim2.fromScale(0, 1), LayoutOrder = 1e7, Visible = false, TextSize = 12, FontFace = Font.new(FONT, W.Medium), TextColor3 = Theme.SubText,
	}, { padding(8, 8) })
	statusMore.Activated:Connect(function()
		if #hiddenStatus > 0 then openList(statusMore, table.clone(hiddenStatus), noPick, noPick) end
	end)
	-- Exact cell width: 10 + dot 6 + gap 9 + text + 10.
	local function statusWidth(s) return textWidth(s.txt.Text, 12, REGULAR) + 35 end
	function layoutStatus()
		if #statusCells == 0 then return end
		stats.status += 1
		local avail = size.X - (navDrawer and 0 or style.SidebarWidth) - 22 -- the bar's target width, logical units
		local ranked = table.clone(statusCells)
		table.sort(ranked, function(a, b)
			if a.critical ~= b.critical then return a.critical end
			if a.priority ~= b.priority then return a.priority > b.priority end
			return a.index < b.index
		end)
		local CHIP, DOT = 40, 27
		local show, dots, all = {}, false, 0
		for _, s in ipairs(ranked) do all += statusWidth(s) + 1 end
		if all <= avail then
			for _, s in ipairs(ranked) do show[s] = true end
		else
			local used = CHIP
			for _, s in ipairs(ranked) do
				local w = statusWidth(s) + 1
				if used + w > avail then break end
				used += w
				show[s] = true
			end
			if next(show) == nil then
				dots, used = true, CHIP
				for _, s in ipairs(ranked) do
					if used + DOT > avail then break end
					used += DOT
					show[s] = true
				end
			end
		end
		table.clear(hiddenStatus)
		local first, hidden = true, 0
		for _, s in ipairs(statusCells) do -- drawn in the order they were added
			local on = show[s] == true
			s.cell.Visible, s.txt.Visible = on, not dots
			s.sep.Visible = on and not first
			if on then first = false else hidden += 1 end
			if not on or dots then table.insert(hiddenStatus, "● " .. s.txt.Text) end
		end
		statusMore.Visible = hidden > 0 or dots
		statusMore.Text = hidden > 0 and ("+" .. hidden) or "···"
	end

	-- Status bar cell: colored dot + text. Set(text, color, critical) updates it; o = {Priority = n, Critical = bool}.
	function Window:AddStatus(text, color, o)
		o = type(o) == "table" and o or {}
		statuses += 1
		local ord = nextOrder() * 2
		local sep = new("Frame", { Name = "Sep", Parent = footer, Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = Theme.Border, BorderSizePixel = 0, LayoutOrder = ord })
		local cell = new("Frame", { Name = "Status", Parent = footer, BackgroundTransparency = 1, Size = UDim2.fromScale(0, 1), AutomaticSize = AUTO_X, LayoutOrder = ord + 1 }, { hlist(9), padding(10, 10) })
		local dot = new("Frame", { Name = "Dot", Parent = cell, Size = UDim2.fromOffset(6, 6), BorderSizePixel = 0 }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		local glow = stroke(nil, 2)
		glow.Transparency, glow.Parent = 0.82, dot
		local txt = label({ Parent = cell, TextSize = 12, TextColor3 = Theme.SubText, AutomaticSize = AUTO_X, Size = UDim2.fromScale(0, 1), LayoutOrder = 1 })
		local s = { cell = cell, sep = sep, txt = txt, index = statuses, critical = o.Critical == true, priority = num(o.Priority) and o.Priority or -statuses }
		table.insert(statusCells, s)
		local api = {}
		function api:Set(t, c, critical)
			if t and t ~= txt.Text then txt.Text = t end
			dot.BackgroundColor3, glow.Color = c or dot.BackgroundColor3, c or dot.BackgroundColor3
			if critical ~= nil then s.critical = critical == true end
			if layoutStatus and presentation then layoutStatus() end -- same frame: the new text never overflows first
		end
		function api:SetPriority(n)
			s.priority = n
			statusDirty = true
		end
		api:Set(text, color or Theme.Warn)
		applyLayout()
		return api
	end

	---------------------------------------------------------------- navigation, pages and sections
	function Window:AddCategory(name)
		local holder = new("Frame", { Name = name, Parent = sideScroll, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, BackgroundTransparency = 1, LayoutOrder = nextOrder() }, { vlist(0) })
		local header = new("TextButton", { Name = "Header", Parent = holder, Text = "", Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1 })
		local headerLabel = label({ Parent = header, Text = name, TextSize = 16, FontFace = Font.new(FONT, W.Medium), TextColor3 = Theme.SubText, Size = UDim2.new(1, -16, 1, 0) })
		bindStyle(nil, header, function(t)
			headerLabel.TextSize = t.CategoryTextSize
			local inset = t.Underline and 10 or 0
			anim:Stop(headerLabel, { "Position", "Size" })
			headerLabel.Position, headerLabel.Size = UDim2.fromOffset(inset, 0), UDim2.new(1, -16 - inset, 1, 0)
			sty(header, { Size = UDim2.new(1, 0, 0, t.CategoryHeaderHeight) })
		end)
		local arrow = iconImage({
			Parent = header, Image = ICON.chevron, ImageColor3 = Theme.Muted,
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(12, 12), Rotation = 90,
		})
		local viewport = new("Frame", { Name = "CategoryViewport", Parent = holder, Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, ClipsDescendants = true, LayoutOrder = 1 })
		local itemLayout = vlist(0)
		local items = new("Frame", { Name = "Items", Parent = viewport, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, BackgroundTransparency = 1 }, { itemLayout })
		local progress = new("NumberValue", { Name = "AccordionProgress", Value = 1, Parent = holder })
		local group = { header = header, viewport = viewport, items = items, requested = true, effective = true, tabs = {} }
		local function updateHeight()
			local full = px(itemLayout.AbsoluteContentSize.Y)
			viewport.Size = UDim2.new(1, 0, 0, math.max(0, math.round(full * progress.Value)))
			selDirty = true
		end
		connect(progress.Changed, updateHeight)
		connect(itemLayout:GetPropertyChangedSignal("AbsoluteContentSize"), updateHeight)
		connect(windowScale:GetPropertyChangedSignal("Scale"), updateHeight)
		header.Activated:Connect(function()
			group.requested = not group.requested
			group.effective = nil -- a transition is in progress
			local opening = group.requested
			if not opening then
				local selected = GuiService.SelectedObject
				if selected and selected:IsDescendantOf(viewport) then focusTo(header) end
			end
			selDirty = true
			items.Visible = true
			local fromClosed = progress.Value <= 0.001
			for i, tab in ipairs(group.tabs) do
				anim:Stop(tab, { "Position", "TextTransparency" })
				if opening then
					if fromClosed then tab.Position, tab.TextTransparency = UDim2.fromOffset(6, 0), 1 end
					local info = TweenInfo.new(0.18, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out, 0, false, math.min(0.10, (i - 1) * 0.02))
					animate(tab, info, { Position = UDim2.fromOffset(0, 0), TextTransparency = 0 })
				end
			end
			animate(arrow, TweenInfo.new(0.20, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Rotation = opening and 90 or 0 })
			local info = opening and TweenInfo.new(0.25, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out) or TweenInfo.new(0.22, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut)
			animate(progress, info, { Value = opening and 1 or 0 }, function()
				group.effective = opening
				if not opening then
					items.Visible = false
					for _, tab in ipairs(group.tabs) do
						anim:Stop(tab, { "Position", "TextTransparency" })
						tab.Position, tab.TextTransparency = UDim2.fromOffset(0, 0), 0
					end
				end
				selDirty = true
			end)
		end)

		local Category = {}
		function Category:AddPage(pageName)
			local tabPad = padding(0, 0, 7)
			local tabRow = new("Frame", { Name = "TabRow", Parent = items, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = nextOrder() })
			local tab = new("TextButton", {
				Name = pageName, Parent = tabRow, Text = pageName, TextSize = 14, FontFace = Font.new(FONT),
				TextColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
				TextTruncate = Enum.TextTruncate.AtEnd, BackgroundColor3 = Theme.Hover, BackgroundTransparency = 1, AutoButtonColor = false,
				Size = UDim2.fromScale(1, 1),
			}, { tabPad })
			table.insert(group.tabs, tab)
			tabGroups[tab] = group
			local frame = new("Frame", { Name = pageName, Parent = pageContainer, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false })
			local shield = new("TextButton", { Name = "TransitionShield", Parent = frame, Size = UDim2.fromScale(1, 1), Text = "", BackgroundTransparency = 1, AutoButtonColor = false, Visible = false, ZIndex = 100 })
			local scroll = new("ScrollingFrame", {
				Name = "Scroll", Parent = frame, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
				ScrollBarThickness = 4, ScrollBarImageColor3 = Theme.Scrollbar, CanvasSize = UDim2.new(),
				AutomaticCanvasSize = AUTO_NONE, ScrollingDirection = Enum.ScrollingDirection.Y,
			})
			local pad = padding(8, 7, 9, 9)
			pad.Parent = scroll
			-- sections are placed on this canvas by the layout engine (canvas-local offsets)
			local canvas = new("Frame", { Name = "Canvas", Parent = scroll, Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1 })
			local empty = label({
				Name = "Empty", Parent = frame, Text = opts.EmptyText or "Nothing here yet", TextSize = 14, TextColor3 = Theme.Muted,
				TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, -40, 0, 20), Visible = false,
			})
			local page = {
				frame = frame, shield = shield, tab = tab, tabRow = tabRow, group = group, tabPad = tabPad, index = #pages + 1, key = name .. "/" .. pageName, category = name, name = pageName,
				scroll = scroll, canvas = canvas, pad = pad, padY = 18, empty = empty, sections = {}, assignDirty = true,
			}
			pagePadding(page)
			table.insert(pages, page)
			table.insert(searchRecords, { page = page })
			canvas:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() markPage(page, "width") end)
			scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
				if not page.selfScroll then page.userScrollAt = os.clock() end
			end)
			tab.Activated:Connect(function() selectPage(page) end)
			hover(tab, function(on)
				page.hovered = on
				animate(tab, FAST, { TextColor3 = current == page and Theme.Text or (on and Theme.SubText or Theme.Muted) })
			end)
			tab.InputBegan:Connect(function(i)
				if POINTER[i.UserInputType] then page.pressed = true; animate(tab, FAST, { BackgroundColor3 = Theme.Hover, BackgroundTransparency = 0.65 }) end
			end)
			tab.InputEnded:Connect(function(i)
				if POINTER[i.UserInputType] then page.pressed = false; animate(tab, FAST, { BackgroundTransparency = current == page and not style.Underline and 0.82 or 1 }) end
			end)
			markPage(page, "structure")
			if not current or prof.Window.Page == page.key then selectPage(page) else refreshTabs() end -- first page, or the one saved last time

			local Page = {}
			-- AddSection(name) / (name, "Left"|"Right") / (name, {Side, MinWidth, MaxWidth, FullWidth}).
			-- Without a side, a section goes to the shorter column; FullWidth spans both columns.
			function Page:AddSection(sectionName, o)
				local side, minW, maxW, full
				if type(o) == "table" then
					side, minW, maxW, full = o.Side, o.MinWidth, o.MaxWidth, o.FullWidth == true
				else
					side = o
				end
				if side ~= "Left" and side ~= "Right" then side = nil end
				local spad = padding(15, 14, 14, 14)
				local sCorner, sStroke, sList = corner(3), stroke(), vlist(10)
				local sTitle = label({ Name = "Title", Text = sectionName, TextSize = 18, FontFace = Font.new(FONT, W.SemiBold), TextColor3 = Theme.Muted, Size = UDim2.new(1, 0, 0, 20) })
				local sectionFrame = new("Frame", {
					Name = "Section", Parent = canvas, Size = UDim2.fromOffset(math.floor(px(canvas.AbsoluteSize.X)), 0), AutomaticSize = AUTO_Y,
					BackgroundColor3 = Theme.Panel, BorderSizePixel = 0,
				}, { sCorner, sStroke, sList, spad, sTitle })
				-- MinWidth stays nil unless given, so the style's own default applies
				local rec = {
					frame = sectionFrame, side = side, pad = spad, list = sList, full = full,
					minW = num(minW) and math.max(120, minW) or nil, maxW = num(maxW) and math.max(120, maxW) or nil,
				}
				table.insert(page.sections, rec)
				page.empty.Visible = false -- section registration takes effect before the next layout step
				page.assignDirty = true
				sectionFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() markPage(page, "height") end)
				connect(sList:GetPropertyChangedSignal("AbsoluteContentSize"), function() if equalRows then markPage(page, "height") end end)
				markPage(page, "insert")
				local elementsList = vlist(10)
				local elements = new("Frame", { Name = "Elements", Parent = sectionFrame, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, BackgroundTransparency = 1, LayoutOrder = 1 }, { elementsList })
				bindStyle(page, sectionFrame, function(t)
					sectionPadding(spad)
					sty(sCorner, { CornerRadius = UDim.new(0, t.SectionCorner) })
					sty(sStroke, { Thickness = t.BorderThickness, Transparency = t.BorderTransparency })
					sTitle.TextSize = t.SectionTitleSize
					sty(sTitle, { Size = UDim2.new(1, 0, 0, t.SectionHeaderHeight) })
					sty(sList, { Padding = UDim.new(0, t.SectionHeaderGap) })
					sty(elementsList, { Padding = UDim.new(0, t.RowGap) })
				end)
				local owned = { keys = {}, keybinds = {}, panels = {}, search = {} }
				rec.stops = {}
				local sec = makeSection(elements, scroll, page.key .. "/" .. sectionName .. "/", "", owned, rec.stops, page, sectionName)
				-- Removes the section and everything it registered; the remaining sections move into its place.
				function sec:Destroy()
					local at = table.find(page.sections, rec)
					if not at then return end
					table.remove(page.sections, at)
					page.empty.Visible = page == current and #page.sections == 0
					for _, entry in ipairs(owned.search) do
						local i = table.find(searchRecords, entry)
						if i then table.remove(searchRecords, i) end
					end
					if refreshSearch and search.open then refreshSearch() end
					for _, k in ipairs(owned.keys) do
						components[k], restorePending[k] = nil, nil
						local i = table.find(componentOrder, k)
						if i then table.remove(componentOrder, i) end
					end
					for _, kb in ipairs(owned.keybinds) do
						local i = table.find(keybinds, kb)
						if i then table.remove(keybinds, i) end
						if capturing == kb then capturing = nil end
					end
					for _, entry in ipairs(owned.panels) do
						local i = table.find(optionPanels, entry)
						if i then table.remove(optionPanels, i) end
					end
					sectionFrame:Destroy()
					page.assignDirty = true
					markPage(page, "insert")
				end
				return sec
			end
			return Page
		end
		return Category
	end

	---------------------------------------------------------------- SaveManager API
	local function firstPage(key)
		for _, p in ipairs(pages) do
			if p.key == key then return p end
		end
		return pages[1]
	end
	-- Applies prof to everything that already exists: window state, active page, every component (missing = default).
	-- Values are applied first, in registration order, each isolated; then callbacks run only for components whose
	-- value actually changed (none in Silent mode), in the same order.
	local function applyProfile()
		restoring = true
		table.clear(restorePending) -- a profile switch supersedes restores still waiting to run
		local w = prof.Window
		pageGeneration += 1
		pageMoving = false
		for _, pg in ipairs(pages) do resetPage(pg, pg == current) end
		readWindow(w)
		if refreshSearch and search.open then refreshSearch() end
		if style ~= STYLE_TOKENS[stylePref] then applyStyle(stylePref, true) end
		applyLayout()
		for _, pg in ipairs(pages) do pg.assignDirty = true end
		markAll("structure") -- a restored layout preference re-lays every page
		setFolded(w.Folded == true, true)
		refreshGrip()
		local p = firstPage(w.Page)
		if p then selectPage(p) end
		if rememberOptions then
			for _, panel in ipairs(optionPanels) do panel.Options:SetOpen(savedExpanded(panel.key), true) end
		end
		local changed = {}
		for _, k in ipairs(componentOrder) do
			local entry = components[k]
			local raw, box = prof.Values[k], nil
			if raw ~= nil then
				local ok, res = pcall(entry.decode, raw)
				if ok then box = res end
			end
			local value
			if box then value = box[1] else value = entry.default end
			local before = HttpService:JSONEncode({ entry.encode() })
			local ok, err = pcall(entry.c._apply, value)
			if not ok then
				warn("[Ethos] restore of " .. k .. " failed: " .. tostring(err))
			elseif HttpService:JSONEncode({ entry.encode() }) ~= before then
				table.insert(changed, k)
			end
		end
		restoring = false
		if restoreMode ~= "Silent" then
			for _, k in ipairs(changed) do
				local ok, err = pcall(components[k].c._notify)
				if not ok then warn("[Ethos] callback for " .. k .. " failed: " .. tostring(err)) end
			end
		end
	end
	Window.SaveManager = SaveManager
	-- Writes now; returns whether the backend accepted it.
	function SaveManager:Save()
		local ok = flush()
		if ok then notify(sessionOnly and "Profile saved for this session" or "Profile saved", "success") end
		return ok
	end
	-- Re-reads the backend and applies the active profile.
	function SaveManager:Load()
		local ok, data = pcall(backend.Load)
		if not ok then notify("Could not load the profile.", "error"); return false, tostring(data) end
		store = migrate(data)
		prof = sanitize(store.Profiles[store.Profile])
		store.Profiles[store.Profile] = prof
		applyProfile()
		return true
	end
	function SaveManager:Export()
		return HttpService:JSONEncode({ Version = SCHEMA, Profile = snapshot() })
	end
	function SaveManager:Import(json)
		local ok, data = pcall(function() return HttpService:JSONDecode(json) end)
		if not ok or type(data) ~= "table" or type(data.Profile) ~= "table" then notify("Invalid configuration.", "error"); return false, "not an Ethos config" end
		prof = sanitize(data.Profile)
		store.Profiles[store.Profile] = prof
		applyProfile()
		if flush() then notify("Configuration imported", "success") end
		return true
	end
	-- Back to defaults for the active profile: auto size, centered, unfolded, unlocked, Auto layout, first page.
	function SaveManager:Reset()
		prof = sanitize({})
		store.Profiles[store.Profile] = prof
		applyProfile()
		if flush() then notify("Profile reset", "success") end
	end
	function SaveManager:GetProfile() return store.Profile end
	function SaveManager:ListProfiles()
		local names = {}
		for name in pairs(store.Profiles) do table.insert(names, name) end
		table.sort(names)
		return names
	end
	-- Saves the current profile, then switches; a new name starts as a copy of the current state.
	function SaveManager:SetProfile(name)
		assert(type(name) == "string" and name ~= "", "Profile name must be a non-empty string")
		flush()
		if store.Profiles[name] == nil then store.Profiles[name] = snapshot() end
		store.Profile = name
		prof = sanitize(store.Profiles[name])
		store.Profiles[name] = prof
		applyProfile()
		if flush() then notify("Profile: " .. store.Profile, "success") end
	end
	function SaveManager:DeleteProfile(name)
		if name == store.Profile or store.Profiles[name] == nil then return false end
		store.Profiles[name] = nil
		flush()
		return true
	end
	function SaveManager:SetAutoSave(v) autoSave = v ~= false end

	---------------------------------------------------------------- teardown
	-- Runs first on Clean (given last): write pending changes while component values are still readable.
	maid:Give(function()
		if pendingSave then flush() end
		closePopup()
		anim:CancelAll()
		table.clear(keybinds)
		for _, p in ipairs(pages) do p.tr, p.pending = nil, nil end -- no section move outlives the window
		drag, capturing = nil, nil
	end)
	connect(gui.Destroying, function() maid:Clean() end)

	applyLayout()
	refreshGrip()
	if prof.Window.Folded == true then
		restoring = true
		setFolded(true, true)
		restoring = false
	end
	-- Debug = true: a low-priority status shows requested→effective layout and the presentation mode.
	if opts.Debug then debugStatus = Window:AddStatus("layout", Theme.Muted, { Priority = -1000 }) end
	-- Sections added while the script builds the UI are placed instantly; moves animate after it yields.
	task.defer(function() layoutReady = true end)
	return Window
end

return Library
