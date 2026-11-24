--[[
    Linoria UI library (KeneiUmaru fork of violin-suzutsuki/LinoriaLib)

    Usage:
        local Library = loadstring(game:HttpGet('https://raw.githubusercontent.com/KeneiUmaru/Library/main/Linoria.lua'))()
        local ThemeManager, SaveManager = Library.ThemeManager, Library.SaveManager
        local Window = Library:CreateWindow({ Title = 'My hub', Center = true, AutoShow = true })

    Loading this file only builds the library; it creates no window. See bloxspin/kenya_client.lua for a full example.

    Additions over upstream:
        Library:Toggle(state?)                    -- eased fade + scale open/close, interruptible; pass true/false to force
        Library:SetRainbowAccent(on, gradient?)   -- hue-cycling accent, optionally spread down the window
        Library:SetKeybindFrameVisibility(on)     -- keybind HUD, auto-hidden while it has no entries
        Library:SetScale(n)                       -- scale the window and its popups (0.5 - 2)
        Library:SetCursor(source, size?)          -- custom menu cursor: image URL (getcustomasset), file path, .cur or rbxassetid;
                                                  -- '' restores the triangle (Settings > Menu > Custom cursor)
        Library:SetGlow(on, size, transparency)   -- accent glow around the window
        Library:SetElementGlow(on, transparency)  -- glow under toggles, slider fills and color swatches
        Library:AddGlow(parent, size, zindex, colorKey) -- add your own glow to any frame
        Groupbox:AddProgressBar(idx, { Text, Default, Min, Max, Suffix, Format }) -- read-only thin bar, update with :SetValue(n)
        Groupbox:AddButton({ Text, Func, DoubleClick = true, ConfirmationTime = 3 }) -- second click confirms; otherwise resets
        Groupbox:AddLabel(text, wrap?, tooltip?)  -- compact help labels; :AddTooltip(text) also works
        Groupbox:AddTagList({ OnRemove = function(id) end }) -- :SetItems({ { Id, Text, Detail? }, ... }); removable rows
        Groupbox:AddIconLabel(text)               -- :SetRows({ { Text, Icon?, Color? }, ... }); one line per row, an
                                                  -- icon (ImageLabel to copy, or a Model shown in 3D) in front of it
        Dropdown ValueTooltips = { [value] = description } -- or function(value); describes hovered options and selection
        Dropdown ValueIcons = { [value] = image }  -- or function(value) -> image id; an icon in front of each option
        Dropdown search box                       -- on lists longer than 8 values; Searchable = true / false forces it
        Library:Notify(text, seconds?)            -- accent bar along the bottom counts the duration down (default 5s),
                                                  -- then it fades out
        CreateWindow Version / Channel / Subtitle / TitleNote -- title bar as a header: Title on the left with Version
                                                  -- (accent) and Channel (green, e.g. 'BETA') as badges, Subtitle
                                                  -- centred, TitleNote (an invite, a status) on the right
        Groupbox:AddParagraph({ Title, Text, Image, ImageHeight }) -- help text: a title over a dimmer, wrapped body.
                                                  -- Image (rbxassetid / rbxthumb, an id number, or with getcustomasset
                                                  -- a URL or workspace file) adds a banner on top, cropped to
                                                  -- ImageHeight px (72), the title over its lower edge.
                                                  -- :SetTitle(s), :SetText(s), :SetImage(source or nil)
        Library:Modal({ Title, Text, Buttons = { 'Delete', 'Cancel' } }) -- dialog over the dimmed window; yields and
                                                  -- returns the picked button's text. The first button is the accent
                                                  -- one, on the right
        Library:ChangeLog({ Title, Pages = { { Title, Text, Kind = 'new' | 'changed' | 'fixed', Path } } })
                                                  -- what's new, one change per page (Back / Next); yields, true once
                                                  -- read or skipped (save that yourself to show it only once)
        Library:RunOnUIThread(fn, ...)            -- run a menu update from a game callback (CoreGui needs executor identity);
                                                  -- SetText / SetValue / Notify / Toggle / SetWatermark already do this themselves
        Sections (every groupbox / tabbox)        -- -/+ folds it; drag its title to move it (accent box = where it
                                                  -- lands); drop it outside the window to float it, its pin square
                                                  -- keeps it shown while the menu is hidden. Library:GetLayout(),
                                                  -- :ApplyLayout(t), :SaveLayout(), :LoadLayout(), :ResetLayout();
                                                  -- saved to Library.LayoutFile (SaveManager:SetFolder sets it,
                                                  -- SaveManager:LoadAutoloadConfig loads it); it also keeps whether the
                                                  -- menu was open: LoadLayout reopens or hides it that way
                                                  -- (Library.SavedOpen = that value, nil for an older file)
        Library.Animations = true                 -- eased toggles, sliders, hovers, dropdowns, tab switch, folding, button
                                                  -- flash, notifications and the menu fade; false snaps them (Settings >
                                                  -- Menu > Animations). Library:Animate(inst, time, goal) / :CreateTween
        Library.Version                           -- API version number, see bloxspin/kenya_client.lua for the check
        Library.RainbowSpeed / Library.GradientSpread / Library.MenuFadeTime -- live-tunable numbers
        Library.GradientMode ('Rainbow'|'Custom'), GradientDirection ('Vertical'|'Horizontal'|'Diagonal'),
        GradientReverse, GradientColorA/B, RainbowSaturation, RainbowValue -- accent gradient options;
        call Library:RefreshAccent() after changing them while nothing is animating
        Library.NotifyOnError = true              -- turn callback errors into notifications instead of console errors
        Library.ThemeManager / Library.SaveManager are bundled (no extra HttpGet needed)
        ThemeManager:BuildMenuSection(tab)        -- Kenya Client Menu + Accent groupboxes (sets the menu keybind); call before ApplyToTab
        Sliders and tab areas size from the real window, so custom CreateWindow sizes work
        Every connection is tracked so Library:Unload() leaves nothing running
        Mobile: touch works as a click everywhere (sliders, pickers, dragging); toggles, buttons, dropdowns and tabs
                fire on a still tap, so swiping to scroll does not switch them; phones get a fitted window and a
                draggable "Menu" button (Library.MobileButton) since there is no toggle key
        Window resize grip (bottom-right dots, NieR style): drag with mouse or finger, min 400x300
]]

local InputService = game:GetService('UserInputService');
local TextService = game:GetService('TextService');
local CoreGui = game:GetService('CoreGui');
local Teams = game:GetService('Teams');
local Players = game:GetService('Players');
local RunService = game:GetService('RunService')
local TweenService = game:GetService('TweenService');
local GuiService = game:GetService('GuiService');
local RenderStepped = RunService.RenderStepped;
local LocalPlayer = Players.LocalPlayer;
local PlayerMouse = LocalPlayer:GetMouse();

-- Touch support: a finger counts as the left mouse button everywhere. Mouse.X / Mouse.Y read the last touch
-- position while a finger is in use and the real mouse again once it moves (hybrid devices).
local IsMobile = InputService.TouchEnabled and not InputService.MouseEnabled;
local LastTouch = nil;
local HeldTouches = {};
local Mouse = setmetatable({}, { __index = function(_, Key) return (LastTouch or PlayerMouse)[Key]; end });

local function IsClick(Input)
    if Input.UserInputType == Enum.UserInputType.Touch then
        HeldTouches[Input] = true;
        LastTouch = Input.Position;
        return true;
    end;
    return Input.UserInputType == Enum.UserInputType.MouseButton1;
end;

-- Replaces IsMouseButtonPressed(MouseButton1) in drag loops so they also run while a finger is down.
local function IsHeld()
    for Touch in next, HeldTouches do
        local State = Touch.UserInputState;
        if State ~= Enum.UserInputState.End and State ~= Enum.UserInputState.Cancel then
            return true;
        end;
        HeldTouches[Touch] = nil;
    end;
    return InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1);
end;

-- For tap controls (toggles, buttons, dropdowns, tabs). A mouse click fires at once; a finger fires on release and
-- only if it stayed put, so swiping to scroll the menu no longer switches on everything it started on or passed over.
local TouchStart = {}; -- touch -> where it first went down (set by the InputBegan signal below)
local TAP_SLOP = 10;
local FINGER_CLEARANCE = 48; -- px between a touch and its tooltip, so the fingertip does not cover the text
-- Long press. A finger must rest this long on something before it shows its tooltip or picks a section up to drag:
-- shorter, and both kept going off under taps and scrolling swipes. Once a hold has done that, lifting the finger
-- is no longer a tap (reading a toggle's tooltip must not switch the toggle).
local TOUCH_HOLD = 1;
local LongPressed = {}; -- touch -> true

local function IsTap(Input)
    if Input.UserInputType ~= Enum.UserInputType.Touch then
        return IsClick(Input);
    end;

    IsClick(Input);
    local Start = TouchStart[Input] or Input.Position;

    while Input.UserInputState == Enum.UserInputState.Begin or Input.UserInputState == Enum.UserInputState.Change do
        if (Input.Position - Start).Magnitude > TAP_SLOP or LongPressed[Input] then
            return false;
        end;
        RenderStepped:Wait();
    end;

    return Input.UserInputState == Enum.UserInputState.End and (Input.Position - Start).Magnitude <= TAP_SLOP
        and not LongPressed[Input];
end;

local ProtectGui = protectgui or (syn and syn.protect_gui) or (function() end);

if Library then
    Library:Unload()
end

local ScreenGui = Instance.new('ScreenGui');
ProtectGui(ScreenGui);

ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global;
-- Floating sections (see Library:RegisterSection) each get their own ScreenGui below this one, so the popups they
-- open (dropdown lists, color pickers, tooltips: all in ScreenGui) draw over them.
ScreenGui.DisplayOrder = 1000;
ScreenGui.Parent = CoreGui;

local PanelGuis = {};

local Toggles = {};
local Options = {};

getgenv().Toggles = Toggles;
getgenv().Options = Options;

-- The menu lives in CoreGui, which a thread with game-script identity cannot touch
-- ("The current thread cannot access 'Instance' (lacking capability Plugin)"). That happens when UI
-- setters are called from a game callback: a hooked game function, OnClientEvent, a game-fired signal.
-- A BindableFunction's OnInvoke callback set from THIS thread runs with this thread's identity even when
-- invoked from a low one, and Invoke is always synchronous (unlike BindableEvent handlers, which are
-- queued when the game uses deferred signals). Setters re-dispatch themselves through it when needed
-- (see Library:RunOnUIThread).
local GetThreadIdentity = getthreadidentity or (syn and syn.get_thread_identity) or getidentity;
local UIThreadFunction = Instance.new('BindableFunction');
local UIThreadBypass = false;   -- set while a hop has failed and the call is retried directly, so the guard cannot recurse

UIThreadFunction.OnInvoke = function(Fn, Args)
    local Result = table.pack(pcall(Fn, table.unpack(Args, 1, Args.n)));
    return true, Result;
end;

local Library = {
    Registry = {};
    RegistryMap = {};
    UIThreadFunction = UIThreadFunction;

    HudRegistry = {};

    -- the 'VS Code' theme (ThemeManager.BuiltInThemes), so a menu without the theme manager starts on it too
    FontColor = Color3.fromRGB(204, 204, 204);
    MainColor = Color3.fromRGB(31, 31, 31);
    BackgroundColor = Color3.fromRGB(24, 24, 24);
    AccentColor = Color3.fromRGB(0, 120, 212);
    OutlineColor = Color3.fromRGB(43, 43, 43);
    RiskColor = Color3.fromRGB(255, 50, 50),

    Black = Color3.new(0, 0, 0);
    Font = Enum.Font.Code,

    OpenedFrames = {};
    DependencyBoxes = {};

    Signals = {};
    ScreenGui = ScreenGui;
    PanelGuis = PanelGuis;

    Version = 19;         -- bump when the public API changes; clients check this against the GitHub copy
                          -- 14: AddSlider Info.Format(Value) -> display text
                          -- 15: AddDropdown Info.ValueIcons
                          -- 16: Groupbox:AddIconLabel
    UIScale = 1;          -- window + popup scale, see Library:SetScale
    Popups = {};          -- dropdown lists / color pickers / menus parented to the ScreenGui, scaled with the window
    RainbowSpeed = 1;     -- multiplier for the accent animation speed (hue cycle / custom color flow)
    GradientSpread = 0.35;-- hue range spread across the window when GradientAccent is on (rainbow mode)
    MenuFadeTime = nil;   -- overrides the window's MenuFadeTime when set (seconds)
    GlassTransparency = 0.1;  -- frosted glass: how see-through the window / sections are, with the game blurred
                          -- behind them only (0 = off, solid window). Set before CreateWindow.
    BlurBillboards = true;    -- also blur the game's name tags / damage numbers behind a glass frame
    BlurStrength = 1;         -- 0..1: how strongly the game behind a glass frame is blurred (1 = the effect's most)
    Animations = true;    -- eased UI changes (see Library:CreateTween); false makes everything snap
    LightDrag = true;     -- drag the main window as an outline, move it on release (see Library:MakeDraggable)

    -- Accent gradient options (see Library:GetAccentAt)
    GradientMode = 'Rainbow';          -- 'Rainbow' (hue wheel) or 'Custom' (blend GradientColorA -> GradientColorB)
    GradientDirection = 'Vertical';    -- 'Vertical', 'Horizontal' or 'Diagonal'
    GradientReverse = false;           -- flip the gradient direction
    GradientColorA = Color3.fromRGB(0, 170, 255);
    GradientColorB = Color3.fromRGB(170, 0, 255);
    RainbowSaturation = 0.8;
    RainbowValue = 1;

    -- Window glow (see Library:SetGlow) and per-element glow (toggles, slider fills, color swatches)
    GlowEnabled = false;
    GlowSize = 30;
    GlowTransparency = 0.5;
    ElementGlow = false;
    ElementGlowTransparency = 0.55;
    ElementGlows = {};
};

local RainbowStep = 0
local Hue = 0
local AccentPhase = 0
local LastRainbowAccent = nil
local LastAccentPaint = 0

local function PingPong(X)
    X = X % 1;
    return 1 - math.abs(2 * X - 1);
end;

-- True while the library (not the theme) is driving the accent color.
local function AccentIsDynamic()
    return Library.RainbowAccent or Library.GradientAccent or Library.GradientMode == 'Custom';
end;

table.insert(Library.Signals, InputService.InputChanged:Connect(function(Input)
    if Input.UserInputType == Enum.UserInputType.Touch then
        LastTouch = Input.Position;
    elseif Input.UserInputType == Enum.UserInputType.MouseMovement then
        LastTouch = nil;
    end;
end));

table.insert(Library.Signals, InputService.InputBegan:Connect(function(Input)
    if Input.UserInputType == Enum.UserInputType.Touch then
        TouchStart[Input] = Input.Position;
        LastTouch = Input.Position;

        -- a tooltip pinned by a long press (Library:AddToolTip) goes when a finger lands outside it and its element
        local Pinned = Library.PinnedTooltip;

        if Pinned then
            local function Covers(Frame)
                local Pos, Size = Frame.AbsolutePosition, Frame.AbsoluteSize;
                return Input.Position.X >= Pos.X and Input.Position.X <= Pos.X + Size.X
                    and Input.Position.Y >= Pos.Y and Input.Position.Y <= Pos.Y + Size.Y;
            end;

            if not (Covers(Pinned.Tooltip) or Covers(Pinned.Owner)) then
                Library.PinnedTooltip = nil;
            end;
        end;
    end;
end));

table.insert(Library.Signals, InputService.InputEnded:Connect(function(Input)
    if TouchStart[Input] then
        task.defer(function() TouchStart[Input] = nil; end); -- after the tap handlers have read it
    end;

    if LongPressed[Input] then
        task.delay(0.5, function() LongPressed[Input] = nil; end); -- IsTap reads it a frame after the release
    end;
end));

table.insert(Library.Signals, RenderStepped:Connect(function(Delta)
    RainbowStep = RainbowStep + Delta

    if RainbowStep >= (1 / 60) then
        RainbowStep = 0

        -- Public hue counter (kept for scripts that read CurrentRainbowColor); always cycles.
        Hue = (Hue + (1 / 400)) % 1;
        Library.CurrentRainbowHue = Hue;
        Library.CurrentRainbowColor = Color3.fromHSV(Hue, Library.RainbowSaturation or 0.8, Library.RainbowValue or 1);

        -- Accent animation phase: only advances while RainbowAccent (animate) is on.
        if Library.RainbowAccent then
            AccentPhase = (AccentPhase + (1 / 400) * (Library.RainbowSpeed or 1)) % 1;
        end;
        Library.AccentPhase = AccentPhase;

        if AccentIsDynamic() then
            -- A theme applied while we drive the accent changes AccentColor underneath us; keep that as the restore color.
            if LastRainbowAccent and Library.AccentColor ~= LastRainbowAccent then
                Library.StaticAccentColor = Library.AccentColor;
            end

            Library.AccentColor = Library:GetAccentAt(0);
            Library.AccentColorDark = Library:GetDarkerColor(Library.AccentColor);
            LastRainbowAccent = Library.AccentColor;

            -- Repainting walks the whole registry (every accent element of the window): 20 times a second looks the
            -- same as 60 and costs a third. While the menu is hidden only the HUD pieces (watermark, keybind list,
            -- notifications) need recoloring.
            local Now = os.clock();
            if Now - LastAccentPaint >= 0.05 then
                LastAccentPaint = Now;
                local Hidden = Library.MainWindow and not Library.MainWindow.Visible;
                Library:UpdateAccentColors(Hidden and Library.HudRegistry or nil);
            end;
        end
    end
end))

-- Accent color at a position along the gradient (0 = start, 1 = end).
--   Rainbow mode: hue = phase - Fraction * GradientSpread (so the hue wheel is spread across the window).
--   Custom mode:  blend GradientColorA -> GradientColorB; with animation on, the blend flows across the window.
-- Without GradientAccent every element uses Fraction 0, i.e. one flat (possibly animated) color.
-- Every animation in the library goes through here. With Library.Animations off it returns a stand-in whose
-- Play applies the goal at once, so callers never need two code paths.
function Library:CreateTween(Instance, Info, Goal)
    if Library.Animations then
        return TweenService:Create(Instance, Info, Goal);
    end;

    return {
        Play = function()
            for Property, Value in next, Goal do
                Instance[Property] = Value;
            end;
        end;
        Cancel = function() end;
    };
end;

-- Time-and-goal shorthand for one eased change (Quad, Out).
function Library:Animate(Instance, Time, Goal)
    local Tween = Library:CreateTween(Instance, TweenInfo.new(Time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), Goal);
    Tween:Play();
    return Tween;
end;

function Library:GetAccentAt(Fraction)
    local Gradient = Library.GradientAccent;

    if not Gradient then
        Fraction = 0;
    elseif Library.GradientReverse then
        Fraction = 1 - Fraction;
    end;

    if Library.GradientMode == 'Custom' then
        local A, B = Library.GradientColorA or Library.AccentColor, Library.GradientColorB or Library.AccentColor;
        local T = Fraction;

        if Library.RainbowAccent then
            T = PingPong(Fraction * (Gradient and 1 or 0) + AccentPhase);
        end;

        return A:Lerp(B, T);
    end;

    local H = AccentPhase - Fraction * (Library.GradientSpread or 0.35);
    return Color3.fromHSV(H % 1, Library.RainbowSaturation or 0.8, Library.RainbowValue or 1);
end;

-- Position of an element inside the main window (0..1) along the configured gradient direction.
function Library:GetGradientFraction(Instance)
    local Holder = Library.MainWindow;

    if not Holder then
        return 0;
    end;

    -- UIStroke / UICorner / UIGradient have no screen position of their own; use the element they decorate.
    -- (An unguarded stroke here used to error and abort the whole per-frame recolor, freezing the gradient.)
    if not Instance:IsA('GuiObject') then
        Instance = Instance.Parent;

        if not (Instance and Instance:IsA('GuiObject')) then
            return 0;
        end;
    end;

    local Pos, Size = Holder.AbsolutePosition, Holder.AbsoluteSize;
    local FX = math.clamp((Instance.AbsolutePosition.X - Pos.X) / math.max(Size.X, 1), 0, 1);
    local FY = math.clamp((Instance.AbsolutePosition.Y - Pos.Y) / math.max(Size.Y, 1), 0, 1);
    local Direction = Library.GradientDirection;

    if Direction == 'Horizontal' then
        return FX;
    elseif Direction == 'Diagonal' then
        return (FX + FY) / 2;
    end;

    return FY;
end;

-- Recolors only the accent-bound registry entries. With GradientAccent on, each element gets the accent
-- color for its position inside the main window (see GetAccentAt / GetGradientFraction).
function Library:UpdateAccentColors(List)
    local Gradient = Library.GradientAccent;

    for _, Object in next, (List or Library.Registry) do
        for Property, ColorIdx in next, Object.Properties do
            if ColorIdx == 'AccentColor' or ColorIdx == 'AccentColorDark' then
                local Color = Library.AccentColor;

                if Gradient then
                    local Ok, Fraction = pcall(Library.GetGradientFraction, Library, Object.Instance);
                    Color = Library:GetAccentAt(Ok and Fraction or 0);
                end

                if ColorIdx == 'AccentColorDark' then
                    Color = Library:GetDarkerColor(Color);
                end

                -- one bad entry must not stop the rest of the window from recoloring
                pcall(function()
                    Object.Instance[Property] = Color;
                end);
            end
        end
    end

    if Library.WindowBorderGradient and (not List) then
        local Direction = Library.GradientDirection;
        Library.WindowBorderGradient.Rotation = (Direction == 'Horizontal' and 0) or (Direction == 'Diagonal' and 45) or 90;
        Library.WindowBorderGradient.Color = Library:GetAccentSequence();
    end;
end

-- ColorSequence matching the current accent: a flat accent color normally, or the start-to-end color range
-- while the gradient accent is active. Used for the window border gradient.
function Library:GetAccentSequence()
    if not Library.GradientAccent then
        return ColorSequence.new(Library.AccentColor);
    end;

    local Keypoints = {};
    local Steps = 8;

    for i = 0, Steps do
        local t = i / Steps;
        table.insert(Keypoints, ColorSequenceKeypoint.new(t, Library:GetAccentAt(t)));
    end;

    return ColorSequence.new(Keypoints);
end;

-- Cycles the accent color through the hue wheel (toggles, sliders, groupbox highlights, etc.)
-- Pass Gradient = true to spread the hue down the window instead of coloring everything the same.
function Library:SetRainbowAccent(Bool, Gradient)
    Library.RainbowAccent = (not not Bool);
    Library.GradientAccent = (not not Gradient);
    Library:RefreshAccent();
end

-- Call after changing GradientMode / colors / direction so a static (non-animated) accent repaints,
-- and so the theme accent comes back when nothing dynamic is left on.
function Library:RefreshAccent()
    LastRainbowAccent = nil;

    if AccentIsDynamic() then
        Library.StaticAccentColor = Library.StaticAccentColor or Library.AccentColor;
    else
        Library.AccentColor = Library.StaticAccentColor or Library.AccentColor;
        Library.AccentColorDark = Library:GetDarkerColor(Library.AccentColor);
        Library:UpdateColorsUsingRegistry();
    end
end

local function GetPlayersString()
    local PlayerList = Players:GetPlayers();

    for i = 1, #PlayerList do
        PlayerList[i] = PlayerList[i].Name;
    end;

    table.sort(PlayerList, function(str1, str2) return str1 < str2 end);

    return PlayerList;
end;

local function GetTeamsString()
    local TeamList = Teams:GetTeams();

    for i = 1, #TeamList do
        TeamList[i] = TeamList[i].Name;
    end;

    table.sort(TeamList, function(str1, str2) return str1 < str2 end);
    
    return TeamList;
end;

-- True when the calling thread lacks the identity needed to touch the menu (see UIThreadFunction above).
function Library:NeedsUIThread()
    if UIThreadBypass or type(GetThreadIdentity) ~= 'function' then
        return false;
    end;

    local Ok, Identity = pcall(GetThreadIdentity);
    return Ok and type(Identity) == 'number' and Identity < 4;
end;

-- Runs Fn(...) on the library's own (executor-identity) thread, synchronously, and returns its results.
-- Use this around any menu update made from a game callback.
function Library:RunOnUIThread(Fn, ...)
    if not Library:NeedsUIThread() then
        return Fn(...);
    end;

    local Args = table.pack(...);
    local Invoked, Ran, Result = pcall(UIThreadFunction.Invoke, UIThreadFunction, Fn, Args);

    if not (Invoked and Ran and type(Result) == 'table') then
        -- The hop is unavailable (library unloaded, executor cannot pass functions through bindables, ...):
        -- run directly with the guard bypassed so this can never re-enter itself.
        UIThreadBypass = true;
        Result = table.pack(pcall(Fn, table.unpack(Args, 1, Args.n)));
        UIThreadBypass = false;
    end;

    if not Result[1] then
        error(Result[2], 0);
    end;

    return table.unpack(Result, 2, Result.n);
end;

function Library:SafeCallback(f, ...)
    if (not f) then
        return;
    end;

    if not Library.NotifyOnError then
        return f(...);
    end;

    local success, event = pcall(f, ...);

    if not success then
        local _, i = event:find(":%d+: ");

        if not i then
            return Library:Notify(event);
        end;

        return Library:Notify(event:sub(i + 1), 3);
    end;
end;

function Library:AttemptSave()
    if Library.SaveManager then
        Library.SaveManager:Save();
    end;
end;

function Library:Create(Class, Properties)
    local _Instance = Class;

    if type(Class) == 'string' then
        _Instance = Instance.new(Class);
    end;

    for Property, Value in next, Properties do
        _Instance[Property] = Value;
    end;

    return _Instance;
end;

function Library:ApplyTextStroke(Inst)
    Inst.TextStrokeTransparency = 1;

    Library:Create('UIStroke', {
        Color = Color3.new(0, 0, 0);
        Thickness = 1;
        LineJoinMode = Enum.LineJoinMode.Miter;
        Parent = Inst;
    });
end;

function Library:CreateLabel(Properties, IsHud)
    local _Instance = Library:Create('TextLabel', {
        BackgroundTransparency = 1;
        Font = Library.Font;
        TextColor3 = Library.FontColor;
        TextSize = 16;
        TextStrokeTransparency = 0;
    });

    Library:ApplyTextStroke(_Instance);

    Library:AddToRegistry(_Instance, {
        TextColor3 = 'FontColor';
    }, IsHud);

    return Library:Create(_Instance, Properties);
end;

-- Product of the UIScales above a frame: screen pixels per one unit of its Position offset.
local function ParentScaleOf(Frame)
    local Scale, Parent = 1, Frame.Parent;
    while Parent and Parent:IsA('GuiObject') do
        local UIScale = Parent:FindFirstChildOfClass('UIScale');
        if UIScale then Scale = Scale * UIScale.Scale; end;
        Parent = Parent.Parent;
    end;
    return math.max(Scale, 0.001);
end;

-- Frames the user places by hand (window, watermark, keybind list, floating sections). When the game window
-- shrinks they are pulled back inside it; the top-left corner wins when a frame is larger than the screen. Each
-- remembers where it was put (Home) and goes back there as the screen grows, until something else moves it.
local Kept = {}; -- Frame -> { Home = position before it was pulled in, Set = position it was pulled to }

function Library:KeepOnScreen(Frame)
    local Entry = Kept[Frame] or {};
    Kept[Frame] = Entry;
    if Entry.Set ~= Frame.Position then Entry.Home = nil; end; -- dragged or reset since: that is the new home

    local Home, Scale = Entry.Home or Frame.Position, ParentScaleOf(Frame);
    local Back = Home - Frame.Position; -- only offsets differ (pulling in adds offsets)
    local View, Size = ScreenGui.AbsoluteSize, Frame.AbsoluteSize;
    local Pos = Frame.AbsolutePosition + Vector2.new(Back.X.Offset, Back.Y.Offset) * Scale; -- where Home sits now
    -- floor: positions land on whole pixels, so a fractional size (UI scale 1.25) would poke out by under a pixel
    local X = math.clamp(Pos.X, 0, math.max(math.floor(View.X - Size.X), 0)) - Pos.X;
    local Y = math.clamp(Pos.Y, 0, math.max(math.floor(View.Y - Size.Y), 0)) - Pos.Y;

    if X == 0 and Y == 0 then
        Frame.Position = Home;
        Entry.Home, Entry.Set = nil, nil;
        return;
    end;
    Frame.Position = Home + UDim2.fromOffset(X / Scale, Y / Scale);
    Entry.Home, Entry.Set = Home, Frame.Position;
end;

ScreenGui:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()
    task.defer(function() -- frames are laid out against the new size after this signal
        for Frame in next, Kept do
            if Frame.Parent then Library:KeepOnScreen(Frame); else Kept[Frame] = nil; end;
        end;
    end);
end);

-- Ghostable: with Library.LightDrag on, an accent outline follows the cursor and the frame moves once on release.
-- Moving the main window drags its whole tree (hidden tab pages included) through layout every frame; measured
-- ~1.2-1.9 ms a frame on a fast PC, while the outline costs nothing.
function Library:MakeDraggable(Instance, Cutoff, Ghostable)
    Instance.Active = true;
    local Binding = 'LinoriaDrag_' .. game:GetService('HttpService'):GenerateGUID(false);
    local Dragging, Moved = false, false;
    local StartMouse, StartPosition, ParentScale;
    local Ghost, Light = nil, false;
    Kept[Instance] = {};

    -- PlayerMouse stops updating while the Roblox ESC menu is open; GetMouseLocation does not (only deltas are used).
    local function Cursor()
        if LastTouch then return Vector2.new(LastTouch.X, LastTouch.Y); end;
        return InputService:GetMouseLocation();
    end;

    local function Update()
        local Point = Cursor();
        local X, Y = (Point.X - StartMouse.X) / ParentScale, (Point.Y - StartMouse.Y) / ParentScale;
        if X ~= 0 or Y ~= 0 then Moved = true; end;
        -- Preserve scale coordinates and anchors; only add the cursor delta.
        (Light and Ghost or Instance).Position = UDim2.new(
            StartPosition.X.Scale, StartPosition.X.Offset + X,
            StartPosition.Y.Scale, StartPosition.Y.Offset + Y
        );
    end;

    -- Same box as the frame: same parent, anchor and position, size without the frame's own UIScale applied twice.
    local function ShowGhost()
        if not Ghost then
            Ghost = Library:Create('Frame', {
                Name = 'DragGhost';
                BackgroundTransparency = 1;
                ZIndex = 1000;
            });
            local Stroke = Library:Create('UIStroke', {
                Thickness = 2;
                Color = Library.AccentColor;
                Parent = Ghost;
            });
            Library:AddToRegistry(Stroke, { Color = 'AccentColor' });
        end;
        Ghost.AnchorPoint = Instance.AnchorPoint;
        Ghost.Size = UDim2.fromOffset(Instance.AbsoluteSize.X / ParentScale, Instance.AbsoluteSize.Y / ParentScale);
        Ghost.Position = Instance.Position;
        Ghost.Parent = Instance.Parent;
        Ghost.Visible = true;
    end;

    local function Stop(Save)
        if not Dragging then return; end;
        if Save and Instance.Parent then Update(); end;
        Dragging = false;
        RunService:UnbindFromRenderStep(Binding);
        if Light and Ghost then
            if Save and Moved and Instance.Parent then
                Instance.Position = Ghost.Position;
            end;
            Ghost.Visible = false;
        end;
        if Save and Moved then Library:AttemptSave(); end;
    end;

    local function Step()
        if not Instance.Parent then Stop(false); return; end;
        -- shortcut: IsMouseButtonPressed is unverified while the ESC menu is open, so rely on InputEnded there.
        if not GuiService.MenuIsOpen and not IsHeld() then Stop(true); return; end;
        Update();
    end;

    local function Shown()
        local Node = Instance;
        while Node and Node:IsA('GuiObject') do
            if not Node.Visible then return false; end;
            Node = Node.Parent;
        end;
        return Node ~= nil and (not Node:IsA('LayerCollector') or Node.Enabled);
    end;

    local function Begin(Input, HitTest)
        if not IsClick(Input) or Dragging then return; end;
        local Pos, Abs, Size = Input.Position, Instance.AbsolutePosition, Instance.AbsoluteSize;
        if HitTest and (not Shown() or Pos.X < Abs.X or Pos.X > Abs.X + Size.X) then return; end;
        ParentScale = ParentScaleOf(Instance);
        local OwnScale = Instance:FindFirstChildOfClass('UIScale');
        local HeaderScale = ParentScale * (OwnScale and OwnScale.Scale or 1);
        local HeaderY = Pos.Y - Abs.Y;
        if HeaderY < 0 or HeaderY > (Cutoff or 40) * HeaderScale then return; end;
        StartMouse, StartPosition = Cursor(), Instance.Position;
        Dragging, Moved = true, false;
        Light = Ghostable == true and Library.LightDrag ~= false;
        if Light then ShowGhost(); end;
        -- Fresh input, once per rendered frame, before camera/UI rendering. No chase tween.
        RunService:BindToRenderStep(Binding, Enum.RenderPriority.Input.Value + 1, function()
            Library:RunOnUIThread(Step);
        end);
    end;

    Instance.InputBegan:Connect(function(Input) Begin(Input, false); end);
    -- The ESC menu sinks GUI input, so Instance.InputBegan never fires while it is open; hit-test by hand instead.
    local MenuConnection = InputService.InputBegan:Connect(function(Input)
        if GuiService.MenuIsOpen then Library:RunOnUIThread(Begin, Input, true); end;
    end);
    Library:GiveSignal(MenuConnection);
    local EndConnection = InputService.InputEnded:Connect(function(Input)
        if IsClick(Input) then Library:RunOnUIThread(Stop, true); end;
    end);
    local FocusConnection = InputService.WindowFocusReleased:Connect(function() Library:RunOnUIThread(Stop, true); end);
    Library:GiveSignal(EndConnection);
    Library:GiveSignal(FocusConnection);
    Instance.Destroying:Connect(function()
        Stop(false);
        MenuConnection:Disconnect();
        EndConnection:Disconnect();
        FocusConnection:Disconnect();
        if Ghost then Ghost:Destroy(); end;
    end);
    Library:GiveSignal({ Disconnect = function() Stop(false); end });
end;

function Library:AddToolTip(InfoStr, HoverInstance, AllowOpenedFrame)
    -- Long tooltips wrap at 300 px instead of running off the edge of the screen.
    local X, Y = 1, 1;
    local Tooltip = Library:Create('Frame', {
        Name = 'Tooltip',
        BackgroundColor3 = Library.MainColor,
        BorderColor3 = Library.OutlineColor,

        Size = UDim2.fromOffset(X + 5, Y + 4),
        ZIndex = 100,
        Parent = Library.ScreenGui,

        Visible = false,
    })

    local Label = Library:CreateLabel({
        Position = UDim2.fromOffset(3, 1),
        Size = UDim2.fromOffset(X, Y);
        TextSize = 14;
        Text = '',
        TextColor3 = Library.FontColor,
        TextWrapped = true;
        TextXAlignment = Enum.TextXAlignment.Left;
        ZIndex = Tooltip.ZIndex + 1,

        Parent = Tooltip;
    });

    Library:AddToRegistry(Tooltip, {
        BackgroundColor3 = 'MainColor';
        BorderColor3 = 'OutlineColor';
    });

    Library:AddToRegistry(Label, {
        TextColor3 = 'FontColor',
    });

    local IsHovering = false
    local HoverSerial = 0
    local LastText

    local function UpdateText()
        local Text = InfoStr
        if type(Text) == 'function' then
            local Ok, Result = pcall(Text)
            Text = Ok and Result or nil
        end
        if type(Text) ~= 'string' or Text == '' then return false end
        if Text ~= LastText then
            LastText = Text
            local Width, Height = Library:GetTextBounds(Text, Library.Font, 14, Vector2.new(300, math.huge))
            Tooltip.Size = UDim2.fromOffset(Width + 8, Height + 6)
            Label.Size = UDim2.fromOffset(Width, Height)
            Label.Text = Text
        end
        return true
    end

    local function IsShown()
        local Object = HoverInstance
        while Object do
            if Object:IsA('GuiObject') and not Object.Visible then return false end
            if Object:IsA('ScreenGui') and not Object.Enabled then return false end
            Object = Object.Parent
        end
        return HoverInstance.Parent ~= nil
    end

    -- Mouse: right of and below the cursor, flipped to the other side of the cursor when that would run past the
    -- screen edge. Finger: centred above the touch point (below it only when there is no room), since the fingertip
    -- covers everything right under it. Then clamped so it is always fully on screen.
    local function PlaceTooltip(Touch)
        local Screen = Library.ScreenGui.AbsoluteSize;
        local Width, Height = Tooltip.AbsoluteSize.X, Tooltip.AbsoluteSize.Y;
        local PosX, PosY;

        if Touch then
            PosX = Touch.X - Width / 2;
            PosY = Touch.Y - FINGER_CLEARANCE - Height;
            if PosY < 4 then
                PosY = Touch.Y + FINGER_CLEARANCE;
            end;
        else
            PosX, PosY = Mouse.X + 15, Mouse.Y + 12;

            if PosX + Width > Screen.X - 4 then
                PosX = Mouse.X - 10 - Width;
            end;

            if PosY + Height > Screen.Y - 4 then
                PosY = Mouse.Y - 6 - Height;
            end;
        end;

        PosX = math.clamp(PosX, 4, math.max(4, Screen.X - Width - 4));
        PosY = math.clamp(PosY, 4, math.max(4, Screen.Y - Height - 4));
        Tooltip.Position = UDim2.fromOffset(PosX, PosY);
    end;

    -- Shows the tooltip while StillOn() holds; Where() gives the touch point (nil = follow the mouse).
    local function ShowWhile(StillOn, Where)
        if not AllowOpenedFrame and Library:MouseIsOverOpenedFrame() then
            return
        end

        IsHovering = true
        HoverSerial = HoverSerial + 1
        local Serial = HoverSerial
        while IsHovering and HoverSerial == Serial and Tooltip.Parent and IsShown() do
            Tooltip.Visible = UpdateText()
            if not StillOn() then break end
            PlaceTooltip(Where and Where())
            RunService.Heartbeat:Wait()
        end
        if HoverSerial == Serial then
            IsHovering = false
            if Tooltip.Parent then Tooltip.Visible = false end
        end
    end

    HoverInstance.MouseEnter:Connect(function()
        if LastTouch or IsMobile then
            return -- a finger: the InputBegan handler below shows it after a long press
        end
        ShowWhile(function() return Library:IsMouseOverFrame(HoverInstance) end)
    end)

    -- Touch: a finger resting on the element for TOUCH_HOLD seconds shows it (a tap or a scrolling swipe never does).
    -- It then stays up, above where the finger was, also once the finger is lifted: until a touch lands outside the
    -- element and the tooltip (the InputBegan signal at the top), or another tooltip is pinned.
    HoverInstance.InputBegan:Connect(function(Input)
        if Input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end

        local Start, Began = Input.Position, os.clock()
        while os.clock() - Began < TOUCH_HOLD do
            local State = Input.UserInputState
            if (State ~= Enum.UserInputState.Begin and State ~= Enum.UserInputState.Change)
                or (Input.Position - Start).Magnitude > TAP_SLOP then
                return
            end
            RenderStepped:Wait()
        end

        if (not AllowOpenedFrame and Library:MouseIsOverOpenedFrame()) or not UpdateText() then
            return -- nothing to show: the hold stays an ordinary tap
        end

        LongPressed[Input] = true
        local Pin = { Tooltip = Tooltip, Owner = HoverInstance }
        local Point = Vector2.new(Start.X, Start.Y)
        Library.PinnedTooltip = Pin
        ShowWhile(function() return Library.PinnedTooltip == Pin end, function() return Point end)

        if Library.PinnedTooltip == Pin then
            Library.PinnedTooltip = nil -- it went for another reason (the menu was hidden)
        end
    end)

    HoverInstance.MouseLeave:Connect(function()
        if LastTouch then
            return -- a pinned touch tooltip ends with a touch outside it, not on the leave a release fires
        end
        HoverSerial = HoverSerial + 1
        IsHovering = false
        Tooltip.Visible = false
    end)
    return Tooltip
end

function Library:OnHighlight(HighlightInstance, Instance, Properties, PropertiesDefault)
    -- hover colors ease in and out (Library.Animations)
    HighlightInstance.MouseEnter:Connect(function()
        local Reg = Library.RegistryMap[Instance];

        for Property, ColorIdx in next, Properties do
            Library:Animate(Instance, 0.1, { [Property] = Library[ColorIdx] or ColorIdx });

            if Reg and Reg.Properties[Property] then
                Reg.Properties[Property] = ColorIdx;
            end;
        end;
    end)

    HighlightInstance.MouseLeave:Connect(function()
        local Reg = Library.RegistryMap[Instance];

        for Property, ColorIdx in next, PropertiesDefault do
            Library:Animate(Instance, 0.15, { [Property] = Library[ColorIdx] or ColorIdx });

            if Reg and Reg.Properties[Property] then
                Reg.Properties[Property] = ColorIdx;
            end;
        end;
    end)
end;

function Library:MouseIsOverOpenedFrame()
    for Frame, _ in next, Library.OpenedFrames do
        local AbsPos, AbsSize = Frame.AbsolutePosition, Frame.AbsoluteSize;

        if Mouse.X >= AbsPos.X and Mouse.X <= AbsPos.X + AbsSize.X
            and Mouse.Y >= AbsPos.Y and Mouse.Y <= AbsPos.Y + AbsSize.Y then

            return true;
        end;
    end;
end;

function Library:IsMouseOverFrame(Frame)
    local AbsPos, AbsSize = Frame.AbsolutePosition, Frame.AbsoluteSize;

    if Mouse.X >= AbsPos.X and Mouse.X <= AbsPos.X + AbsSize.X
        and Mouse.Y >= AbsPos.Y and Mouse.Y <= AbsPos.Y + AbsSize.Y then

        return true;
    end;
end;

function Library:UpdateDependencyBoxes()
    for _, Depbox in next, Library.DependencyBoxes do
        Depbox:Update();
    end;
end;

function Library:MapValue(Value, MinA, MaxA, MinB, MaxB)
    return (1 - ((Value - MinA) / (MaxA - MinA))) * MinB + ((Value - MinA) / (MaxA - MinA)) * MaxB;
end;

-- Extra height for a wrapped label sized to its measured text. While a UIScale eases to its end value (the menu's
-- and a dialog's zoom) Roblox lays the lines out in a box a fraction of a pixel short of them and drops the last
-- line, then keeps that layout: the box reaches its full size without changing by a whole pixel. Live: last line
-- missing after 9 of 10 menu opens, none with 1 px to spare.
local WRAP_SLACK = 1;

function Library:GetTextBounds(Text, Font, Size, Resolution)
    local Bounds = TextService:GetTextSize(Text, Size, Font, Resolution or Vector2.new(1920, 1080))
    return Bounds.X, Bounds.Y
end;

function Library:GetDarkerColor(Color)
    local H, S, V = Color3.toHSV(Color);
    return Color3.fromHSV(H, S, V / 1.5);
end;
Library.AccentColorDark = Library:GetDarkerColor(Library.AccentColor);

function Library:AddToRegistry(Instance, Properties, IsHud)
    local Idx = #Library.Registry + 1;
    local Data = {
        Instance = Instance;
        Properties = Properties;
        Idx = Idx;
    };

    table.insert(Library.Registry, Data);
    Library.RegistryMap[Instance] = Data;

    if IsHud then
        table.insert(Library.HudRegistry, Data);
    end;
end;

function Library:RemoveFromRegistry(Instance)
    local Data = Library.RegistryMap[Instance];

    if Data then
        for Idx = #Library.Registry, 1, -1 do
            if Library.Registry[Idx] == Data then
                table.remove(Library.Registry, Idx);
            end;
        end;

        for Idx = #Library.HudRegistry, 1, -1 do
            if Library.HudRegistry[Idx] == Data then
                table.remove(Library.HudRegistry, Idx);
            end;
        end;

        Library.RegistryMap[Instance] = nil;
    end;
end;

function Library:UpdateColorsUsingRegistry()
    -- TODO: Could have an 'active' list of objects
    -- where the active list only contains Visible objects.

    -- IMPL: Could setup .Changed events on the AddToRegistry function
    -- that listens for the 'Visible' propert being changed.
    -- Visible: true => Add to active list, and call UpdateColors function
    -- Visible: false => Remove from active list.

    -- The above would be especially efficient for a rainbow menu color or live color-changing.

    for Idx, Object in next, Library.Registry do
        for Property, ColorIdx in next, Object.Properties do
            if type(ColorIdx) == 'string' then
                Object.Instance[Property] = Library[ColorIdx];
            elseif type(ColorIdx) == 'function' then
                Object.Instance[Property] = ColorIdx()
            end
        end;
    end;
end;

function Library:GiveSignal(Signal)
    -- Only used for signals not attached to library instances, as those should be cleaned up on object destruction by Roblox
    table.insert(Library.Signals, Signal)
end

-- Frosted glass behind translucent frames. DepthOfField blurs whatever is nearer than its focus range and Glass parts
-- write depth, so a near-invisible Glass part held 1 stud in front of the camera blurs exactly the screen rectangle
-- it covers. Shown() returns (frame is on screen, blur wanted): the blur eases out while a closing menu still fades.
local GlassFrames = {};
local GLASS_DEPTH = 1.5;       -- studs from the camera; the blur's focus range starts at 2.5 (NewBlur)
local BILLBOARD_DEPTH = 1.1;   -- where blurred billboards are held: Roblox draws none nearer than 0.8 studs

-- A game can destroy either one at any time (a map load clears Lighting, a respawn replaces the camera), and a
-- destroyed instance cannot be parented again: UpdateGlass then makes a fresh one.
local function NewBlur(NearIntensity)
    local Blur = Instance.new('DepthOfFieldEffect');
    Blur.Name = 'LinoriaBlur';
    Blur.FarIntensity = 0;
    Blur.FocusDistance = 52.5;
    Blur.InFocusRadius = 50;
    Blur.NearIntensity = NearIntensity;
    Blur.Parent = game:GetService('Lighting');
    Library.Blur = Blur;
    return Blur;
end;

local function NewGlassPart()
    local Part = Instance.new('Part');
    Part.Anchored = true;
    Part.CanCollide = false;
    Part.CanQuery = false;
    Part.CanTouch = false;
    Part.CastShadow = false;
    Part.Material = Enum.Material.Glass;
    Part.Transparency = 0.98;
    return Part;
end;

-- Blurring the game's billboards (name tags, health bars, damage numbers) through the glass. Drawn AlwaysOnTop they
-- go on screen after the post effects and stay sharp. In the 3D pass the blur does reach them, but one behind the
-- Glass part is not drawn at all. So while a glass frame is shown (Library.BlurBillboards) each AlwaysOnTop billboard
-- behind one is moved into the 3D pass and held BILLBOARD_DEPTH studs from the camera, in front of the glass: re-adorned
-- to a proxy part on the line from the camera to its real adornee, with the proxy's size and the billboard's stud
-- offsets and stud size all scaled by the same factor, which leaves it exactly where and as large as it was on
-- screen. Over a glass frame it then blurs with the scene; anywhere else it looks as before. All tested live with
-- own billboards, 2026-11-21.
-- Only a billboard that is behind a glass frame on screen is held. In the 3D pass a billboard takes every post
-- effect the game runs, wherever it is: with all of them held, the game's own full-screen blur (the one it turns on
-- behind its windows) smeared every name tag and message on screen while the menu was open (live, 2026-11-22).
-- (A plain table: with weak keys the entries of live GUIs were collected, and those were never put back.)
local Billboards, BillboardSignals, BillboardsOn = {}, {}, false; -- [Gui] = { Held, what the game set, what was written }
local HOLD_MARGIN = 30; -- px around a glass frame that still counts as behind it (twice that to be let go again)

local function TrackBillboard(Gui)
    if Gui:IsA('BillboardGui') and Gui.AlwaysOnTop and not Billboards[Gui] then
        Billboards[Gui] = {}; -- left as it is until HoldBillboards finds it behind a glass frame
    end;
end;

-- Back to how the game had it; still tracked.
local function LetGo(Gui, Data)
    if Data.Held then
        Data.Held = false;

        if Gui.Parent then
            Gui.Adornee = Data.Adornee;
            Gui.StudsOffset = Data.Offset;
            Gui.StudsOffsetWorldSpace = Data.World;
            Gui.Size = Data.Size;
            Gui.AlwaysOnTop = true;
        end;
    end;

    if Data.Proxy then
        Data.Proxy:Destroy();
        Data.Proxy = nil;
    end;
end;

local function ReleaseBillboard(Gui, Data)
    Billboards[Gui] = nil;
    LetGo(Gui, Data);
end;

-- Every frame, after the camera has moved (UpdateGlass). Rects: the glass frames on screen, { X0, Y0, X1, Y1 } in
-- viewport px.
local function HoldBillboards(Camera, Rects)
    local Eye = Camera.CFrame;

    for Gui, Data in next, Billboards do
        if Data.Held then
            -- whatever is not what was written last frame is the game's own (new) value
            if Gui.Adornee ~= Data.Proxy then Data.Adornee = Gui.Adornee; end;
            if Gui.StudsOffset ~= Data.SetOffset then Data.Offset = Gui.StudsOffset; end;
            if Gui.StudsOffsetWorldSpace ~= Data.SetWorld then Data.World = Gui.StudsOffsetWorldSpace; end;
            if Gui.Size ~= Data.SetSize then Data.Size = Gui.Size; end;
        elseif not Gui.AlwaysOnTop then
            Billboards[Gui] = nil; -- the game has put it in the scene itself: no longer one of these
            continue;
        else
            Data.Adornee, Data.Offset, Data.World, Data.Size = Gui.Adornee, Gui.StudsOffset, Gui.StudsOffsetWorldSpace, Gui.Size;
        end;

        local Target = Data.Adornee or Gui.Parent;
        local Place = Target and (Target:IsA('BasePart') and Target.CFrame or Target:IsA('Attachment') and Target.WorldCFrame);

        if not (Gui.Parent and Place) then -- destroyed, or adorned to something this cannot follow
            ReleaseBillboard(Gui, Data);
            continue;
        end;

        -- where it is on screen (its middle, near enough, and its size in px): behind a glass frame?
        local Point = Camera:WorldToViewportPoint(Place.Position + Place:VectorToWorldSpace(Data.World) + Eye:VectorToWorldSpace(Data.Offset));
        local Half = Gui.AbsoluteSize / 2;
        local Margin = Data.Held and HOLD_MARGIN * 2 or HOLD_MARGIN;
        local Behind = false;

        if Point.Z > 0 then
            for _, Rect in next, Rects do
                if Point.X + Half.X >= Rect[1] - Margin and Point.X - Half.X <= Rect[3] + Margin
                    and Point.Y + Half.Y >= Rect[2] - Margin and Point.Y - Half.Y <= Rect[4] + Margin then

                    Behind = true;
                    break;
                end;
            end;
        end;

        if not Behind then
            LetGo(Gui, Data);
            continue;
        end;

        if not Data.Held then
            Data.Held = true;
            Gui.AlwaysOnTop = false;
        end;

        -- the billboard's own depth, near enough: its adornee's, moved by the two stud offsets
        local Depth = -Eye:PointToObjectSpace(Place.Position + Place:VectorToWorldSpace(Data.World)).Z - Data.Offset.Z;
        local Scale = Depth > GLASS_DEPTH and BILLBOARD_DEPTH / Depth or 1; -- already in front of the glass: as is

        if (Place.Position - Eye.Position).Magnitude > Gui.MaxDistance then
            Scale = 1; -- too far to be shown: left at its real distance, where Roblox hides it itself
        end;

        if not Data.Proxy or Data.Proxy.Parent ~= Camera then -- first frame, or it went with a replaced camera
            if Data.Proxy then
                Data.Proxy:Destroy();
            end;

            Data.Proxy = Instance.new('Part');
            Data.Proxy.Anchored = true;
            Data.Proxy.CanCollide = false;
            Data.Proxy.CanQuery = false;
            Data.Proxy.CanTouch = false;
            Data.Proxy.CastShadow = false;
            Data.Proxy.Transparency = 1;
            Data.Proxy.Parent = Camera;
        end;

        Data.Proxy.Size = (Target:IsA('BasePart') and Target.Size or Vector3.zero) * Scale;
        Data.Proxy.CFrame = Place.Rotation + Eye.Position + (Place.Position - Eye.Position) * Scale;

        Gui.Adornee = Data.Proxy;
        Gui.StudsOffset = Data.Offset * Scale;
        Gui.StudsOffsetWorldSpace = Data.World * Scale;
        Gui.Size = UDim2.new(Data.Size.X.Scale * Scale, Data.Size.X.Offset, Data.Size.Y.Scale * Scale, Data.Size.Y.Offset);
        -- read back, so next frame's comparison is against exactly what the property holds
        Data.SetOffset, Data.SetWorld, Data.SetSize = Gui.StudsOffset, Gui.StudsOffsetWorldSpace, Gui.Size;
    end;
end;

local function SetBillboardBlur(On)
    BillboardsOn = On;

    if On then
        for _, Root in next, { workspace, LocalPlayer:FindFirstChildOfClass('PlayerGui') } do
            for _, Gui in next, Root:GetDescendants() do
                TrackBillboard(Gui);
            end;

            table.insert(BillboardSignals, Root.DescendantAdded:Connect(TrackBillboard)); -- ones made meanwhile
        end;

        return;
    end;

    for _, Signal in next, BillboardSignals do
        Signal:Disconnect();
    end;
    table.clear(BillboardSignals);

    for Gui, Data in next, Billboards do
        ReleaseBillboard(Gui, Data);
    end;
end;

local function UpdateGlass(Delta)
    local Camera = workspace.CurrentCamera;
    local Blur = Library.Blur;
    local Wanted = false;
    local Rects = {}; -- the glass frames on screen, for HoldBillboards

    if not Blur.Parent then
        Blur = NewBlur(Blur.NearIntensity);
    end;

    for Frame, Glass in next, GlassFrames do
        if not Frame.Parent then -- destroyed with its window / panel
            Glass.Part:Destroy();
            GlassFrames[Frame] = nil;
            continue;
        end;

        local Visible, Want = Glass.Shown();
        if Library.GlassTransparency <= 0 then -- solid menu (Library:SetGlassTransparency): nothing shows through
            Visible, Want = false, false;
        end;
        Wanted = Wanted or Want;
        local Parent = Visible and Camera or nil;
        if Glass.Part.Parent ~= Parent and not pcall(function() Glass.Part.Parent = Parent; end) then
            Glass.Part = NewGlassPart(); -- the old one went with a destroyed camera
            Glass.Part.Parent = Parent;
        end;

        if Visible and Camera then
            local Size = Frame.AbsoluteSize;
            local PerPixel = math.tan(math.rad(Camera.FieldOfView) / 2) * GLASS_DEPTH * 2 / Camera.ViewportSize.Y;
            local Corner = Frame.AbsolutePosition + GuiService:GetGuiInset();
            local Center = Corner + Size / 2 - Camera.ViewportSize / 2;
            Rects[#Rects + 1] = { Corner.X, Corner.Y, Corner.X + Size.X, Corner.Y + Size.Y };

            Glass.Part.Size = Vector3.new(Size.X * PerPixel, Size.Y * PerPixel, 0);
            Glass.Part.CFrame = Camera.CFrame * CFrame.new(Center.X * PerPixel, -Center.Y * PerPixel, -GLASS_DEPTH);
        end;
    end;

    -- eases to Library.BlurStrength while a glass frame is shown, and back to 0 when none is
    local Goal = Wanted and math.clamp(tonumber(Library.BlurStrength) or 1, 0, 1) or 0;
    local Step = Delta / 0.2;
    Blur.NearIntensity = Blur.NearIntensity + math.clamp(Goal - Blur.NearIntensity, -Step, Step);
    Blur.Enabled = Blur.NearIntensity > 0;

    if (Wanted and Library.BlurBillboards == true and Camera ~= nil) ~= BillboardsOn then
        SetBillboardBlur(not BillboardsOn);
    end;

    if BillboardsOn then
        HoldBillboards(Camera, Rects);
    end;
end;

function Library:AddGlass(Frame, Shown)
    if not Library.Blur then
        NewBlur(0);

        -- after the camera scripts, so the parts never trail the camera by a frame
        Library.GlassBinding = 'LinoriaGlass_' .. game:GetService('HttpService'):GenerateGUID(false);
        RunService:BindToRenderStep(Library.GlassBinding, Enum.RenderPriority.Last.Value, UpdateGlass);
    end;

    GlassFrames[Frame] = { Part = NewGlassPart(), Shown = Shown };
end;

function Library:Unload()
    -- Unload all of the signals
    for Idx = #Library.Signals, 1, -1 do
        local Connection = table.remove(Library.Signals, Idx)
        Connection:Disconnect()
    end

     -- Call our unload callback, maybe to undo some hooks etc
    if Library.UnloadCallback then
        Library.UnloadCallback()
    end

    ScreenGui:Destroy()

    if Library.Blur then
        RunService:UnbindFromRenderStep(Library.GlassBinding)
        Library.Blur:Destroy()

        if BillboardsOn then
            SetBillboardBlur(false)
        end

        for _, Glass in next, GlassFrames do
            Glass.Part:Destroy()
        end
    end

    for _, Gui in next, PanelGuis do
        Gui:Destroy()
    end
end

-- Kept in its own field: storing it in Library.OnUnload replaced this method, and an Unload before any callback was
-- registered (a re-run tearing down a run still building its UI) called the method itself, which set it to nil and
-- made that run's later Library:OnUnload(...) fail with "missing method 'OnUnload'".
function Library:OnUnload(Callback)
    Library.UnloadCallback = Callback
end

Library:GiveSignal(ScreenGui.DescendantRemoving:Connect(function(Instance)
    -- a section moving to / from its floating layer is not being destroyed: keep its colors updating
    if Library.MovingSection then
        return;
    end;

    if Library.RegistryMap[Instance] then
        Library:RemoveFromRegistry(Instance);
    end;
end))

-- Popups (dropdown lists, color pickers, key/mode menus) live directly under the ScreenGui, so they get
-- their own UIScale that follows Library:SetScale.
function Library:RegisterPopup(Frame)
    Library:Create('UIScale', {
        Scale = Library.UIScale;
        Parent = Frame;
    });

    table.insert(Library.Popups, Frame);
end;

-- Glow image: a blurred rounded square (the glow asset used by Starlight Interface Suite). Its 100px blurred
-- margin is stretched to G px, so a glow of size G spills exactly G px past the frame it is parented to.
-- ColorKey (e.g. 'AccentColor') keeps it following the library colors; leave nil to color it yourself.
function Library:AddGlow(Parent, G, ZIndex, ColorKey)
    local Glow = Library:Create('ImageLabel', {
        Name = 'Glow';
        AnchorPoint = Vector2.new(0.5, 0.5);
        BackgroundTransparency = 1;
        Position = UDim2.fromScale(0.5, 0.5);
        Size = UDim2.new(1, 2 * G, 1, 2 * G);
        Image = 'rbxassetid://94680501858633';
        ImageColor3 = Library.AccentColor;
        ImageTransparency = 1;
        ScaleType = Enum.ScaleType.Slice;
        SliceCenter = Rect.new(100, 100, 500, 500);
        SliceScale = G / 100;
        ZIndex = ZIndex;
        Parent = Parent;
    });

    if ColorKey then
        Library:AddToRegistry(Glow, { ImageColor3 = ColorKey });
    end;

    return Glow;
end;

-- Lucide icons (lucide.dev) rebuilt from frames on their 24-unit grid: Roblox cannot draw SVG, and image assets need
-- uploading. lines = { x1, y1, x2, y2 }, circles = { cx, cy, r }. pin / pin-off are simplified outlines of Lucide's.
local LucideIcons = {
    ['search'] = { lines = { { 21, 21, 16.65, 16.65 } }, circles = { { 11, 11, 8 } } };
    ['minus'] = { lines = { { 5, 12, 19, 12 } } };
    ['plus'] = { lines = { { 5, 12, 19, 12 }, { 12, 5, 12, 19 } } };
    ['check'] = { lines = { { 20, 6, 9, 17 }, { 9, 17, 4, 12 } } };
    ['arrow-right-left'] = { lines = { { 8, 3, 4, 7 }, { 4, 7, 8, 11 }, { 4, 7, 20, 7 }, { 16, 21, 20, 17 }, { 20, 17, 16, 13 }, { 20, 17, 4, 17 } } };
    ['pin'] = { lines = { { 8, 3, 16, 3 }, { 9, 3, 9, 10 }, { 15, 3, 15, 10 }, { 9, 10, 5, 15 }, { 15, 10, 19, 15 }, { 5, 15, 19, 15 }, { 12, 15, 12, 22 } } };
};
LucideIcons['pin-off'] = { lines = table.clone(LucideIcons.pin.lines) };
table.insert(LucideIcons['pin-off'].lines, { 2, 2, 22, 22 });

-- Info: Parent, Size (px number or UDim2), Position, AnchorPoint, ZIndex, Color (registry key or function, default
-- 'FontColor'), Thickness (px, default 2). Returns the holder frame and its stroke pieces (in table order: lines,
-- then circles) so callers can show / hide parts, e.g. the vertical bar of 'plus'.
function Library:CreateIcon(Name, Info)
    local Shape = assert(LucideIcons[Name], 'CreateIcon: unknown icon ' .. tostring(Name));
    local ColorKey = Info.Color or 'FontColor';
    local Color = type(ColorKey) == 'function' and ColorKey() or Library[ColorKey];
    local T = Info.Thickness or 2;
    local ZIndex = Info.ZIndex or 1;

    local Icon = Library:Create('Frame', {
        AnchorPoint = Info.AnchorPoint or Vector2.zero;
        BackgroundTransparency = 1;
        Position = Info.Position or UDim2.new();
        Size = typeof(Info.Size) == 'UDim2' and Info.Size or UDim2.fromOffset(Info.Size or 14, Info.Size or 14);
        ZIndex = ZIndex;
        Parent = Info.Parent;
    });

    local Pieces = {};

    for _, L in next, Shape.lines or {} do
        local DX, DY = L[3] - L[1], L[4] - L[2];
        -- an upright line is sized, not turned: a rotated frame is anti-aliased, and at 1px the bar of the plus came
        -- out dimmer than its dash
        local Upright = DX == 0;
        -- + T px of length gives round caps that also close the joints of polylines
        local Line = Library:Create('Frame', {
            AnchorPoint = Vector2.new(0.5, 0.5);
            BackgroundColor3 = Color;
            BorderSizePixel = 0;
            Position = UDim2.fromScale((L[1] + L[3]) / 48, (L[2] + L[4]) / 48);
            Rotation = Upright and 0 or math.deg(math.atan2(DY, DX));
            Size = Upright and UDim2.new(0, T, math.abs(DY) / 24, T) or UDim2.new(math.sqrt(DX * DX + DY * DY) / 24, T, 0, T);
            ZIndex = ZIndex;
            Parent = Icon;
        });
        Library:Create('UICorner', { CornerRadius = UDim.new(1, 0); Parent = Line });
        Library:AddToRegistry(Line, { BackgroundColor3 = ColorKey });
        table.insert(Pieces, Line);
    end;

    for _, C in next, Shape.circles or {} do
        local Ring = Library:Create('Frame', {
            AnchorPoint = Vector2.new(0.5, 0.5);
            BackgroundTransparency = 1;
            Position = UDim2.fromScale(C[1] / 24, C[2] / 24);
            Size = UDim2.fromScale(C[3] / 12, C[3] / 12);
            ZIndex = ZIndex;
            Parent = Icon;
        });
        Library:Create('UICorner', { CornerRadius = UDim.new(1, 0); Parent = Ring });
        Library:AddToRegistry(Library:Create('UIStroke', { Color = Color; Thickness = T * 0.75; Parent = Ring }), { Color = ColorKey });
        table.insert(Pieces, Ring);
    end;

    return Icon, Pieces;
end;

-- Element glows are hidden unless Library.ElementGlow is on; IsActive() says whether this one should
-- currently be lit (toggle on, slider above zero, ...). Call Library:ApplyElementGlow after its state changes.
function Library:TrackElementGlow(Glow, IsActive)
    Library.ElementGlows[Glow] = IsActive;
end;

function Library:ApplyElementGlow(Glow, Instant)
    local IsActive = Library.ElementGlows[Glow];
    local Target = (Library.ElementGlow and IsActive and IsActive()) and Library.ElementGlowTransparency or 1;

    if Instant then
        Glow.ImageTransparency = Target;
    else
        Library:CreateTween(Glow, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { ImageTransparency = Target }):Play();
    end;
end;

function Library:SetElementGlow(Enabled, Transparency)
    Library.ElementGlow = (not not Enabled);
    Library.ElementGlowTransparency = tonumber(Transparency) or Library.ElementGlowTransparency;

    for Glow in next, Library.ElementGlows do
        if Glow.Parent then
            Library:ApplyElementGlow(Glow);
        else
            Library.ElementGlows[Glow] = nil;
        end;
    end;
end;

-- Accent glow around the main window. Size is the spread in px, Transparency 0..1 (lower = stronger).
function Library:SetGlow(Enabled, Size, Transparency)
    Library.GlowEnabled = (not not Enabled);
    Library.GlowSize = tonumber(Size) or Library.GlowSize;
    Library.GlowTransparency = tonumber(Transparency) or Library.GlowTransparency;

    local Glow = Library.WindowGlow;

    if Glow then
        Glow.Size = UDim2.new(1, 2 * Library.GlowSize, 1, 2 * Library.GlowSize);
        Glow.SliceScale = Library.GlowSize / 100;
        Glow.ImageTransparency = Library.GlowEnabled and Library.GlowTransparency or 1;
    end;
end;

-- Places a popup at (X, Y) in ScreenGui pixels without letting it leave the screen. If it would overflow the
-- right/bottom edge it first flips: AltX is where its RIGHT edge should sit instead, AltY where its BOTTOM edge
-- should sit (pass nil to skip flipping); whatever still overflows is clamped inside the screen.
function Library:PlacePopup(Frame, X, Y, AltX, AltY)
    local View = ScreenGui.AbsoluteSize;
    local Scale = Library.UIScale or 1;
    local W, H = Frame.Size.X.Offset * Scale, Frame.Size.Y.Offset * Scale;

    if AltX and X + W > View.X then
        X = AltX - W;
    end;

    if AltY and Y + H > View.Y then
        Y = AltY - H;
    end;

    Frame.Position = UDim2.fromOffset(
        math.clamp(X, 0, math.max(View.X - W, 0)),
        math.clamp(Y, 0, math.max(View.Y - H, 0))
    );
end;

-- Puts a popup at the first spot next to Anchor that fits fully on screen: below, above, right, left. Short screens
-- (phones) fit neither below nor above, so the popup moves beside its opener instead of covering it.
function Library:PlacePopupNear(Frame, Anchor, Gap)
    local Pos, Size = Anchor.AbsolutePosition, Anchor.AbsoluteSize;
    local View = ScreenGui.AbsoluteSize;
    local Scale = Library.UIScale or 1;
    local W, H = Frame.Size.X.Offset * Scale, Frame.Size.Y.Offset * Scale;
    local ClampX = math.clamp(Pos.X, 0, math.max(View.X - W, 0));
    local ClampY = math.clamp(Pos.Y + Size.Y / 2 - H / 2, 0, math.max(View.Y - H, 0));

    for _, Spot in next, {
        { ClampX, Pos.Y + Size.Y + Gap },
        { ClampX, Pos.Y - Gap - H },
        { Pos.X + Size.X + Gap, ClampY },
        { Pos.X - Gap - W, ClampY },
    } do
        local X, Y = Spot[1], Spot[2];
        if X >= 0 and Y >= 0 and X + W <= View.X and Y + H <= View.Y then
            Frame.Position = UDim2.fromOffset(X, Y);
            return;
        end;
    end;

    Library:PlacePopup(Frame, Pos.X, Pos.Y + Size.Y + Gap, Pos.X + Size.X, Pos.Y - Gap); -- nothing fits: clamp
end;

-- Scales the main window and every popup. 1 = default size.
local PendingScale, ScaleWaiting = nil, false;

function Library:SetScale(Scale)
    Scale = math.clamp(tonumber(Scale) or 1, 0.5, 2);

    -- Applied once the mouse / finger is released: rescaling mid-drag moved the scale slider itself under the
    -- cursor, which fed a new value back in every frame and shrank the menu at once.
    if IsHeld() then
        PendingScale = Scale;
        if not ScaleWaiting then
            ScaleWaiting = true;
            task.spawn(function()
                while IsHeld() do
                    RenderStepped:Wait();
                end;
                ScaleWaiting = false;
                Library:SetScale(PendingScale);
            end);
        end;
        return;
    end;

    -- Below 1 a 1px outline is under a pixel wide, and the outline and the black line inside it round onto the same
    -- screen pixel, so outer outlines vanish (0.99 looked broken). Snap near-1 values to exactly 1.
    -- shortcut: real shrinking (< 0.95) still thins outlines; fixing that needs every bordered frame redrawn.
    if math.abs(Scale - 1) < 0.05 then
        Scale = 1;
    end;

    Library.UIScale = Scale;

    if Library.WindowScale then
        Library.WindowScale.Scale = Scale;
    end;

    for Idx = #Library.Popups, 1, -1 do
        local Frame = Library.Popups[Idx];
        local PopupScale = Frame and Frame:FindFirstChildOfClass('UIScale');

        if PopupScale then
            PopupScale.Scale = Scale;
        else
            table.remove(Library.Popups, Idx);
        end;
    end;
end;

-- Custom menu cursor (replaces the drawn triangle while the menu is open).
--   Source: an image URL (downloaded once to LinoriaCursors/ and loaded with getcustomasset), a workspace file path,
--   a Windows .cur file or link (its PNG and hotspot are used), or an rbxassetid:// id. '' goes back to the triangle; nil keeps the current image (to change only the size).
--   Size: px, square. The image's top-left corner is the hotspot.
-- shortcut: a URL is cached by name, so an image changed at the same URL needs its LinoriaCursors file deleted.
local GetCustomAsset = getcustomasset or getsynasset;

-- Windows .cur cursors (Vista and later) store PNG images inside. Returns the largest one and its hotspot (the
-- click point) as a fraction of the image size.
local function CurToPng(Data)
    local Best;

    for Index = 0, string.unpack('<I2', Data, 5) - 1 do
        local W, H, _, _, HX, HY, Size, Offset = string.unpack('<BBBBI2I2I4I4', Data, 7 + Index * 16);
        W, H = (W == 0 and 256 or W), (H == 0 and 256 or H);

        if Data:sub(Offset + 1, Offset + 4) == '\137PNG' and (not Best or W > Best.W) then
            Best = { W = W, Png = Data:sub(Offset + 1, Offset + Size), Hot = Vector2.new(HX / W, HY / H) };
        end;
    end;

    assert(Best, 'no PNG image in this .cur (old BMP-only cursors are not supported)');
    return Best.Png, Best.Hot;
end;

-- An image source as something an ImageLabel can show: rbxasset / rbxthumb ids as they are, a URL (downloaded once)
-- or a workspace file through getcustomasset. A .cur also returns its hotspot. Errors when it cannot be loaded;
-- a URL yields while it downloads. (The folder is named for its first user, the cursor.)
local function ResolveImage(Source)
    if Source:find('^rbxasset') or Source:find('^rbxthumb') then
        return Source;
    end;

    assert(GetCustomAsset, 'this executor has no getcustomasset');
    local Path = Source;

    if Source:find('^https?://') then
        Path = 'LinoriaCursors/' .. (Source:gsub('[^%w%.]', '_'):sub(-80));

        if not isfile(Path) then
            if not isfolder('LinoriaCursors') then
                makefolder('LinoriaCursors');
            end;

            writefile(Path, game:HttpGet(Source));
        end;
    end;

    if Path:lower():find('%.cur$') then
        local Png, Hot = CurToPng(readfile(Path));
        local PngPath = Path:sub(1, -5) .. '.png';
        writefile(PngPath, Png);
        return GetCustomAsset(PngPath), Hot;
    end;

    return GetCustomAsset(Path);
end;

function Library:SetCursor(Source, Size)
    if Library:NeedsUIThread() then
        return Library:RunOnUIThread(Library.SetCursor, Library, Source, Size);
    end;

    Library.CursorSize = tonumber(Size) or Library.CursorSize or 24;

    if Source ~= nil then
        Source = tostring(Source):match('^%s*(.-)%s*$');
        local Ok, Asset, Hotspot = pcall(function()
            if Source == '' then
                return nil;
            end;

            return ResolveImage(Source);
        end);

        if not Ok then
            Library:Notify('Cursor image failed: ' .. tostring(Asset), 4);
            Asset = nil;
        end;

        Library.CursorAsset = Asset;
        Library.CursorHotspot = Ok and Hotspot or Vector2.zero;
    end;

    if Library.CursorAsset and not Library.CursorImage then
        Library.CursorImage = Library:Create('ImageLabel', {
            Name = 'Cursor';
            BackgroundTransparency = 1;
            ImageTransparency = 1;
            Active = false;
            Visible = false;
            ZIndex = 10000;
            Parent = ScreenGui;
        });
        pcall(function() Library.CursorImage.Interactable = false; end); -- never take hover/clicks from the menu
    end;

    if Library.CursorImage then
        Library.CursorImage.Image = Library.CursorAsset or '';
        Library.CursorImage.Size = UDim2.fromOffset(Library.CursorSize, Library.CursorSize);

        if not Library.CursorAsset then
            Library.CursorImage.Visible = false;
        end;
    end;
end;

local BaseAddons = {};

do
    local Funcs = {};

    function Funcs:AddColorPicker(Idx, Info)
        Info.Tooltip = Info.Tooltip or (Library.Tooltips and Library.Tooltips[Idx]);
        local ToggleLabel = self.TextLabel;
        -- local Container = self.Container;

        assert(Info.Default, 'AddColorPicker: Missing default value.');

        local ColorPicker = {
            Value = Info.Default;
            Transparency = Info.Transparency or 0;
            Type = 'ColorPicker';
            Title = type(Info.Title) == 'string' and Info.Title or 'Color picker',
            Callback = Info.Callback or function(Color) end;
        };

        function ColorPicker:SetHSVFromRGB(Color)
            local H, S, V = Color3.toHSV(Color);

            ColorPicker.Hue = H;
            ColorPicker.Sat = S;
            ColorPicker.Vib = V;
        end;

        ColorPicker:SetHSVFromRGB(ColorPicker.Value);

        local DisplayFrame = Library:Create('Frame', {
            BackgroundColor3 = ColorPicker.Value;
            BorderColor3 = Library:GetDarkerColor(ColorPicker.Value);
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(0, 28, 0, 14);
            ZIndex = 6;
            Parent = ToggleLabel;
        });

        -- Swatch glow takes the picked color (not the accent) and is lit whenever element glow is on.
        local SwatchGlow = Library:AddGlow(DisplayFrame, 8, 5);
        Library:TrackElementGlow(SwatchGlow, function() return true; end);

        -- Transparency image taken from https://github.com/matas3535/SplixPrivateDrawingLibrary/blob/main/Library.lua cus i'm lazy
        local CheckerFrame = Library:Create('ImageLabel', {
            BorderSizePixel = 0;
            Size = UDim2.new(0, 27, 0, 13);
            ZIndex = 5;
            Image = 'http://www.roblox.com/asset/?id=12977615774';
            Visible = not not Info.Transparency;
            Parent = DisplayFrame;
        });

        -- 1/16/23
        -- Rewrote this to be placed inside the Library ScreenGui
        -- There was some issue which caused RelativeOffset to be way off
        -- Thus the color picker would never show

        local PickerFrameOuter = Library:Create('Frame', {
            Name = 'Color';
            BackgroundColor3 = Color3.new(1, 1, 1);
            BorderColor3 = Color3.new(0, 0, 0);
            Position = UDim2.fromOffset(DisplayFrame.AbsolutePosition.X, DisplayFrame.AbsolutePosition.Y + 18),
            Size = UDim2.fromOffset(230, Info.Transparency and 271 or 253);
            Visible = false;
            ZIndex = 15;
            Parent = ScreenGui,
        });

        local function PlacePicker()
            Library:PlacePopupNear(PickerFrameOuter, DisplayFrame, 4);
        end;

        -- Only while open (Show places it): every hidden popup re-placing itself on each window move forced a layout
        -- pass per dropdown / picker and dropped the FPS while dragging the menu.
        DisplayFrame:GetPropertyChangedSignal('AbsolutePosition'):Connect(function()
            if PickerFrameOuter.Visible then PlacePicker(); end;
        end)

        Library:RegisterPopup(PickerFrameOuter);

        local PickerFrameInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 16;
            Parent = PickerFrameOuter;
        });

        local Highlight = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 0, 2);
            ZIndex = 17;
            Parent = PickerFrameInner;
        });

        local SatVibMapOuter = Library:Create('Frame', {
            BorderColor3 = Color3.new(0, 0, 0);
            Position = UDim2.new(0, 4, 0, 25);
            Size = UDim2.new(0, 200, 0, 200);
            ZIndex = 17;
            Parent = PickerFrameInner;
        });

        local SatVibMapInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 18;
            Parent = SatVibMapOuter;
        });

        local SatVibMap = Library:Create('ImageLabel', {
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 18;
            Image = 'rbxassetid://4155801252';
            Parent = SatVibMapInner;
        });

        local CursorOuter = Library:Create('ImageLabel', {
            AnchorPoint = Vector2.new(0.5, 0.5);
            Size = UDim2.new(0, 6, 0, 6);
            BackgroundTransparency = 1;
            Image = 'http://www.roblox.com/asset/?id=9619665977';
            ImageColor3 = Color3.new(0, 0, 0);
            ZIndex = 19;
            Parent = SatVibMap;
        });

        local CursorInner = Library:Create('ImageLabel', {
            Size = UDim2.new(0, CursorOuter.Size.X.Offset - 2, 0, CursorOuter.Size.Y.Offset - 2);
            Position = UDim2.new(0, 1, 0, 1);
            BackgroundTransparency = 1;
            Image = 'http://www.roblox.com/asset/?id=9619665977';
            ZIndex = 20;
            Parent = CursorOuter;
        })

        local HueSelectorOuter = Library:Create('Frame', {
            BorderColor3 = Color3.new(0, 0, 0);
            Position = UDim2.new(0, 208, 0, 25);
            Size = UDim2.new(0, 15, 0, 200);
            ZIndex = 17;
            Parent = PickerFrameInner;
        });

        local HueSelectorInner = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(1, 1, 1);
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 18;
            Parent = HueSelectorOuter;
        });

        local HueCursor = Library:Create('Frame', { 
            BackgroundColor3 = Color3.new(1, 1, 1);
            AnchorPoint = Vector2.new(0, 0.5);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(1, 0, 0, 1);
            ZIndex = 18;
            Parent = HueSelectorInner;
        });

        local HueBoxOuter = Library:Create('Frame', {
            BorderColor3 = Color3.new(0, 0, 0);
            Position = UDim2.fromOffset(4, 228),
            Size = UDim2.new(0.5, -6, 0, 20),
            ZIndex = 18,
            Parent = PickerFrameInner;
        });

        local HueBoxInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 18,
            Parent = HueBoxOuter;
        });

        Library:Create('UIGradient', {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212))
            });
            Rotation = 90;
            Parent = HueBoxInner;
        });

        local HueBox = Library:Create('TextBox', {
            BackgroundTransparency = 1;
            Position = UDim2.new(0, 5, 0, 0);
            Size = UDim2.new(1, -5, 1, 0);
            Font = Library.Font;
            PlaceholderColor3 = Color3.fromRGB(190, 190, 190);
            PlaceholderText = 'Hex color',
            Text = '#FFFFFF',
            TextColor3 = Library.FontColor;
            TextSize = 14;
            TextStrokeTransparency = 0;
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 20,
            Parent = HueBoxInner;
        });

        Library:ApplyTextStroke(HueBox);

        local RgbBoxBase = Library:Create(HueBoxOuter:Clone(), {
            Position = UDim2.new(0.5, 2, 0, 228),
            Size = UDim2.new(0.5, -6, 0, 20),
            Parent = PickerFrameInner
        });

        local RgbBox = Library:Create(RgbBoxBase.Frame:FindFirstChild('TextBox'), {
            Text = '255, 255, 255',
            PlaceholderText = 'RGB color',
            TextColor3 = Library.FontColor
        });

        local TransparencyBoxOuter, TransparencyBoxInner, TransparencyCursor;
        
        if Info.Transparency then 
            TransparencyBoxOuter = Library:Create('Frame', {
                BorderColor3 = Color3.new(0, 0, 0);
                Position = UDim2.fromOffset(4, 251);
                Size = UDim2.new(1, -8, 0, 15);
                ZIndex = 19;
                Parent = PickerFrameInner;
            });

            TransparencyBoxInner = Library:Create('Frame', {
                BackgroundColor3 = ColorPicker.Value;
                BorderColor3 = Library.OutlineColor;
                BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.new(1, 0, 1, 0);
                ZIndex = 19;
                Parent = TransparencyBoxOuter;
            });

            Library:AddToRegistry(TransparencyBoxInner, { BorderColor3 = 'OutlineColor' });

            Library:Create('ImageLabel', {
                BackgroundTransparency = 1;
                Size = UDim2.new(1, 0, 1, 0);
                Image = 'http://www.roblox.com/asset/?id=12978095818';
                ZIndex = 20;
                Parent = TransparencyBoxInner;
            });

            TransparencyCursor = Library:Create('Frame', { 
                BackgroundColor3 = Color3.new(1, 1, 1);
                AnchorPoint = Vector2.new(0.5, 0);
                BorderColor3 = Color3.new(0, 0, 0);
                Size = UDim2.new(0, 1, 1, 0);
                ZIndex = 21;
                Parent = TransparencyBoxInner;
            });
        end;

        local DisplayLabel = Library:CreateLabel({
            Size = UDim2.new(1, 0, 0, 14);
            Position = UDim2.fromOffset(5, 5);
            TextXAlignment = Enum.TextXAlignment.Left;
            TextSize = 14;
            Text = ColorPicker.Title,--Info.Default;
            TextWrapped = false;
            ZIndex = 16;
            Parent = PickerFrameInner;
        });


        local ContextMenu = {}
        do
            ContextMenu.Options = {}
            ContextMenu.Container = Library:Create('Frame', {
                BorderColor3 = Color3.new(),
                ZIndex = 14,

                Visible = false,
                Parent = ScreenGui
            })

            Library:RegisterPopup(ContextMenu.Container);

            ContextMenu.Inner = Library:Create('Frame', {
                BackgroundColor3 = Library.BackgroundColor;
                BorderColor3 = Library.OutlineColor;
                BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.fromScale(1, 1);
                ZIndex = 15;
                Parent = ContextMenu.Container;
            });

            Library:Create('UIListLayout', {
                Name = 'Layout',
                FillDirection = Enum.FillDirection.Vertical;
                SortOrder = Enum.SortOrder.LayoutOrder;
                Parent = ContextMenu.Inner;
            });

            Library:Create('UIPadding', {
                Name = 'Padding',
                PaddingLeft = UDim.new(0, 4),
                Parent = ContextMenu.Inner,
            });

            -- Right of the swatch, flipping to its left when it would leave the screen.
            local function updateMenuPosition()
                local Pos, Size = DisplayFrame.AbsolutePosition, DisplayFrame.AbsoluteSize;
                Library:PlacePopup(ContextMenu.Container, Pos.X + Size.X + 4, Pos.Y + 1, Pos.X - 4, Pos.Y + Size.Y);
            end

            local function updateMenuSize()
                local menuWidth = 60
                for i, label in next, ContextMenu.Inner:GetChildren() do
                    if label:IsA('TextLabel') then
                        menuWidth = math.max(menuWidth, label.TextBounds.X)
                    end
                end

                ContextMenu.Container.Size = UDim2.fromOffset(
                    menuWidth + 8,
                    ContextMenu.Inner.Layout.AbsoluteContentSize.Y + 4
                )
            end

            DisplayFrame:GetPropertyChangedSignal('AbsolutePosition'):Connect(function()
                if ContextMenu.Container.Visible then updateMenuPosition(); end; -- only while open, see PlacePicker
            end)
            ContextMenu.Inner.Layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(updateMenuSize)

            task.spawn(updateMenuPosition)
            task.spawn(updateMenuSize)

            Library:AddToRegistry(ContextMenu.Inner, {
                BackgroundColor3 = 'BackgroundColor';
                BorderColor3 = 'OutlineColor';
            });

            function ContextMenu:Show()
                updateMenuPosition()
                self.Container.Visible = true
            end

            function ContextMenu:Hide()
                self.Container.Visible = false
            end

            function ContextMenu:AddOption(Str, Callback)
                if type(Callback) ~= 'function' then
                    Callback = function() end
                end

                local Button = Library:CreateLabel({
                    Active = false;
                    Size = UDim2.new(1, 0, 0, 15);
                    TextSize = 13;
                    Text = Str;
                    ZIndex = 16;
                    Parent = self.Inner;
                    TextXAlignment = Enum.TextXAlignment.Left,
                });

                Library:OnHighlight(Button, Button, 
                    { TextColor3 = 'AccentColor' },
                    { TextColor3 = 'FontColor' }
                );

                Button.InputBegan:Connect(function(Input)
                    if not IsTap(Input) then
                        return
                    end

                    Callback()
                end)
            end

            ContextMenu:AddOption('Copy color', function()
                Library.ColorClipboard = ColorPicker.Value
                Library:Notify('Copied color!', 2)
            end)

            ContextMenu:AddOption('Paste color', function()
                if not Library.ColorClipboard then
                    return Library:Notify('You have not copied a color!', 2)
                end
                ColorPicker:SetValueRGB(Library.ColorClipboard)
            end)


            ContextMenu:AddOption('Copy HEX', function()
                pcall(setclipboard, ColorPicker.Value:ToHex())
                Library:Notify('Copied hex code to clipboard!', 2)
            end)

            ContextMenu:AddOption('Copy RGB', function()
                pcall(setclipboard, table.concat({ math.floor(ColorPicker.Value.R * 255), math.floor(ColorPicker.Value.G * 255), math.floor(ColorPicker.Value.B * 255) }, ', '))
                Library:Notify('Copied RGB values to clipboard!', 2)
            end)

        end

        Library:AddToRegistry(PickerFrameInner, { BackgroundColor3 = 'BackgroundColor'; BorderColor3 = 'OutlineColor'; });
        Library:AddToRegistry(Highlight, { BackgroundColor3 = 'AccentColor'; });
        Library:AddToRegistry(SatVibMapInner, { BackgroundColor3 = 'BackgroundColor'; BorderColor3 = 'OutlineColor'; });

        Library:AddToRegistry(HueBoxInner, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'OutlineColor'; });
        Library:AddToRegistry(RgbBoxBase.Frame, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'OutlineColor'; });
        Library:AddToRegistry(RgbBox, { TextColor3 = 'FontColor', });
        Library:AddToRegistry(HueBox, { TextColor3 = 'FontColor', });

        local SequenceTable = {};

        for Hue = 0, 1, 0.1 do
            table.insert(SequenceTable, ColorSequenceKeypoint.new(Hue, Color3.fromHSV(Hue, 1, 1)));
        end;

        local HueSelectorGradient = Library:Create('UIGradient', {
            Color = ColorSequence.new(SequenceTable);
            Rotation = 90;
            Parent = HueSelectorInner;
        });

        HueBox.FocusLost:Connect(function(enter)
            if enter then
                local success, result = pcall(Color3.fromHex, HueBox.Text)
                if success and typeof(result) == 'Color3' then
                    ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib = Color3.toHSV(result)
                end
            end

            ColorPicker:Display()
        end)

        RgbBox.FocusLost:Connect(function(enter)
            if enter then
                local r, g, b = RgbBox.Text:match('(%d+),%s*(%d+),%s*(%d+)')
                if r and g and b then
                    ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib = Color3.toHSV(Color3.fromRGB(r, g, b))
                end
            end

            ColorPicker:Display()
        end)

        function ColorPicker:Display()
            ColorPicker.Value = Color3.fromHSV(ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib);
            SatVibMap.BackgroundColor3 = Color3.fromHSV(ColorPicker.Hue, 1, 1);

            Library:Create(DisplayFrame, {
                BackgroundColor3 = ColorPicker.Value;
                BackgroundTransparency = ColorPicker.Transparency;
                BorderColor3 = Library:GetDarkerColor(ColorPicker.Value);
            });

            SwatchGlow.ImageColor3 = ColorPicker.Value;
            Library:ApplyElementGlow(SwatchGlow, true);

            if TransparencyBoxInner then
                TransparencyBoxInner.BackgroundColor3 = ColorPicker.Value;
                TransparencyCursor.Position = UDim2.new(1 - ColorPicker.Transparency, 0, 0, 0);
            end;

            CursorOuter.Position = UDim2.new(ColorPicker.Sat, 0, 1 - ColorPicker.Vib, 0);
            HueCursor.Position = UDim2.new(0, 0, ColorPicker.Hue, 0);

            HueBox.Text = '#' .. ColorPicker.Value:ToHex()
            RgbBox.Text = table.concat({ math.floor(ColorPicker.Value.R * 255), math.floor(ColorPicker.Value.G * 255), math.floor(ColorPicker.Value.B * 255) }, ', ')

            Library:SafeCallback(ColorPicker.Callback, ColorPicker.Value);
            Library:SafeCallback(ColorPicker.Changed, ColorPicker.Value);
            Library:AttemptSave();
        end;

        function ColorPicker:OnChanged(Func)
            ColorPicker.Changed = Func;
            Func(ColorPicker.Value)
        end;

        function ColorPicker:Show()
            for Frame, Val in next, Library.OpenedFrames do
                if Frame.Name == 'Color' then
                    Frame.Visible = false;
                    Library.OpenedFrames[Frame] = nil;
                end;
            end;

            PlacePicker();
            PickerFrameOuter.Visible = true;
            Library.OpenedFrames[PickerFrameOuter] = true;
        end;

        function ColorPicker:Hide()
            PickerFrameOuter.Visible = false;
            Library.OpenedFrames[PickerFrameOuter] = nil;
        end;

        function ColorPicker:SetValue(HSV, Transparency)
            if Library:NeedsUIThread() then
                return Library:RunOnUIThread(ColorPicker.SetValue, ColorPicker, HSV, Transparency);
            end;

            local Color = Color3.fromHSV(HSV[1], HSV[2], HSV[3]);

            ColorPicker.Transparency = Transparency or 0;
            ColorPicker:SetHSVFromRGB(Color);
            ColorPicker:Display();
        end;

        function ColorPicker:SetValueRGB(Color, Transparency)
            if Library:NeedsUIThread() then
                return Library:RunOnUIThread(ColorPicker.SetValueRGB, ColorPicker, Color, Transparency);
            end;

            ColorPicker.Transparency = Transparency or 0;
            ColorPicker:SetHSVFromRGB(Color);
            ColorPicker:Display();
        end;

        SatVibMap.InputBegan:Connect(function(Input)
            if IsClick(Input) then
                while IsHeld() do
                    local MinX = SatVibMap.AbsolutePosition.X;
                    local MaxX = MinX + SatVibMap.AbsoluteSize.X;
                    local MouseX = math.clamp(Mouse.X, MinX, MaxX);

                    local MinY = SatVibMap.AbsolutePosition.Y;
                    local MaxY = MinY + SatVibMap.AbsoluteSize.Y;
                    local MouseY = math.clamp(Mouse.Y, MinY, MaxY);

                    ColorPicker.Sat = (MouseX - MinX) / (MaxX - MinX);
                    ColorPicker.Vib = 1 - ((MouseY - MinY) / (MaxY - MinY));
                    ColorPicker:Display();

                    RenderStepped:Wait();
                end;

                Library:AttemptSave();
            end;
        end);

        HueSelectorInner.InputBegan:Connect(function(Input)
            if IsClick(Input) then
                while IsHeld() do
                    local MinY = HueSelectorInner.AbsolutePosition.Y;
                    local MaxY = MinY + HueSelectorInner.AbsoluteSize.Y;
                    local MouseY = math.clamp(Mouse.Y, MinY, MaxY);

                    ColorPicker.Hue = ((MouseY - MinY) / (MaxY - MinY));
                    ColorPicker:Display();

                    RenderStepped:Wait();
                end;

                Library:AttemptSave();
            end;
        end);

        DisplayFrame.InputBegan:Connect(function(Input)
            if IsTap(Input) and not Library:MouseIsOverOpenedFrame() then
                if PickerFrameOuter.Visible then
                    ColorPicker:Hide()
                else
                    ContextMenu:Hide()
                    ColorPicker:Show()
                end;
            elseif Input.UserInputType == Enum.UserInputType.MouseButton2 and not Library:MouseIsOverOpenedFrame() then
                ContextMenu:Show()
                ColorPicker:Hide()
            end
        end);

        if TransparencyBoxInner then
            TransparencyBoxInner.InputBegan:Connect(function(Input)
                if IsClick(Input) then
                    while IsHeld() do
                        local MinX = TransparencyBoxInner.AbsolutePosition.X;
                        local MaxX = MinX + TransparencyBoxInner.AbsoluteSize.X;
                        local MouseX = math.clamp(Mouse.X, MinX, MaxX);

                        ColorPicker.Transparency = 1 - ((MouseX - MinX) / (MaxX - MinX));

                        ColorPicker:Display();

                        RenderStepped:Wait();
                    end;

                    Library:AttemptSave();
                end;
            end);
        end;

        Library:GiveSignal(InputService.InputBegan:Connect(function(Input)
            if IsClick(Input) then
                -- the swatch toggles the picker itself; the picker can sit above it when flipped near the screen bottom
                if not Library:IsMouseOverFrame(PickerFrameOuter) and not Library:IsMouseOverFrame(DisplayFrame) then
                    ColorPicker:Hide();
                end;

                if not Library:IsMouseOverFrame(ContextMenu.Container) then
                    ContextMenu:Hide()
                end
            end;

            if Input.UserInputType == Enum.UserInputType.MouseButton2 and ContextMenu.Container.Visible then
                if not Library:IsMouseOverFrame(ContextMenu.Container) and not Library:IsMouseOverFrame(DisplayFrame) then
                    ContextMenu:Hide()
                end
            end
        end))

        ColorPicker:Display();
        if Info.Tooltip then Library:AddToolTip(Info.Tooltip, DisplayFrame); end;
        ColorPicker.DisplayFrame = DisplayFrame

        Options[Idx] = ColorPicker;

        return self;
    end;

    function Funcs:AddKeyPicker(Idx, Info)
        Info.Tooltip = Info.Tooltip or (Library.Tooltips and Library.Tooltips[Idx]);
        local ParentObj = self;
        local ToggleLabel = self.TextLabel;
        local Container = self.Container;

        assert(Info.Default, 'AddKeyPicker: Missing default value.');

        local KeyPicker = {
            Value = Info.Default;
            Toggled = false;
            Mode = Info.Mode or 'Toggle'; -- Always, Toggle, Hold
            Type = 'KeyPicker';
            Callback = Info.Callback or function(Value) end;
            ChangedCallback = Info.ChangedCallback or function(New) end;

            SyncToggleState = Info.SyncToggleState or false;
        };

        if KeyPicker.SyncToggleState then
            Info.Modes = { 'Toggle' }
            Info.Mode = 'Toggle'
        end

        local PickOuter = Library:Create('Frame', {
            BackgroundTransparency = 1; -- no black frame: the inner frame's outline is the control's edge
            BorderSizePixel = 0;
            Size = UDim2.new(0, 28, 0, 15);
            ZIndex = 6;
            Parent = ToggleLabel;
        });

        local PickInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 7;
            Parent = PickOuter;
        });

        Library:AddToRegistry(PickInner, {
            BackgroundColor3 = 'BackgroundColor';
            BorderColor3 = 'OutlineColor';
        });

        local DisplayLabel = Library:CreateLabel({
            Size = UDim2.new(1, 0, 1, 0);
            TextSize = 13;
            Text = Info.Default;
            TextWrapped = true;
            ZIndex = 8;
            Parent = PickInner;
        });

        -- Widen the key box to fit long key names (RightShift, LeftControl, ...) instead of clipping them.
        local function FitPicker()
            local X = Library:GetTextBounds(DisplayLabel.Text, Library.Font, 13);
            PickOuter.Size = UDim2.new(0, math.max(28, X + 8), 0, 15);
        end;

        FitPicker();

        local ModeSelectOuter = Library:Create('Frame', {
            BorderColor3 = Color3.new(0, 0, 0);
            Position = UDim2.fromOffset(ToggleLabel.AbsolutePosition.X + ToggleLabel.AbsoluteSize.X + 4, ToggleLabel.AbsolutePosition.Y + 1);
            Size = UDim2.new(0, 60, 0, 45 + 2);
            Visible = false;
            ZIndex = 14;
            Parent = ScreenGui;
        });

        -- Right of the label, flipping to its left when it would leave the screen.
        local function PlaceModeSelect()
            local Pos, Size = ToggleLabel.AbsolutePosition, ToggleLabel.AbsoluteSize;
            Library:PlacePopup(ModeSelectOuter, Pos.X + Size.X + 4, Pos.Y + 1, Pos.X - 4, Pos.Y + Size.Y);
        end;

        ToggleLabel:GetPropertyChangedSignal('AbsolutePosition'):Connect(function()
            if ModeSelectOuter.Visible then PlaceModeSelect(); end; -- only while open, see the color picker
        end);

        Library:RegisterPopup(ModeSelectOuter);

        local ModeSelectInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 15;
            Parent = ModeSelectOuter;
        });

        Library:AddToRegistry(ModeSelectInner, {
            BackgroundColor3 = 'BackgroundColor';
            BorderColor3 = 'OutlineColor';
        });

        Library:Create('UIListLayout', {
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            Parent = ModeSelectInner;
        });

        local ContainerLabel = Library:CreateLabel({
            TextXAlignment = Enum.TextXAlignment.Left;
            Size = UDim2.new(1, 0, 0, 18);
            TextSize = 13;
            Visible = false;
            ZIndex = 110;
            Parent = Library.KeybindContainer;
        },  true);

        local Modes = Info.Modes or { 'Always', 'Toggle', 'Hold' };
        local ModeButtons = {};

        for Idx, Mode in next, Modes do
            local ModeButton = {};

            local Label = Library:CreateLabel({
                Active = false;
                Size = UDim2.new(1, 0, 0, 15);
                TextSize = 13;
                Text = Mode;
                ZIndex = 16;
                Parent = ModeSelectInner;
            });

            function ModeButton:Select()
                for _, Button in next, ModeButtons do
                    Button:Deselect();
                end;

                KeyPicker.Mode = Mode;

                Label.TextColor3 = Library.AccentColor;
                Library.RegistryMap[Label].Properties.TextColor3 = 'AccentColor';

                ModeSelectOuter.Visible = false;
            end;

            function ModeButton:Deselect()
                KeyPicker.Mode = nil;

                Label.TextColor3 = Library.FontColor;
                Library.RegistryMap[Label].Properties.TextColor3 = 'FontColor';
            end;

            Label.InputBegan:Connect(function(Input)
                if IsTap(Input) then
                    ModeButton:Select();
                    Library:AttemptSave();
                end;
            end);

            if Mode == KeyPicker.Mode then
                ModeButton:Select();
            end;

            ModeButtons[Mode] = ModeButton;
        end;

        function KeyPicker:Update()
            if Info.NoUI then
                return;
            end;

            local State = KeyPicker:GetState();

            ContainerLabel.Text = string.format('[%s] %s (%s)', KeyPicker.Value, Info.Text, KeyPicker.Mode);

            ContainerLabel.Visible = true;
            ContainerLabel.TextColor3 = State and Library.AccentColor or Library.FontColor;

            Library.RegistryMap[ContainerLabel].Properties.TextColor3 = State and 'AccentColor' or 'FontColor';

            Library:UpdateKeybindFrame();
        end;

        function KeyPicker:GetState()
            if KeyPicker.Mode == 'Always' then
                return true;
            elseif KeyPicker.Mode == 'Hold' then
                if KeyPicker.Value == 'None' then
                    return false;
                end

                local Key = KeyPicker.Value;

                if Key == 'MB1' or Key == 'MB2' then
                    return Key == 'MB1' and InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
                        or Key == 'MB2' and InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2);
                else
                    return InputService:IsKeyDown(Enum.KeyCode[KeyPicker.Value]);
                end;
            else
                return KeyPicker.Toggled;
            end;
        end;

        function KeyPicker:SetValue(Data)
            if Library:NeedsUIThread() then
                return Library:RunOnUIThread(KeyPicker.SetValue, KeyPicker, Data);
            end;

            local Key, Mode = Data[1], Data[2];
            DisplayLabel.Text = Key;
                    FitPicker();
            KeyPicker.Value = Key;
            ModeButtons[Mode]:Select();
            KeyPicker:Update();
            Library:AttemptSave();
        end;

        function KeyPicker:OnClick(Callback)
            KeyPicker.Clicked = Callback
        end

        function KeyPicker:OnChanged(Callback)
            KeyPicker.Changed = Callback
            Callback(KeyPicker.Value)
        end

        if ParentObj.Addons then
            table.insert(ParentObj.Addons, KeyPicker)
        end

        function KeyPicker:DoClick()
            if ParentObj.Type == 'Toggle' and KeyPicker.SyncToggleState then
                ParentObj:SetValue(not ParentObj.Value)
            end

            Library:SafeCallback(KeyPicker.Callback, KeyPicker.Toggled)
            Library:SafeCallback(KeyPicker.Clicked, KeyPicker.Toggled)
        end

        local Picking = false;

        PickOuter.InputBegan:Connect(function(Input)
            if IsTap(Input) and not Library:MouseIsOverOpenedFrame() then
                Picking = true;

                DisplayLabel.Text = '';

                local Break;
                local Text = '';

                task.spawn(function()
                    while (not Break) do
                        if Text == '...' then
                            Text = '';
                        end;

                        Text = Text .. '.';
                        DisplayLabel.Text = Text;

                        task.wait(0.4);
                    end;
                end);

                task.wait(0.2);

                local Event;
                Event = InputService.InputBegan:Connect(function(Input)
                    local Key;

                    if Input.UserInputType == Enum.UserInputType.Keyboard then
                        Key = Input.KeyCode.Name;
                    elseif Input.UserInputType == Enum.UserInputType.MouseButton1 then
                        Key = 'MB1';
                    elseif Input.UserInputType == Enum.UserInputType.MouseButton2 then
                        Key = 'MB2';
                    end;

                    Break = true;
                    Picking = false;

                    DisplayLabel.Text = Key;
                    FitPicker();
                    KeyPicker.Value = Key;

                    Library:SafeCallback(KeyPicker.ChangedCallback, Input.KeyCode or Input.UserInputType)
                    Library:SafeCallback(KeyPicker.Changed, Input.KeyCode or Input.UserInputType)

                    Library:AttemptSave();

                    Event:Disconnect();
                end);
            elseif Input.UserInputType == Enum.UserInputType.MouseButton2 and not Library:MouseIsOverOpenedFrame() then
                PlaceModeSelect();
                ModeSelectOuter.Visible = true;
            end;
        end);

        Library:GiveSignal(InputService.InputBegan:Connect(function(Input)
            if (not Picking) then
                if KeyPicker.Mode == 'Toggle' then
                    local Key = KeyPicker.Value;

                    if Key == 'MB1' or Key == 'MB2' then
                        if Key == 'MB1' and Input.UserInputType == Enum.UserInputType.MouseButton1
                        or Key == 'MB2' and Input.UserInputType == Enum.UserInputType.MouseButton2 then
                            KeyPicker.Toggled = not KeyPicker.Toggled
                            KeyPicker:DoClick()
                        end;
                    elseif Input.UserInputType == Enum.UserInputType.Keyboard then
                        if Input.KeyCode.Name == Key then
                            KeyPicker.Toggled = not KeyPicker.Toggled;
                            KeyPicker:DoClick()
                        end;
                    end;
                end;

                KeyPicker:Update();
            end;

            if IsClick(Input) then
                local AbsPos, AbsSize = ModeSelectOuter.AbsolutePosition, ModeSelectOuter.AbsoluteSize;

                if Mouse.X < AbsPos.X or Mouse.X > AbsPos.X + AbsSize.X
                    or Mouse.Y < (AbsPos.Y - 20 - 1) or Mouse.Y > AbsPos.Y + AbsSize.Y then

                    ModeSelectOuter.Visible = false;
                end;
            end;
        end))

        Library:GiveSignal(InputService.InputEnded:Connect(function(Input)
            if (not Picking) then
                KeyPicker:Update();
            end;
        end))

        KeyPicker:Update();

        Options[Idx] = KeyPicker;
        if Info.Tooltip then Library:AddToolTip(Info.Tooltip, PickOuter); end;

        return self;
    end;

    BaseAddons.__index = Funcs;
    BaseAddons.__namecall = function(Table, Key, ...)
        return Funcs[Key](...);
    end;
end;

local BaseGroupbox = {};

do
    local Funcs = {};

    function Funcs:AddBlank(Size)
        local Groupbox = self;
        local Container = Groupbox.Container;

        Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(1, 0, 0, Size);
            ZIndex = 1;
            Parent = Container;
        });
    end;

    function Funcs:AddLabel(Text, DoesWrap, Tooltip)
        local Label = {};

        local Groupbox = self;
        local Container = Groupbox.Container;

        local TextLabel = Library:CreateLabel({
            Size = UDim2.new(1, -4, 0, 15);
            TextSize = 14;
            Text = Text;
            TextWrapped = DoesWrap or false,
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 5;
            Parent = Container;
        });

        if DoesWrap then
            -- + WRAP_SLACK, taken back from the blank under it: see WRAP_SLACK
            local Y = select(2, Library:GetTextBounds(Text, Library.Font, 14, Vector2.new(TextLabel.AbsoluteSize.X, math.huge)))
            TextLabel.Size = UDim2.new(1, -4, 0, Y + WRAP_SLACK)
        else
            Library:Create('UIListLayout', {
                Padding = UDim.new(0, 4);
                FillDirection = Enum.FillDirection.Horizontal;
                HorizontalAlignment = Enum.HorizontalAlignment.Right;
                SortOrder = Enum.SortOrder.LayoutOrder;
                Parent = TextLabel;
            });
        end

        Label.TextLabel = TextLabel;
        Label.Container = Container;
        function Label:AddTooltip(Text)
            Library:AddToolTip(Text, TextLabel);
            return self;
        end;
        if Tooltip then Label:AddTooltip(Tooltip); end;

        function Label:SetText(Text)
            if Library:NeedsUIThread() then
                return Library:RunOnUIThread(Label.SetText, Label, Text);
            end;

            -- status labels are refreshed every few hundred ms with mostly the same text: skip the re-measure
            -- and groupbox resize when nothing changed
            if TextLabel.Text == Text then
                return;
            end;

            TextLabel.Text = Text

            if DoesWrap then
                local Y = select(2, Library:GetTextBounds(Text, Library.Font, 14, Vector2.new(TextLabel.AbsoluteSize.X, math.huge)))
                TextLabel.Size = UDim2.new(1, -4, 0, Y + WRAP_SLACK)
            end

            Groupbox:Resize();
        end

        if (not DoesWrap) then
            setmetatable(Label, BaseAddons);
        end

        Groupbox:AddBlank(DoesWrap and 5 - WRAP_SLACK or 5);
        Groupbox:Resize();

        return Label;
    end;

    -- A label whose lines can each carry an icon and a colour. IconLabel:SetRows(Rows), Rows = { { Text = 'Chest x1',
    -- Icon = <ImageLabel to copy the image from, a Model to show in 3D, or nil>, Color = <Color3 or nil> }, ... }:
    -- one line per row, the icon in front of it. Safe from game callbacks; unchanged rows are not laid out again.
    function Funcs:AddIconLabel(Text)
        local Groupbox = self;
        local Object = Groupbox:AddLabel(Text, true).TextLabel;
        local Padding = Library:Create('UIPadding', { Parent = Object });
        local Images, Shown = {}, nil;
        local IconLabel = { TextLabel = Object };

        local function Apply(Rows, Indent)
            -- each row is measured on its own, so a row that wraps still leaves the next icon on its line
            local Lines, Y, Width = {}, 0, math.max(Object.AbsoluteSize.X - Indent, 50);
            Padding.PaddingLeft = UDim.new(0, Indent);

            for Index, Row in ipairs(Rows) do
                Lines[Index] = Row.Text;

                if Row.Color then
                    Object.RichText = true;
                    Lines[Index] = '<font color="#' .. Row.Color:ToHex() .. '">'
                        .. Row.Text:gsub('[&<]', { ['&'] = '&amp;', ['<'] = '&lt;' }) .. '</font>';
                end;

                local Image, IsModel = Images[Index], Row.Icon ~= nil and Row.Icon:IsA('Model');

                if Image and Row.Icon and Image:IsA('ViewportFrame') ~= IsModel then
                    Image:Destroy(); -- this line changed between an image and a 3D item
                    Image = nil;
                end;

                if Row.Icon and not Image then
                    Image = Library:Create(IsModel and 'ViewportFrame' or 'ImageLabel', {
                        BackgroundTransparency = 1;
                        Size = UDim2.fromOffset(14, 14);
                        ZIndex = 6;
                        Parent = Object;
                    });
                    Images[Index] = Image;
                end;

                if Image then
                    Image.Visible = Row.Icon ~= nil;

                    if Row.Icon then
                        Image.Position = UDim2.fromOffset(-Indent, Y); -- in the padding, left of the text

                        if not IsModel then
                            -- the image only: some game icons carry an ImageRectSize that crops them to an empty corner
                            Image.Image = Row.Icon.Image;
                        elseif Image.Name ~= Row.Icon.Name then
                            Image.Name = Row.Icon.Name;
                            Image:ClearAllChildren();
                            local Clone = Row.Icon:Clone();
                            Clone.Parent = Image;
                            -- the camera looks at the model's front from far enough to fit its bounding box
                            local Pivot, Extents = Clone:GetBoundingBox();
                            Image.Ambient = Color3.new(1, 1, 1);
                            Image.CurrentCamera = Library:Create('Camera', {
                                FieldOfView = 30;
                                CFrame = CFrame.lookAt(Pivot.Position + Vector3.new(0, 0, Extents.Magnitude * 1.4), Pivot.Position);
                                Parent = Image;
                            });
                        end;
                    end;
                end;

                Y = Y + select(2, Library:GetTextBounds(Row.Text, Library.Font, 14, Vector2.new(Width, math.huge)));
            end;

            for Index, Image in pairs(Images) do
                if Index > #Rows then
                    Image.Visible = false;
                end;
            end;

            Object.Text = table.concat(Lines, '\n');
            Object.Size = UDim2.new(1, -4, 0, Y + WRAP_SLACK);
            Groupbox:Resize();
        end;

        function IconLabel:SetRows(Rows)
            local Parts, Indent = {}, 0;

            for Index, Row in ipairs(Rows) do
                local Icon = Row.Icon and (Row.Icon:IsA('Model') and Row.Icon.Name or Row.Icon.Image) or '';
                Parts[Index] = Row.Text .. '\0' .. Icon .. '\0' .. (Row.Color and Row.Color:ToHex() or '');
                Indent = Row.Icon and 18 or Indent;
            end;

            -- the width is part of the key: rows measured before the label had its real width are laid out again
            local Key = Object.AbsoluteSize.X .. '\n' .. table.concat(Parts, '\n');

            if Key ~= Shown then -- callers refresh every second or so with mostly the same rows
                Shown = Key;
                Library:RunOnUIThread(Apply, Rows, Indent);
            end;
        end;

        return IconLabel;
    end;

    -- A compact, dynamically updated list of removable labels. The owner keeps the data and handles removal.
    function Funcs:AddTagList(Info)
        Info = Info or {};
        local Groupbox = self;
        local Frame = Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(1, -4, 0, 20);
            ZIndex = 5;
            Parent = Groupbox.Container;
        });
        local Layout = Library:Create('UIListLayout', {
            Padding = UDim.new(0, 3);
            SortOrder = Enum.SortOrder.LayoutOrder;
            Parent = Frame;
        });
        local Tags = { Frame = Frame };
        function Tags:SetItems(Items)
            if Library:NeedsUIThread() then
                return Library:RunOnUIThread(Tags.SetItems, Tags, Items);
            end;
            for _, Child in ipairs(Frame:GetChildren()) do
                if Child ~= Layout then Child:Destroy(); end;
            end;
            local Count, Height = 0, 0;
            for _, Item in ipairs(type(Items) == 'table' and Items or {}) do
                Count = Count + 1;
                -- optional Item.Detail goes on a dimmer second line so long rows are not cut to "..."
                local Detail = Item.Detail ~= nil and tostring(Item.Detail) or nil;
                local RowHeight = Detail and 36 or 23;
                Height = Height + RowHeight + 3;
                local Row = Library:Create('Frame', {
                    BackgroundColor3 = Library.MainColor;
                    BorderColor3 = Library.OutlineColor;
                    Size = UDim2.new(1, 0, 0, RowHeight);
                    LayoutOrder = Count;
                    ZIndex = 6;
                    Parent = Frame;
                });
                Library:AddToRegistry(Row, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'OutlineColor'; });
                Library:CreateLabel({
                    BackgroundTransparency = 1;
                    Position = UDim2.fromOffset(5, Detail and 2 or 0);
                    Size = UDim2.new(1, -35, 0, Detail and 17 or 23);
                    Text = tostring(Item.Text or Item.Id or '');
                    TextSize = 13;
                    TextXAlignment = Enum.TextXAlignment.Left;
                    TextTruncate = Enum.TextTruncate.AtEnd;
                    ZIndex = 7;
                    Parent = Row;
                });
                if Detail then
                    Library:CreateLabel({
                        BackgroundTransparency = 1;
                        Position = UDim2.fromOffset(5, 18);
                        Size = UDim2.new(1, -35, 0, 16);
                        Text = Detail;
                        TextSize = 12;
                        TextTransparency = 0.35;
                        TextXAlignment = Enum.TextXAlignment.Left;
                        TextTruncate = Enum.TextTruncate.AtEnd;
                        ZIndex = 7;
                        Parent = Row;
                    });
                end;
                local Remove = Library:Create('TextButton', {
                    BackgroundTransparency = 1;
                    Position = UDim2.new(1, -28, 0, 0);
                    Size = UDim2.new(0, 28, 1, 0);
                    Text = '×';
                    TextSize = 18;
                    Font = Library.Font;
                    TextColor3 = Library.FontColor;
                    ZIndex = 8;
                    Parent = Row;
                });
                Library:AddToRegistry(Remove, { TextColor3 = 'FontColor'; });
                Remove.Activated:Connect(function()
                    if not Library:MouseIsOverOpenedFrame() and type(Info.OnRemove) == 'function' then
                        Library:SafeCallback(Info.OnRemove, Item.Id);
                    end;
                end);
            end;
            if Count == 0 then
                Library:CreateLabel({
                    Size = UDim2.new(1, 0, 0, 20);
                    Text = Info.EmptyText or 'No active tags';
                    TextSize = 13;
                    TextXAlignment = Enum.TextXAlignment.Left;
                    ZIndex = 6;
                    Parent = Frame;
                });
            end;
            Frame.Size = UDim2.new(1, -4, 0, Count == 0 and 20 or Height - 3);
            Groupbox:Resize();
        end;
        Tags:SetItems(Info.Items or {});
        Groupbox:AddBlank(5);
        Groupbox:Resize();
        return Tags;
    end;

    function Funcs:AddButton(...)
        -- TODO: Eventually redo this
        local Button = {};
        local function ProcessButtonParams(Class, Obj, ...)
            local Props = select(1, ...)
            if type(Props) == 'table' then
                Obj.Text = Props.Text
                Obj.Func = Props.Func
                Obj.DoubleClick = Props.DoubleClick
                Obj.ConfirmationTime = tonumber(Props.ConfirmationTime) or 0.5
                Obj.Tooltip = Props.Tooltip
            else
                Obj.Text = select(1, ...)
                Obj.Func = select(2, ...)
            end

            assert(type(Obj.Func) == 'function', 'AddButton: `Func` callback is missing.');
            Obj.Tooltip = Obj.Tooltip or (Library.ButtonTooltips and Library.ButtonTooltips[Obj.Text]);
        end

        ProcessButtonParams('Button', Button, ...)

        local Groupbox = self;
        local Container = Groupbox.Container;

        local function CreateBaseButton(Button)
            local Outer = Library:Create('Frame', {
                BackgroundTransparency = 1; -- no black frame: the inner frame's outline is the control's edge
                BorderSizePixel = 0;
                Size = UDim2.new(1, -4, 0, 20);
                ZIndex = 5;
            });

            local Inner = Library:Create('Frame', {
                BackgroundColor3 = Library.MainColor;
                BorderColor3 = Library.OutlineColor;
                BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.new(1, 0, 1, 0);
                ZIndex = 6;
                Parent = Outer;
            });

            local Label = Library:CreateLabel({
                Size = UDim2.new(1, 0, 1, 0);
                TextSize = 14;
                Text = Button.Text;
                ZIndex = 6;
                Parent = Inner;
            });

            Library:Create('UIGradient', {
                Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
                    ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212))
                });
                Rotation = 90;
                Parent = Inner;
            });

            Library:AddToRegistry(Inner, {
                BackgroundColor3 = 'MainColor';
                BorderColor3 = 'OutlineColor';
            });

            Library:OnHighlight(Outer, Inner,
                { BorderColor3 = 'AccentColor' },
                { BorderColor3 = 'OutlineColor' }
            );

            return Outer, Inner, Label
        end

        local function InitEvents(Button)
            local function WaitForEvent(event, timeout, validator)
                local bindable = Instance.new('BindableEvent')
                local resolved = false
                local connection = event:Once(function(...)
                    if resolved then return end
                    resolved = true
                    bindable:Fire(type(validator) == 'function' and validator(...) or false)
                end)
                task.delay(timeout, function()
                    if resolved then return end
                    resolved = true
                    connection:disconnect()
                    bindable:Fire(false)
                end)
                local Result = bindable.Event:Wait()
                bindable:Destroy()
                return Result
            end

            local function ValidateClick(Input)
                if Library:MouseIsOverOpenedFrame() then
                    return false
                end

                if not IsTap(Input) then
                    return false
                end

                return true
            end

            Button.Outer.InputBegan:Connect(function(Input)
                if not ValidateClick(Input) then return end
                if Button.Locked then return end

                -- press flash: accent, easing back to the normal fill (Library.Animations)
                if Library.Animations then
                    Button.Inner.BackgroundColor3 = Library.AccentColorDark
                    Library:Animate(Button.Inner, 0.3, { BackgroundColor3 = Library.MainColor })
                end

                if Button.DoubleClick then
                    Library:RemoveFromRegistry(Button.Label)
                    Library:AddToRegistry(Button.Label, { TextColor3 = 'AccentColor' })

                    Button.Label.TextColor3 = Library.AccentColor
                    Button.Label.Text = 'Are you sure?'
                    Button.Locked = true

                    local clicked = WaitForEvent(Button.Outer.InputBegan, math.clamp(Button.ConfirmationTime or 0.5, 0.1, 10), ValidateClick)

                    Library:RemoveFromRegistry(Button.Label)
                    Library:AddToRegistry(Button.Label, { TextColor3 = 'FontColor' })

                    Button.Label.TextColor3 = Library.FontColor
                    Button.Label.Text = Button.Text
                    task.defer(rawset, Button, 'Locked', false)

                    if clicked then
                        Library:SafeCallback(Button.Func)
                    end

                    return
                end

                Library:SafeCallback(Button.Func);
            end)
        end

        Button.Outer, Button.Inner, Button.Label = CreateBaseButton(Button)
        Button.Outer.Parent = Container

        InitEvents(Button)

        function Button:AddTooltip(tooltip)
            if type(tooltip) == 'string' then
                Library:AddToolTip(tooltip, self.Outer)
            end
            return self
        end


        function Button:AddButton(...)
            local SubButton = {}

            ProcessButtonParams('SubButton', SubButton, ...)

            -- Two halves of the full-width button (1, -4) with a 4 px gap. The sub button sizes from the first one
            -- instead of copying its AbsoluteSize, which went stale under UI scale / floating sections and pushed
            -- it past the box edge.
            self.Outer.Size = UDim2.new(0.5, -4, 0, 20)

            SubButton.Outer, SubButton.Inner, SubButton.Label = CreateBaseButton(SubButton)

            SubButton.Outer.Position = UDim2.new(1, 4, 0, 0)
            SubButton.Outer.Size = UDim2.new(1, 0, 1, 0)
            SubButton.Outer.Parent = self.Outer

            function SubButton:AddTooltip(tooltip)
                if type(tooltip) == 'string' then
                    Library:AddToolTip(tooltip, self.Outer)
                end
                return SubButton
            end

            if type(SubButton.Tooltip) == 'string' then
                SubButton:AddTooltip(SubButton.Tooltip)
            end

            InitEvents(SubButton)
            return SubButton
        end

        if type(Button.Tooltip) == 'string' then
            Button:AddTooltip(Button.Tooltip)
        end

        Groupbox:AddBlank(5);
        Groupbox:Resize();

        return Button;
    end;

    -- A block of help text: a title over a dimmer, wrapped body. Info = { Title, Text (or Content), Image, ImageHeight };
    -- a plain string is the body. With Image a banner comes first, cropped to fill ImageHeight px (default 72), with
    -- the title over its lower edge. Image: an rbxassetid / rbxthumb string, an asset id number, or (getcustomasset)
    -- an image URL or a workspace file path; a URL is downloaded once in the background and the banner appears when
    -- it is there. The body is wrapped again when the section's width changes. Paragraph:SetTitle(s), :SetText(s),
    -- :SetImage(source or nil) are safe from game callbacks.
    function Funcs:AddParagraph(Info)
        if type(Info) ~= 'table' then Info = { Text = Info }; end;

        local Groupbox = self;
        local Paragraph = { Title = Info.Title, Text = Info.Text or Info.Content, Image = Info.Image };
        local ImageHeight = tonumber(Info.ImageHeight) or 72;

        local Holder = Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(1, -4, 0, 0);
            ZIndex = 5;
            Parent = Groupbox.Container;
        });

        local Banner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 0, ImageHeight);
            Visible = false;
            ZIndex = 6;
            Parent = Holder;
        });
        local BannerStroke = Library:Create('UIStroke', {
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border;
            Color = Library.OutlineColor;
            Parent = Banner;
        });
        Library:AddToRegistry(Banner, { BackgroundColor3 = 'MainColor' });
        Library:AddToRegistry(BannerStroke, { Color = 'OutlineColor' });

        local Picture = Library:Create('ImageLabel', {
            BackgroundTransparency = 1;
            ScaleType = Enum.ScaleType.Crop;
            Size = UDim2.fromScale(1, 1);
            ZIndex = 7;
            Parent = Banner;
        });

        -- darkens the lower half of the picture so the title over it stays readable
        local Shade = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderSizePixel = 0;
            Size = UDim2.fromScale(1, 1);
            ZIndex = 8;
            Parent = Banner;
        });
        Library:Create('UIGradient', {
            Rotation = 90;
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.45, 1), NumberSequenceKeypoint.new(1, 0.15),
            });
            Parent = Shade;
        });

        for _, Rounded in next, { Banner, Picture, Shade } do
            Library:Create('UICorner', { CornerRadius = UDim.new(0, 4); Parent = Rounded });
        end;

        local Title = Library:CreateLabel({
            TextSize = 14;
            TextTruncate = Enum.TextTruncate.AtEnd;
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 9;
            Parent = Holder;
        });

        local Body = Library:CreateLabel({
            TextSize = 14;
            TextTransparency = 0.35; -- under the title in weight
            TextWrapped = true;
            TextXAlignment = Enum.TextXAlignment.Left;
            TextYAlignment = Enum.TextYAlignment.Top;
            ZIndex = 6;
            Parent = Holder;
        });

        -- unscaled, so the menu's zoom and the UI scale do not count as a new width
        local function InnerWidth()
            return math.floor(Holder.AbsoluteSize.X / ParentScaleOf(Holder) + 0.5);
        end;

        local Width, Asset;

        local function Layout()
            local HasImage = Asset ~= nil;
            local HasTitle = Paragraph.Title ~= nil and Paragraph.Title ~= '';
            local HasText = Paragraph.Text ~= nil and Paragraph.Text ~= '';
            local Y = 0;

            Banner.Visible = HasImage;
            Shade.Visible = HasTitle;
            Title.Visible = HasTitle;
            Title.Text = HasTitle and tostring(Paragraph.Title) or '';

            if HasImage then
                Picture.Image = Asset;
                Title.Position, Title.Size, Title.TextSize = UDim2.fromOffset(8, ImageHeight - 22), UDim2.new(1, -16, 0, 16), 15;
                Y = ImageHeight + (HasText and 6 or 0);
            elseif HasTitle then
                Title.Position, Title.Size, Title.TextSize = UDim2.new(), UDim2.new(1, 0, 0, 15), 14;
                Y = 15 + (HasText and 3 or 0);
            end;

            Width = InnerWidth();
            Body.Visible = HasText;

            if HasText then
                local Text = tostring(Paragraph.Text);
                local Height = select(2, Library:GetTextBounds(Text, Library.Font, 14, Vector2.new(math.max(Width, 1), math.huge)));
                Body.Text = Text;
                Body.Position = UDim2.fromOffset(0, Y);
                Body.Size = UDim2.new(1, 0, 0, Height + WRAP_SLACK); -- overhangs the holder: see WRAP_SLACK
                Y = Y + Height;
            end;

            Holder.Size = UDim2.new(1, -4, 0, Y);
            Groupbox:Resize();
        end;

        Holder:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()
            if InnerWidth() ~= Width then Layout(); end;
        end);

        -- sets Asset from Paragraph.Image; a URL or file is loaded off this thread and laid out when it is there
        local function LoadImage()
            local Source = Paragraph.Image;
            Asset = nil;

            if type(Source) == 'number' then
                Asset = 'rbxassetid://' .. Source;
            elseif type(Source) == 'string' and Source:find('^rbx') then
                Asset = Source;
            elseif type(Source) == 'string' and Source ~= '' then
                task.spawn(function()
                    local Ok, Result = pcall(ResolveImage, Source);
                    if Paragraph.Image ~= Source then return; end; -- changed while it downloaded

                    if Ok then
                        Asset = Result;
                        Library:RunOnUIThread(Layout);
                    else
                        Library:Notify('Paragraph image failed: ' .. tostring(Result), 4);
                    end;
                end);
            end;
        end;

        for _, Key in next, { 'Title', 'Text', 'Image' } do
            Paragraph['Set' .. Key] = function(_, Value)
                if Paragraph[Key] == Value then return; end;
                Paragraph[Key] = Value;
                if Key == 'Image' then LoadImage(); end;
                Library:RunOnUIThread(Layout);
            end;
        end;

        Paragraph.Holder = Holder;
        LoadImage();
        Layout();
        Groupbox:AddBlank(8); -- a wrapped block reads as part of the next control at a label's 5 px
        Groupbox:Resize();

        return Paragraph;
    end;

    function Funcs:AddDivider()
        local Groupbox = self;
        local Container = self.Container

        local Divider = {
            Type = 'Divider',
        }

        Groupbox:AddBlank(2);
        local DividerOuter = Library:Create('Frame', {
            BackgroundTransparency = 1; -- no black frame: the inner frame's outline is the control's edge
            BorderSizePixel = 0;
            Size = UDim2.new(1, -4, 0, 5);
            ZIndex = 5;
            Parent = Container;
        });

        local DividerInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 6;
            Parent = DividerOuter;
        });

        Library:AddToRegistry(DividerInner, {
            BackgroundColor3 = 'MainColor';
            BorderColor3 = 'OutlineColor';
        });

        Groupbox:AddBlank(9);
        Groupbox:Resize();
    end

    function Funcs:AddInput(Idx, Info)
        Info.Tooltip = Info.Tooltip or (Library.Tooltips and Library.Tooltips[Idx]);
        assert(Info.Text, 'AddInput: Missing `Text` string.')

        local Textbox = {
            Value = Info.Default or '';
            Numeric = Info.Numeric or false;
            Finished = Info.Finished or false;
            Type = 'Input';
            Callback = Info.Callback or function(Value) end;
        };

        local Groupbox = self;
        local Container = Groupbox.Container;

        local InputLabel = Library:CreateLabel({
            Size = UDim2.new(1, 0, 0, 15);
            TextSize = 14;
            Text = Info.Text;
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 5;
            Parent = Container;
        });

        Groupbox:AddBlank(1);

        local TextBoxOuter = Library:Create('Frame', {
            BackgroundTransparency = 1; -- no black frame: the inner frame's outline is the control's edge
            BorderSizePixel = 0;
            Size = UDim2.new(1, -4, 0, 20);
            ZIndex = 5;
            Parent = Container;
        });

        local TextBoxInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 6;
            Parent = TextBoxOuter;
        });

        Library:AddToRegistry(TextBoxInner, {
            BackgroundColor3 = 'MainColor';
            BorderColor3 = 'OutlineColor';
        });

        Library:OnHighlight(TextBoxOuter, TextBoxInner,
            { BorderColor3 = 'AccentColor' },
            { BorderColor3 = 'OutlineColor' }
        );

        if type(Info.Tooltip) == 'string' then
            Library:AddToolTip(Info.Tooltip, TextBoxOuter)
        end

        Library:Create('UIGradient', {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212))
            });
            Rotation = 90;
            Parent = TextBoxInner;
        });

        local Container = Library:Create('Frame', {
            BackgroundTransparency = 1;
            ClipsDescendants = true;

            Position = UDim2.new(0, 5, 0, 0);
            Size = UDim2.new(1, -5, 1, 0);

            ZIndex = 7;
            Parent = TextBoxInner;
        })

        local Box = Library:Create('TextBox', {
            BackgroundTransparency = 1;

            Position = UDim2.fromOffset(0, 0),
            Size = UDim2.fromScale(5, 1),

            Font = Library.Font;
            PlaceholderColor3 = Color3.fromRGB(190, 190, 190);
            PlaceholderText = Info.Placeholder or '';

            Text = Info.Default or '';
            TextColor3 = Library.FontColor;
            TextSize = 14;
            TextStrokeTransparency = 0;
            TextXAlignment = Enum.TextXAlignment.Left;

            ZIndex = 7;
            Parent = Container;
        });

        Library:ApplyTextStroke(Box);

        function Textbox:SetValue(Text)
            if Library:NeedsUIThread() then
                return Library:RunOnUIThread(Textbox.SetValue, Textbox, Text);
            end;

            if Info.MaxLength and #Text > Info.MaxLength then
                Text = Text:sub(1, Info.MaxLength);
            end;

            if Textbox.Numeric then
                if (not tonumber(Text)) and Text:len() > 0 then
                    Text = Textbox.Value
                end
            end

            Textbox.Value = Text;
            Box.Text = Text;

            Library:SafeCallback(Textbox.Callback, Textbox.Value);
            Library:SafeCallback(Textbox.Changed, Textbox.Value);
            Library:AttemptSave();
        end;

        -- Flush a draft synchronously before actions that consume an input (e.g. saving a preset).
        function Textbox:Commit()
            if Library:NeedsUIThread() then
                return Library:RunOnUIThread(Textbox.Commit, Textbox);
            end;
            Textbox:SetValue(Box.Text);
            return Textbox.Value;
        end;

        if Textbox.Finished then
            -- Finished inputs commit on Enter and when clicking elsewhere.
            Box.FocusLost:Connect(function()
                Textbox:SetValue(Box.Text);
                Library:AttemptSave();
            end)
        else
            Box:GetPropertyChangedSignal('Text'):Connect(function()
                Textbox:SetValue(Box.Text);
                Library:AttemptSave();
            end);
        end

        -- https://devforum.roblox.com/t/how-to-make-textboxes-follow-current-cursor-position/1368429/6
        -- thank you nicemike40 :)

        local function Update()
            local PADDING = 2
            local reveal = Container.AbsoluteSize.X

            if not Box:IsFocused() or Box.TextBounds.X <= reveal - 2 * PADDING then
                -- we aren't focused, or we fit so be normal
                Box.Position = UDim2.new(0, PADDING, 0, 0)
            else
                -- we are focused and don't fit, so adjust position
                local cursor = Box.CursorPosition
                if cursor ~= -1 then
                    -- calculate pixel width of text from start to cursor
                    local subtext = string.sub(Box.Text, 1, cursor-1)
                    local width = TextService:GetTextSize(subtext, Box.TextSize, Box.Font, Vector2.new(math.huge, math.huge)).X

                    -- check if we're inside the box with the cursor
                    local currentCursorPos = Box.Position.X.Offset + width

                    -- adjust if necessary
                    if currentCursorPos < PADDING then
                        Box.Position = UDim2.fromOffset(PADDING-width, 0)
                    elseif currentCursorPos > reveal - PADDING - 1 then
                        Box.Position = UDim2.fromOffset(reveal-width-PADDING-1, 0)
                    end
                end
            end
        end

        task.spawn(Update)

        Box:GetPropertyChangedSignal('Text'):Connect(Update)
        Box:GetPropertyChangedSignal('CursorPosition'):Connect(Update)
        Box.FocusLost:Connect(Update)
        Box.Focused:Connect(Update)

        Library:AddToRegistry(Box, {
            TextColor3 = 'FontColor';
        });

        function Textbox:OnChanged(Func)
            Textbox.Changed = Func;
            Func(Textbox.Value);
        end;

        Groupbox:AddBlank(5);
        Groupbox:Resize();

        Options[Idx] = Textbox;

        return Textbox;
    end;

    function Funcs:AddToggle(Idx, Info)
        Info.Tooltip = Info.Tooltip or (Library.Tooltips and Library.Tooltips[Idx]);
        assert(Info.Text, 'AddInput: Missing `Text` string.')

        local Toggle = {
            Value = Info.Default or false;
            Type = 'Toggle';

            Callback = Info.Callback or function(Value) end;
            Addons = {},
            Risky = Info.Risky,
        };

        local Groupbox = self;
        local Container = Groupbox.Container;

        -- Rounded checkbox in the look of a selected row of a dropdown list: on, the box takes a faint accent tint,
        -- an accent outline and a check; the tint grows from the centre. The label dims while off, so the active
        -- options stand out at a glance.
        -- The on / off state is the tint's size, never its transparency: the menu's fades own every transparency,
        -- and a toggle switched while the menu is hidden (a keybind, a loading config) must still come back right.
        local TINT = 0.65;
        local CHECK_SIZE = UDim2.fromScale(0.75, 0.75);
        local ToggleOuter = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderSizePixel = 0;
            Size = UDim2.new(0, 13, 0, 13);
            ZIndex = 5;
            Parent = Container;
        });

        Library:AddToRegistry(ToggleOuter, {
            BackgroundColor3 = 'MainColor';
        });

        Library:Create('UICorner', {
            CornerRadius = UDim.new(0, 3);
            Parent = ToggleOuter;
        });

        -- Off: the outline color lifted toward the font color. The plain outline color nearly matches the background
        -- on dark themes (Catppuccin, Midnight Ocean, ...), so an off toggle looked like it had no box at all.
        local function OffStrokeColor()
            return Library.OutlineColor:Lerp(Library.FontColor, 0.35);
        end;

        local ToggleStroke = Library:Create('UIStroke', {
            Color = OffStrokeColor();
            Thickness = 1;
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border;
            Parent = ToggleOuter;
        });

        Library:AddToRegistry(ToggleStroke, {
            Color = OffStrokeColor;
        });

        local ToggleInner = Library:Create('Frame', {
            AnchorPoint = Vector2.new(0.5, 0.5);
            Position = UDim2.fromScale(0.5, 0.5);
            BackgroundColor3 = Library.AccentColor;
            BackgroundTransparency = TINT;
            BorderSizePixel = 0;
            Size = UDim2.fromScale(0, 0);
            ZIndex = 6;
            Parent = ToggleOuter;
        });

        Library:AddToRegistry(ToggleInner, {
            BackgroundColor3 = 'AccentColor';
        });

        Library:Create('UICorner', {
            CornerRadius = UDim.new(0, 3); -- the box's own corners: the tint fills it edge to edge
            Parent = ToggleInner;
        });

        -- Lucide check over the tint, in the font color as in the dropdown list; shown only while on
        local ToggleCheck = Library:CreateIcon('check', {
            AnchorPoint = Vector2.new(0.5, 0.5);
            Color = 'FontColor';
            Position = UDim2.fromScale(0.5, 0.5);
            Size = CHECK_SIZE;
            Thickness = 2;
            ZIndex = 7;
            Parent = ToggleOuter;
        });

        local ToggleGlow = Library:AddGlow(ToggleOuter, 7, 4, 'AccentColor');
        Library:TrackElementGlow(ToggleGlow, function() return Toggle.Value; end);

        local ToggleLabel = Library:CreateLabel({
            Size = UDim2.new(0, 216, 1, 0);
            Position = UDim2.new(1, 7, 0, 0);
            TextSize = 14;
            Text = Info.Text;
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 6;
            Parent = ToggleOuter;
        });

        local ToggleLabelStroke = ToggleLabel:FindFirstChildOfClass('UIStroke');

        Library:Create('UIListLayout', {
            Padding = UDim.new(0, 4);
            FillDirection = Enum.FillDirection.Horizontal;
            HorizontalAlignment = Enum.HorizontalAlignment.Right;
            SortOrder = Enum.SortOrder.LayoutOrder;
            Parent = ToggleLabel;
        });

        local ToggleRegion = Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(0, 170, 1, 0);
            ZIndex = 8;
            Parent = ToggleOuter;
        });

        local Hovering = false;
        local FadeInfo = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);

        -- Outline follows the accent while the toggle is on or hovered.
        local function UpdateStroke()
            local Accent = Toggle.Value or Hovering;
            ToggleStroke.Color = Accent and Library.AccentColor or OffStrokeColor();

            local Reg = Library.RegistryMap[ToggleStroke];
            if Reg then
                Reg.Properties.Color = Accent and 'AccentColor' or OffStrokeColor;
            end;
        end;

        ToggleRegion.MouseEnter:Connect(function()
            Hovering = true;
            UpdateStroke();
        end);

        ToggleRegion.MouseLeave:Connect(function()
            Hovering = false;
            UpdateStroke();
        end);

        function Toggle:UpdateColors()
            Toggle:Display(true);
        end;

        if type(Info.Tooltip) == 'string' then
            Library:AddToolTip(Info.Tooltip, ToggleRegion)
        end

        function Toggle:Display(Instant)
            local On = Toggle.Value;
            local FillSize = On and UDim2.fromScale(1, 1) or UDim2.fromScale(0, 0);
            local LabelFade = On and 0 or 0.35;

            Library:RememberTransparency(ToggleLabel, 'TextTransparency', LabelFade);
            if ToggleLabelStroke then
                Library:RememberTransparency(ToggleLabelStroke, 'Transparency', LabelFade);
            end;

            UpdateStroke();
            Library:ApplyElementGlow(ToggleGlow, Instant);
            ToggleCheck.Visible = On; -- grows with the fill; hides at once on off (a shrinking check leaves dots)

            if Instant then
                ToggleCheck.Size = CHECK_SIZE;
                ToggleInner.Size = FillSize;
                ToggleLabel.TextTransparency = LabelFade;
                if ToggleLabelStroke then
                    ToggleLabelStroke.Transparency = LabelFade;
                end;
            else
                Library:CreateTween(ToggleInner, FadeInfo, { Size = FillSize }):Play();
                if On then
                    ToggleCheck.Size = UDim2.fromScale(0, 0);
                    Library:CreateTween(ToggleCheck, FadeInfo, { Size = CHECK_SIZE }):Play();
                end;
                Library:CreateTween(ToggleLabel, FadeInfo, { TextTransparency = LabelFade }):Play();
                if ToggleLabelStroke then
                    Library:CreateTween(ToggleLabelStroke, FadeInfo, { Transparency = LabelFade }):Play();
                end;
            end;
        end;

        function Toggle:OnChanged(Func)
            Toggle.Changed = Func;
            Func(Toggle.Value);
        end;

        function Toggle:SetValue(Bool)
            if Library:NeedsUIThread() then
                return Library:RunOnUIThread(Toggle.SetValue, Toggle, Bool);
            end;

            Bool = (not not Bool);

            Toggle.Value = Bool;
            Toggle:Display();

            for _, Addon in next, Toggle.Addons do
                if Addon.Type == 'KeyPicker' and Addon.SyncToggleState then
                    Addon.Toggled = Bool
                    Addon:Update()
                end
            end

            Library:SafeCallback(Toggle.Callback, Toggle.Value);
            Library:SafeCallback(Toggle.Changed, Toggle.Value);
            Library:UpdateDependencyBoxes();
            Library:AttemptSave();
        end;

        ToggleRegion.InputBegan:Connect(function(Input)
            if IsTap(Input) and not Library:MouseIsOverOpenedFrame() then
                Toggle:SetValue(not Toggle.Value) -- Why was it not like this from the start?
                Library:AttemptSave();
            end;
        end);

        if Toggle.Risky then
            Library:RemoveFromRegistry(ToggleLabel)
            ToggleLabel.TextColor3 = Library.RiskColor
            Library:AddToRegistry(ToggleLabel, { TextColor3 = 'RiskColor' })
        end

        Toggle:Display(true);
        Groupbox:AddBlank(Info.BlankSize or 5 + 2);
        Groupbox:Resize();

        Toggle.TextLabel = ToggleLabel;
        Toggle.Container = Container;
        setmetatable(Toggle, BaseAddons);

        Toggles[Idx] = Toggle;

        Library:UpdateDependencyBoxes();

        return Toggle;
    end;

    function Funcs:AddSlider(Idx, Info)
        Info.Tooltip = Info.Tooltip or (Library.Tooltips and Library.Tooltips[Idx]);
        assert(Info.Default, 'AddSlider: Missing default value.');
        assert(Info.Text, 'AddSlider: Missing slider text.');
        assert(Info.Min, 'AddSlider: Missing minimum value.');
        assert(Info.Max, 'AddSlider: Missing maximum value.');
        assert(Info.Rounding, 'AddSlider: Missing rounding value.');

        local Slider = {
            Value = Info.Default;
            Min = Info.Min;
            Max = Info.Max;
            Rounding = Info.Rounding;
            MaxSize = 232;
            Type = 'Slider';
            Callback = Info.Callback or function(Value) end;
        };

        local Groupbox = self;
        local Container = Groupbox.Container;

        if not Info.Compact then
            Library:CreateLabel({
                Size = UDim2.new(1, 0, 0, 10);
                TextSize = 14;
                Text = Info.Text;
                TextXAlignment = Enum.TextXAlignment.Left;
                TextYAlignment = Enum.TextYAlignment.Bottom;
                ZIndex = 5;
                Parent = Container;
            });

            Groupbox:AddBlank(3);
        end

        local SliderOuter = Library:Create('Frame', {
            BackgroundTransparency = 1; -- no black frame: the inner frame's outline is the control's edge
            BorderSizePixel = 0;
            Size = UDim2.new(1, -4, 0, 13);
            ZIndex = 5;
            Parent = Container;
        });

        local SliderInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 6;
            Parent = SliderOuter;
        });

        Library:AddToRegistry(SliderInner, {
            BackgroundColor3 = 'MainColor';
            BorderColor3 = 'OutlineColor';
        });

        local Fill = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BorderColor3 = Library.AccentColorDark;
            Size = UDim2.new(0, 0, 1, 0);
            ZIndex = 7;
            Parent = SliderInner;
        });

        Library:AddToRegistry(Fill, {
            BackgroundColor3 = 'AccentColor';
            BorderColor3 = 'AccentColorDark';
        });

        local FillGlow = Library:AddGlow(Fill, 6, 6, 'AccentColor');
        -- the value, not Fill.Size: the fill is tweened, and right after a change it still has its old width
        Library:TrackElementGlow(FillGlow, function() return Slider.Value > Slider.Min; end);

        local HideBorderRight = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BorderSizePixel = 0;
            Position = UDim2.new(1, 0, 0, 0);
            Size = UDim2.new(0, 1, 1, 0);
            ZIndex = 8;
            Parent = Fill;
        });

        Library:AddToRegistry(HideBorderRight, {
            BackgroundColor3 = 'AccentColor';
        });

        local DisplayLabel = Library:CreateLabel({
            Size = UDim2.new(1, 0, 1, 0);
            TextSize = 14;
            Text = 'Infinite';
            ZIndex = 9;
            Parent = SliderInner;
        });

        Library:OnHighlight(SliderOuter, SliderInner,
            { BorderColor3 = 'AccentColor' },
            { BorderColor3 = 'OutlineColor' }
        );

        if type(Info.Tooltip) == 'string' then
            Library:AddToolTip(Info.Tooltip, SliderOuter)
        end

        function Slider:UpdateColors()
            Fill.BackgroundColor3 = Library.AccentColor;
            Fill.BorderColor3 = Library.AccentColorDark;
        end;

        function Slider:Display()
            local Suffix = Info.Suffix or '';

            -- Info.Format(Value) -> text, for values that mean something special (e.g. "Default" at the minimum)
            local Shown = Info.Format and tostring(Info.Format(Slider.Value)) or nil;

            if Info.Compact then
                DisplayLabel.Text = Info.Text .. ': ' .. (Shown or (Slider.Value .. Suffix))
            elseif Info.HideMax or Shown then
                DisplayLabel.Text = Shown or string.format('%s', Slider.Value .. Suffix)
            else
                DisplayLabel.Text = string.format('%s/%s', Slider.Value .. Suffix, Slider.Max .. Suffix);
            end

            local X = math.ceil(Library:MapValue(Slider.Value, Slider.Min, Slider.Max, 0, Slider.MaxSize));
            Library:Animate(Fill, 0.08, { Size = UDim2.new(0, X, 1, 0) });
            Library:ApplyElementGlow(FillGlow, true);

            HideBorderRight.Visible = not (X == Slider.MaxSize or X == 0);
        end;

        function Slider:OnChanged(Func)
            Slider.Changed = Func;
            Func(Slider.Value);
        end;

        local function Round(Value)
            if Slider.Rounding == 0 then
                return math.floor(Value);
            end;


            return tonumber(string.format('%.' .. Slider.Rounding .. 'f', Value))
        end;

        function Slider:GetValueFromXOffset(X)
            return Round(Library:MapValue(X, 0, Slider.MaxSize, Slider.Min, Slider.Max));
        end;

        function Slider:SetValue(Str)
            if Library:NeedsUIThread() then
                return Library:RunOnUIThread(Slider.SetValue, Slider, Str);
            end;

            local Num = tonumber(Str);

            if (not Num) then
                return;
            end;

            Num = math.clamp(Num, Slider.Min, Slider.Max);

            Slider.Value = Num;
            Slider:Display();

            Library:SafeCallback(Slider.Callback, Slider.Value);
            Library:SafeCallback(Slider.Changed, Slider.Value);
            Library:AttemptSave();
        end;

        -- The value under the pointer (mouse, or the last touch).
        local function FollowPointer()
            -- Mouse is in screen pixels, the track width (MaxSize) is unscaled; divide by the window
            -- scale so the fill tracks the cursor at any UI scale.
            local Scale = Library.WindowScale and Library.WindowScale.Scale or 1;
            local nX = math.clamp((Mouse.X - SliderInner.AbsolutePosition.X) / Scale, 0, Slider.MaxSize);

            local nValue = Slider:GetValueFromXOffset(nX);
            local OldValue = Slider.Value;
            Slider.Value = nValue;

            Slider:Display();

            if nValue ~= OldValue then
                Library:SafeCallback(Slider.Callback, Slider.Value);
                Library:SafeCallback(Slider.Changed, Slider.Value);
            end;
        end;

        SliderInner.InputBegan:Connect(function(Input)
            if not IsClick(Input) or Library:MouseIsOverOpenedFrame() then
                return;
            end;

            -- A finger: the way it first moves says what it is doing. Sideways drags the slider; up or down is a
            -- swipe scrolling the menu, which used to drag the value of every slider it started on. A tap puts the
            -- value where it landed. While dragging, the menu does not scroll away under the finger.
            local Scroller;

            if Input.UserInputType == Enum.UserInputType.Touch then
                local Start = Input.Position;

                while true do
                    local Move = Input.Position - Start;

                    if math.abs(Move.X) > TAP_SLOP and math.abs(Move.X) >= math.abs(Move.Y) then
                        break;
                    elseif Move.Magnitude > TAP_SLOP then
                        return;
                    end;

                    local State = Input.UserInputState;

                    if State ~= Enum.UserInputState.Begin and State ~= Enum.UserInputState.Change then
                        if State == Enum.UserInputState.End and not LongPressed[Input] then
                            FollowPointer();
                            Library:AttemptSave();
                        end;

                        return;
                    end;

                    RenderStepped:Wait();
                end;

                Scroller = SliderInner:FindFirstAncestorWhichIsA('ScrollingFrame');

                if Scroller then
                    Scroller.ScrollingEnabled = false;
                end;
            end;

            while IsHeld() do
                FollowPointer();
                RenderStepped:Wait();
            end;

            if Scroller then
                Scroller.ScrollingEnabled = true;
            end;

            Library:AttemptSave();
        end);

        -- Track width follows the real slider width (so custom window sizes work) instead of a fixed 232px.
        local function UpdateMaxSize()
            local Scale = Library.WindowScale and Library.WindowScale.Scale or 1;
            local Width = math.floor(SliderInner.AbsoluteSize.X / Scale + 0.5);

            if Width > 0 and Width ~= Slider.MaxSize then
                Slider.MaxSize = Width;
                Slider:Display();
            end;
        end;

        SliderInner:GetPropertyChangedSignal('AbsoluteSize'):Connect(UpdateMaxSize);
        UpdateMaxSize();

        Slider:Display();
        Groupbox:AddBlank(Info.BlankSize or 6);
        Groupbox:Resize();

        Options[Idx] = Slider;

        return Slider;
    end;

    -- Read-only progress bar in the Linoria frame style (black outer border, inset inner frame, accent fill) but
    -- deliberately unlike a slider so it never looks draggable: name on the left and value on the right of a row,
    -- over a thin bar with no text inside. Update it with Options.<Idx>:SetValue(n); safe from game callbacks.
    --   Groupbox:AddProgressBar('Level', { Text = 'Level progress', Default = 40, Min = 0, Max = 100 })
    --   Info.Format(Value, Min, Max) -> string customises the readout; otherwise Info.Suffix or a percentage.
    function Funcs:AddProgressBar(Idx, Info)
        Info.Tooltip = Info.Tooltip or (Library.Tooltips and Library.Tooltips[Idx]);
        assert(Info.Text, 'AddProgressBar: Missing `Text` string.');

        local ProgressBar = {
            Value = Info.Default or 0;
            Min = Info.Min or 0;
            Max = Info.Max or 100;
            Type = 'ProgressBar';
        };

        local Groupbox = self;
        local Container = Groupbox.Container;

        local Row = Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(1, -4, 0, 14);
            ZIndex = 5;
            Parent = Container;
        });

        local TitleLabel = Library:CreateLabel({
            Size = UDim2.new(1, 0, 1, 0);
            TextSize = 14;
            Text = Info.Text;
            TextTruncate = Enum.TextTruncate.AtEnd;
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 5;
            Parent = Row;
        });

        local ValueLabel = Library:CreateLabel({
            Size = UDim2.new(1, 0, 1, 0);
            TextSize = 14;
            Text = '';
            TextXAlignment = Enum.TextXAlignment.Right;
            ZIndex = 5;
            Parent = Row;
        });

        Groupbox:AddBlank(2);

        local BarOuter = Library:Create('Frame', {
            BackgroundTransparency = 1; -- no black frame: the inner frame's outline is the control's edge
            BorderSizePixel = 0;
            Size = UDim2.new(1, -4, 0, 8);
            ZIndex = 5;
            Parent = Container;
        });

        local BarInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 6;
            Parent = BarOuter;
        });

        Library:AddToRegistry(BarInner, {
            BackgroundColor3 = 'MainColor';
            BorderColor3 = 'OutlineColor';
        });

        local Fill = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BorderColor3 = Library.AccentColorDark;
            Size = UDim2.new(0, 0, 1, 0);
            ZIndex = 7;
            Parent = BarInner;
        });

        Library:AddToRegistry(Fill, {
            BackgroundColor3 = 'AccentColor';
            BorderColor3 = 'AccentColorDark';
        });

        local FillGlow = Library:AddGlow(Fill, 6, 6, 'AccentColor');
        Library:TrackElementGlow(FillGlow, function() return ProgressBar:GetFraction() > 0; end);

        local HideBorderRight = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BorderSizePixel = 0;
            Position = UDim2.new(1, 0, 0, 0);
            Size = UDim2.new(0, 1, 1, 0);
            ZIndex = 8;
            Parent = Fill;
        });

        Library:AddToRegistry(HideBorderRight, {
            BackgroundColor3 = 'AccentColor';
        });

        if type(Info.Tooltip) == 'string' then
            Library:AddToolTip(Info.Tooltip, BarOuter);
        end;

        local FillInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);

        function ProgressBar:GetFraction()
            local Range = ProgressBar.Max - ProgressBar.Min;

            if Range <= 0 then
                return 0;
            end;

            return math.clamp((ProgressBar.Value - ProgressBar.Min) / Range, 0, 1);
        end;

        function ProgressBar:UpdateColors()
            Fill.BackgroundColor3 = Library.AccentColor;
            Fill.BorderColor3 = Library.AccentColorDark;
        end;

        function ProgressBar:Display(Instant)
            local Fraction = ProgressBar:GetFraction();
            local Goal = UDim2.new(Fraction, 0, 1, 0);
            local Readout;

            if type(Info.Format) == 'function' then
                Readout = tostring(Info.Format(ProgressBar.Value, ProgressBar.Min, ProgressBar.Max));
            elseif Info.Suffix then
                Readout = tostring(ProgressBar.Value) .. Info.Suffix;
            else
                Readout = string.format('%d%%', math.floor(Fraction * 100 + 0.5));
            end;

            ValueLabel.Text = Readout;

            -- The name gives up room (truncating with "...") rather than running under the value.
            TitleLabel.Size = UDim2.new(1, -(Library:GetTextBounds(Readout, Library.Font, 14) + 8), 1, 0);

            if Instant then
                Fill.Size = Goal;
            else
                Library:CreateTween(Fill, FillInfo, { Size = Goal }):Play();
            end;

            HideBorderRight.Visible = not (Fraction == 1 or Fraction == 0);
            Library:ApplyElementGlow(FillGlow);
        end;

        function ProgressBar:SetValue(Value)
            if Library:NeedsUIThread() then
                return Library:RunOnUIThread(ProgressBar.SetValue, ProgressBar, Value);
            end;

            Value = tonumber(Value);

            if not Value then
                return;
            end;

            ProgressBar.Value = math.clamp(Value, ProgressBar.Min, math.max(ProgressBar.Min, ProgressBar.Max));
            ProgressBar:Display();
        end;

        function ProgressBar:SetText(Text)
            if Library:NeedsUIThread() then
                return Library:RunOnUIThread(ProgressBar.SetText, ProgressBar, Text);
            end;

            TitleLabel.Text = tostring(Text);
        end;

        -- Change the range, e.g. when the next level needs more XP. Keeps the current value inside it.
        function ProgressBar:SetRange(Min, Max)
            if Library:NeedsUIThread() then
                return Library:RunOnUIThread(ProgressBar.SetRange, ProgressBar, Min, Max);
            end;

            ProgressBar.Min = tonumber(Min) or ProgressBar.Min;
            ProgressBar.Max = tonumber(Max) or ProgressBar.Max;
            ProgressBar:SetValue(ProgressBar.Value);
        end;

        ProgressBar:Display(true);
        Groupbox:AddBlank(Info.BlankSize or 6);
        Groupbox:Resize();

        Options[Idx] = ProgressBar;

        return ProgressBar;
    end;

    function Funcs:AddDropdown(Idx, Info)
        Info.Tooltip = Info.Tooltip or (Library.Tooltips and Library.Tooltips[Idx]);
        Info.ValueTooltips = Info.ValueTooltips or (Library.DropdownDescriptions and Library.DropdownDescriptions[Idx]);
        if Info.SpecialType == 'Player' then
            Info.Values = GetPlayersString();
            Info.AllowNull = true;
        elseif Info.SpecialType == 'Team' then
            Info.Values = GetTeamsString();
            Info.AllowNull = true;
        end;

        assert(Info.Values, 'AddDropdown: Missing dropdown value list.');
        assert(Info.AllowNull or Info.Default, 'AddDropdown: Missing default value. Pass `AllowNull` as true if this was intentional.')

        if (not Info.Text) then
            Info.Compact = true;
        end;

        local Dropdown = {
            Values = Info.Values;
            Value = Info.Multi and {};
            Multi = Info.Multi;
            Type = 'Dropdown';
            SpecialType = Info.SpecialType; -- can be either 'Player' or 'Team'
            Callback = Info.Callback or function(Value) end;
        };
        -- Info.ValueIcons: the image id shown in front of an option ('' or nil = none).
        function Dropdown:GetValueIcon(Value)
            local Icons = Info.ValueIcons;
            if Value == nil then return '' end;
            if type(Icons) == 'function' then
                local Ok, Image = pcall(Icons, Value);
                return Ok and type(Image) == 'string' and Image or '';
            end;
            return type(Icons) == 'table' and type(Icons[Value]) == 'string' and Icons[Value] or '';
        end;
        function Dropdown:GetValueTooltip(Value)
            if Value == nil then return nil end;
            local Descriptions = Info.ValueTooltips;
            if type(Descriptions) == 'function' then
                local Ok, Text = pcall(Descriptions, Value);
                if Ok and type(Text) == 'string' and Text ~= '' then return Text end;
            elseif type(Descriptions) == 'table' and type(Descriptions[Value]) == 'string' then
                return Descriptions[Value];
            end;
            return tostring(Value);
        end;

        local Groupbox = self;
        local Container = Groupbox.Container;

        -- Reveal overflowing text, fade out, reset, fade in, and repeat while active.
        -- Each label owns one tween and completion connection; rebuild/close cancels both.
        local function AddTextScroll(Label, Clip, HoverTarget, ScrollOnChange)
            local Controller = { Wanted = false, Tween = nil, Completion = nil, Serial = 0 };
            local TextTransparency = Label.TextTransparency;
            local Stroke = Label:FindFirstChildOfClass('UIStroke');
            local StrokeTransparency = Stroke and Stroke.Transparency or 0;

            local function IsVisible()
                local Object = Label;
                while Object do
                    if Object:IsA('GuiObject') and not Object.Visible then return false end;
                    if Object:IsA('ScreenGui') and not Object.Enabled then return false end;
                    Object = Object.Parent;
                end;
                return Label.Parent ~= nil;
            end;

            function Controller:Stop()
                self.Serial = self.Serial + 1;
                if self.Completion then
                    self.Completion:Disconnect();
                    self.Completion = nil;
                end;
                if self.Tween then
                    self.Tween:Cancel();
                    self.Tween = nil;
                end;
                Label.Position = UDim2.fromOffset(0, 0);
                Label.TextTransparency = TextTransparency;
                if Stroke then Stroke.Transparency = StrokeTransparency end;
            end;

            function Controller:Refresh()
                self:Stop();
                local Scale = Library.UIScale or 1;
                local Width = Clip.AbsoluteSize.X / Scale;
                if Width <= 0 then return end;
                local TextWidth = Library:GetTextBounds(Label.Text, Label.Font, Label.TextSize, Vector2.new(100000, 100000));
                local Overflow = math.max(0, math.ceil(TextWidth) - Width);
                Label.Size = UDim2.new(0, math.max(Width, math.ceil(TextWidth)), 1, 0);
                if not self.Wanted or Overflow <= 0 or not Library.Animations or not IsVisible() then return end;
                local Serial = self.Serial;

                local function PlayPhase(Info, Goal, Finished)
                    if self.Serial ~= Serial then return end;
                    if not self.Wanted or not Library.Animations or not IsVisible() then
                        self:Stop();
                        return;
                    end;
                    local Tween = Library:CreateTween(Label, Info, Goal);
                    self.Tween = Tween;
                    self.Completion = Tween.Completed:Connect(function(State)
                        if self.Serial ~= Serial then return end;
                        self.Completion:Disconnect();
                        self.Completion = nil;
                        self.Tween = nil;
                        if State == Enum.PlaybackState.Completed then Finished() end;
                    end);
                    Tween:Play();
                end;

                local Scroll;
                Scroll = function()
                    PlayPhase(
                        TweenInfo.new(math.clamp(Overflow / 35, 0.6, 8), Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0.35),
                        { Position = UDim2.fromOffset(-Overflow, 0) },
                        function()
                            PlayPhase(TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.6),
                                { TextTransparency = 1 }, function()
                                    Label.Position = UDim2.fromOffset(0, 0);
                                    PlayPhase(TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                                        { TextTransparency = TextTransparency }, Scroll);
                                end);
                        end);
                end;
                Scroll();
            end;

            -- Fade the text outline together with the glyphs.
            if Stroke then
                Label:GetPropertyChangedSignal('TextTransparency'):Connect(function()
                    local Alpha = math.clamp((Label.TextTransparency - TextTransparency) / math.max(1 - TextTransparency, 0.001), 0, 1);
                    Stroke.Transparency = StrokeTransparency + (1 - StrokeTransparency) * Alpha;
                end);
            end;
            HoverTarget.MouseEnter:Connect(function()
                Controller.Wanted = true;
                Controller:Refresh();
            end);
            HoverTarget.MouseLeave:Connect(function()
                Controller.Wanted = false;
                Controller:Stop();
            end);
            Label:GetPropertyChangedSignal('Text'):Connect(function()
                Controller.Wanted = ScrollOnChange or Controller.Wanted;
                Controller:Refresh();
            end);
            Label:GetPropertyChangedSignal('TextSize'):Connect(function() Controller:Refresh(); end);
            Label:GetPropertyChangedSignal('Font'):Connect(function() Controller:Refresh(); end);
            Clip:GetPropertyChangedSignal('AbsoluteSize'):Connect(function() Controller:Refresh(); end);
            Clip.Destroying:Connect(function() Controller:Stop(); end);
            Controller:Refresh();
            return Controller;
        end;

        local RelativeOffset = 0;

        if not Info.Compact then
            local DropdownLabel = Library:CreateLabel({
                Size = UDim2.new(1, 0, 0, 10);
                TextSize = 14;
                Text = Info.Text;
                TextXAlignment = Enum.TextXAlignment.Left;
                TextYAlignment = Enum.TextYAlignment.Bottom;
                ZIndex = 5;
                Parent = Container;
            });

            Groupbox:AddBlank(3);
        end

        for _, Element in next, Container:GetChildren() do
            if not Element:IsA('UIListLayout') then
                RelativeOffset = RelativeOffset + Element.Size.Y.Offset;
            end;
        end;

        local DropdownOuter = Library:Create('Frame', {
            BackgroundTransparency = 1; -- no black frame: the inner frame's outline is the control's edge
            BorderSizePixel = 0;
            Size = UDim2.new(1, -4, 0, 20);
            ZIndex = 5;
            Parent = Container;
        });

        local DropdownInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 6;
            Parent = DropdownOuter;
        });

        Library:AddToRegistry(DropdownInner, {
            BackgroundColor3 = 'MainColor';
            BorderColor3 = 'OutlineColor';
        });

        Library:Create('UIGradient', {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(212, 212, 212))
            });
            Rotation = 90;
            Parent = DropdownInner;
        });

        local DropdownArrow = Library:Create('ImageLabel', {
            AnchorPoint = Vector2.new(0, 0.5);
            BackgroundTransparency = 1;
            Position = UDim2.new(1, -16, 0.5, 0);
            Size = UDim2.new(0, 12, 0, 12);
            Image = 'http://www.roblox.com/asset/?id=6282522798';
            ZIndex = 8;
            Parent = DropdownInner;
        });

        local ItemClip = Library:Create('Frame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            ClipsDescendants = true;
            Position = UDim2.new(0, 5, 0, 0);
            Size = UDim2.new(1, -25, 1, 0);
            ZIndex = 7;
            Parent = DropdownInner;
        });

        local ItemList = Library:CreateLabel({
            Position = UDim2.fromOffset(0, 0);
            Size = UDim2.new(1, 0, 1, 0);
            TextSize = 14;
            Text = '--';
            TextXAlignment = Enum.TextXAlignment.Left;
            TextWrapped = false;
            ZIndex = 7;
            Parent = ItemClip;
        });
        AddTextScroll(ItemList, ItemClip, DropdownOuter, true);

        Library:OnHighlight(DropdownOuter, DropdownInner,
            { BorderColor3 = 'AccentColor' },
            { BorderColor3 = 'OutlineColor' }
        );

        if Info.Tooltip or Info.ValueTooltips then
            Library:AddToolTip(function()
                local Text = Info.Tooltip or '';
                local Selected = Info.ValueTooltips and not Dropdown.Multi and Dropdown:GetValueTooltip(Dropdown.Value);
                return Selected and (Text ~= '' and Text .. '\n\n' .. Selected or Selected) or Text;
            end, DropdownOuter)
        end

        -- The open list is a VS Code style context menu: a rounded box over the blurred game (Library:AddGlass, tinted
        -- like the menu: Library.GlassTransparency), rows inset LIST_PAD px, a rounded accent highlight under the
        -- hovered row, and a check in front of the selected values.
        local MAX_DROPDOWN_ITEMS = 8;
        local ROW_HEIGHT, LIST_PAD, CHECK_WIDTH = 22, 4, 24;

        local ListOuter = Library:Create('Frame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            ZIndex = 20;
            Visible = false;
            Active = true; -- keeps taps on the list out of the game world (the rows cannot do it, see RenderRows)
            Parent = ScreenGui;
        });

        -- The opening tween (Dropdown:OpenDropdown) owns the list's size and position while it runs. Anything else
        -- that sizes or places the list ends it first, at its goal, or the tween would carry on to stale values.
        local OpenTween, OpenFull, OpenRest;
        local function EndOpenTween()
            if not OpenTween then return; end;
            OpenTween:Cancel();
            OpenTween = nil;
            ListOuter.Size, ListOuter.Position = OpenFull, OpenRest;
        end;

        local function RecalculateListPosition()
            EndOpenTween();
            -- Over the box itself, as a native select menu: the list starts where the box does (or ends where it ends,
            -- when it has to open upward near the bottom of the screen). A gap of minus the box's height does both.
            Library:PlacePopupNear(ListOuter, DropdownOuter, -DropdownOuter.AbsoluteSize.Y);
        end;

        local function RecalculateListSize(YSize)
            EndOpenTween();
            ListOuter.Size = UDim2.fromOffset(DropdownOuter.AbsoluteSize.X / (Library.UIScale or 1), YSize or (MAX_DROPDOWN_ITEMS * ROW_HEIGHT + LIST_PAD * 2))
        end;

        RecalculateListPosition();
        RecalculateListSize();

        Library:RegisterPopup(ListOuter);

        if Library.Blur or Library.GlassTransparency > 0 then -- a glass menu: the list blurs the game behind it too
            Library:AddGlass(ListOuter, function()
                return ListOuter.Visible, ListOuter.Visible;
            end);
        end;

        local ListTextScrollers = {};
        ListOuter:GetPropertyChangedSignal('Visible'):Connect(function()
            if not ListOuter.Visible then
                for _, Scroller in ipairs(ListTextScrollers) do
                    Scroller.Wanted = false;
                    Scroller:Stop();
                end;
            end;
        end);

        local ListInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 21;
            Parent = ListOuter;
        });

        Library:AddToRegistry(ListInner, {
            BackgroundColor3 = 'MainColor';
        });

        Library:Create('UICorner', { CornerRadius = UDim.new(0, 6); Parent = ListInner });

        -- the theme outline lifted toward the font color, as VS Code's menu border stands out from its fill
        local function ListBorderColor()
            return Library.OutlineColor:Lerp(Library.FontColor, 0.3);
        end;

        Library:AddToRegistry(Library:Create('UIStroke', {
            Color = ListBorderColor();
            Thickness = 1;
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border;
            Parent = ListInner;
        }), { Color = ListBorderColor });

        -- drop shadow, as under VS Code's menus: the list has the menu's own color, and without it the two blended
        local ListShadow = Library:AddGlow(ListInner, 14, 20);
        ListShadow.ImageColor3 = Color3.new(0, 0, 0);
        ListShadow.ImageTransparency = 0.3;
        ListShadow.Position = UDim2.new(0.5, 0, 0.5, 4);

        -- Solid fill under the part of the list over the menu window: the menu's text showed through the tinted list
        -- even at 2.5% (live, 2026-11-21). Only what sticks out past the window stays tinted over the blurred game.
        local ListBacking = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderSizePixel = 0;
            Visible = false;
            ZIndex = 21;
            Parent = ListInner;
        });

        Library:AddToRegistry(ListBacking, { BackgroundColor3 = 'MainColor' });
        Library:Create('UICorner', { CornerRadius = UDim.new(0, 6); Parent = ListBacking });

        local function PlaceListBacking()
            local Window = Library.MainWindow;
            local A, ASize = ListOuter.AbsolutePosition, ListOuter.AbsoluteSize;
            local B, BSize = Window and Window.AbsolutePosition, Window and Window.AbsoluteSize;
            local X0, Y0 = B and math.max(A.X, B.X), B and math.max(A.Y, B.Y);
            local X1, Y1 = B and math.min(A.X + ASize.X, B.X + BSize.X), B and math.min(A.Y + ASize.Y, B.Y + BSize.Y);

            ListBacking.Visible = Window ~= nil and Window.Visible and X1 > X0 and Y1 > Y0;

            if ListBacking.Visible then
                local Scale = math.max(Library.UIScale or 1, 0.01);
                ListBacking.Position = UDim2.fromOffset((X0 - A.X) / Scale, (Y0 - A.Y) / Scale);
                ListBacking.Size = UDim2.fromOffset((X1 - X0) / Scale, (Y1 - Y0) / Scale);
            end;
        end;

        DropdownOuter:GetPropertyChangedSignal('AbsolutePosition'):Connect(function()
            if ListOuter.Visible then -- only while open, see the color picker
                RecalculateListPosition();
                PlaceListBacking();
            end;
        end);

        -- the backing is sized in px: it follows the list while that unfolds
        for _, Property in next, { 'AbsoluteSize', 'AbsolutePosition' } do
            ListOuter:GetPropertyChangedSignal(Property):Connect(function()
                if ListOuter.Visible then PlaceListBacking(); end;
            end);
        end;

        local Scrolling = Library:Create('ScrollingFrame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            CanvasSize = UDim2.new(0, 0, 0, 0);
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 21;
            Parent = ListInner;

            TopImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png',
            BottomImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png',

            ScrollBarThickness = 3,
            ScrollBarImageColor3 = Library.FontColor,
            ScrollBarImageTransparency = 0.6,
            VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar, -- rows end where the bar starts
        });

        Library:AddToRegistry(Scrolling, {
            ScrollBarImageColor3 = 'FontColor'
        })

        -- Search box over the list: shown when the list scrolls (more than MAX_DROPDOWN_ITEMS values), or per
        -- Info.Searchable = true / false. Rows render from Shown, the values matching the typed text.
        local SEARCH_HEIGHT = 20;
        local Shown = Dropdown.Values;

        -- an accent search icon and a separator line under it, so it does not read as another option
        local SearchRow = Library:Create('Frame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Position = UDim2.fromOffset(LIST_PAD, LIST_PAD);
            Size = UDim2.new(1, -LIST_PAD * 2, 0, SEARCH_HEIGHT);
            Visible = false;
            ZIndex = 26;
            Parent = ListInner;
        });

        Library:AddToRegistry(Library:Create('Frame', {
            BackgroundColor3 = ListBorderColor();
            BorderSizePixel = 0;
            Position = UDim2.new(0, 0, 1, -1);
            Size = UDim2.new(1, 0, 0, 1);
            ZIndex = 27;
            Parent = SearchRow;
        }), { BackgroundColor3 = ListBorderColor });

        Library:CreateIcon('search', {
            AnchorPoint = Vector2.new(0, 0.5);
            Color = 'AccentColor';
            Position = UDim2.new(0, 5, 0.5, 0);
            Size = 14;
            ZIndex = 27;
            Parent = SearchRow;
        });

        local SearchBox = Library:Create('TextBox', {
            BackgroundTransparency = 1;
            ClearTextOnFocus = false;
            Font = Library.Font;
            PlaceholderColor3 = Color3.fromRGB(150, 150, 150);
            PlaceholderText = 'Search...';
            Position = UDim2.fromOffset(24, 0);
            Size = UDim2.new(1, -30, 1, -1);
            Text = '';
            TextColor3 = Library.FontColor;
            TextSize = 14;
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 27;
            Parent = SearchRow;
        });

        Library:ApplyTextStroke(SearchBox);
        Library:AddToRegistry(SearchBox, { TextColor3 = 'FontColor' });

        local function IsSearchable()
            if Info.Searchable ~= nil then
                return Info.Searchable;
            end;
            return #Dropdown.Values > MAX_DROPDOWN_ITEMS;
        end;

        local function ApplyFilter()
            local Query = SearchRow.Visible and SearchBox.Text:lower() or '';
            Shown = Dropdown.Values;

            if Query ~= '' then
                Shown = {};
                for _, Value in ipairs(Dropdown.Values) do
                    if tostring(Value):lower():find(Query, 1, true) then
                        table.insert(Shown, Value);
                    end;
                end;
            end;

            Scrolling.CanvasSize = UDim2.fromOffset(0, #Shown * ROW_HEIGHT);
        end;

        function Dropdown:Display()
            local Values = Dropdown.Values;
            local Str = '';

            if Info.Multi then
                for Idx, Value in next, Values do
                    if Dropdown.Value[Value] then
                        Str = Str .. Value .. ', ';
                    end;
                end;

                Str = Str:sub(1, #Str - 2);
            else
                Str = Dropdown.Value or '';
            end;

            ItemList.Text = (Str == '' and '--' or Str);
        end;

        function Dropdown:GetActiveValues()
            if Info.Multi then
                local T = {};

                for Value, Bool in next, Dropdown.Value do
                    table.insert(T, Value);
                end;

                return T;
            else
                return Dropdown.Value and 1 or 0;
            end;
        end;

        -- Reuse only the visible rows; opening a large list must not build thousands of instances.
        local Rows = {};
        local FirstRendered;
        function Dropdown:RenderRows(Force)
            if not ListOuter.Visible then return end;
            local Scale = math.max(Library.UIScale or 1, 0.01);
            local First = math.max(1, math.floor(Scrolling.CanvasPosition.Y / Scale / ROW_HEIGHT) + 1);
            if not Force and FirstRendered == First then return end;
            FirstRendered = First;
            local Count = math.min(#Shown, MAX_DROPDOWN_ITEMS + 2);
            for Index = #Rows + 1, Count do
                local Row = {};
                -- the row's fill is its hover highlight: clear until the pointer is over it
                local Button = Library:Create('Frame', {
                    BackgroundColor3 = Library.AccentColor;
                    BackgroundTransparency = 1;
                    BorderSizePixel = 0;
                    Size = UDim2.new(1, 0, 0, ROW_HEIGHT);
                    ZIndex = 23;
                    -- not Active: an Active row captures the finger, so a swipe on the list never scrolled it
                    -- (live: 90 px swipe, canvas stayed at 0; with inactive rows it moved 90)
                    Parent = Scrolling;
                });
                Row.Button = Button;

                Library:AddToRegistry(Button, {
                    BackgroundColor3 = 'AccentColor';
                });

                Library:Create('UICorner', { CornerRadius = UDim.new(0, 4); Parent = Button });

                -- at rest a selected row keeps a faint accent fill (Row.Rest, set by UpdateButton); hover fills it fully
                Row.Rest = 1;

                Button.MouseEnter:Connect(function()
                    Row.Hovered = true;
                    Library:Animate(Button, 0.06, { BackgroundTransparency = 0 });
                end);

                Button.MouseLeave:Connect(function()
                    Row.Hovered = false;
                    Library:Animate(Button, 0.1, { BackgroundTransparency = Row.Rest });
                end);

                -- selected values get a check in the column left of the names
                Row.Check = Library:CreateIcon('check', {
                    AnchorPoint = Vector2.new(0.5, 0.5);
                    Position = UDim2.new(0, CHECK_WIDTH / 2, 0.5, 0);
                    Size = 12;
                    Thickness = 2;
                    ZIndex = 25;
                    Parent = Button;
                });

                -- ValueIcons: a 16px icon in front of the name, which moves right to make room
                Row.Icon = Info.ValueIcons and Library:Create('ImageLabel', {
                    AnchorPoint = Vector2.new(0, 0.5);
                    BackgroundTransparency = 1;
                    Position = UDim2.new(0, CHECK_WIDTH, 0.5, 0);
                    Size = UDim2.fromOffset(16, 16);
                    ScaleType = Enum.ScaleType.Fit;
                    ZIndex = 25;
                    Parent = Button;
                });

                local TextX = CHECK_WIDTH + (Row.Icon and 20 or 0);
                local ButtonClip = Library:Create('Frame', {
                    BackgroundTransparency = 1;
                    BorderSizePixel = 0;
                    ClipsDescendants = true;
                    Position = UDim2.new(0, TextX, 0, 0);
                    Size = UDim2.new(1, -(TextX + 8), 1, 0);
                    ZIndex = 25;
                    Parent = Button;
                });

                local ButtonLabel = Library:CreateLabel({
                    Active = false;
                    Size = UDim2.new(1, 0, 1, 0);
                    Position = UDim2.fromOffset(0, 0);
                    TextSize = 14;
                    Text = '';
                    TextXAlignment = Enum.TextXAlignment.Left;
                    TextWrapped = false;
                    ZIndex = 25;
                    Parent = ButtonClip;
                });
                Row.Label = ButtonLabel;
                Row.Scroller = AddTextScroll(ButtonLabel, ButtonClip, Button, false);
                table.insert(ListTextScrollers, Row.Scroller);
                Library:AddToolTip(function()
                    return ListOuter.Visible and Row.Value ~= nil and Dropdown:GetValueTooltip(Row.Value) or nil;
                end, Button, true);

                function Row:UpdateButton()
                    local Selected = Info.Multi and Dropdown.Value[self.Value] or Dropdown.Value == self.Value;
                    Row.Check.Visible = Selected and true or false;
                    Row.Rest = Selected and 0.65 or 1;
                    if not Row.Hovered then
                        Button.BackgroundTransparency = Row.Rest;
                    end;
                end;

                ButtonLabel.InputBegan:Connect(function(Input)
                    if IsTap(Input) then
                        local Value = Row.Value;
                        if Value == nil then return end;
                        local Selected = Info.Multi and Dropdown.Value[Value] or Dropdown.Value == Value;
                        local Try = not Selected;

                        if Dropdown:GetActiveValues() == 1 and (not Try) and (not Info.AllowNull) then
                        else
                            if Info.Multi then
                                Selected = Try;

                                if Selected then
                                    Dropdown.Value[Value] = true;
                                else
                                    Dropdown.Value[Value] = nil;
                                end;
                            else
                                Selected = Try;

                                if Selected then
                                    Dropdown.Value = Value;
                                else
                                    Dropdown.Value = nil;
                                end;

                                for _, OtherButton in ipairs(Rows) do
                                    OtherButton:UpdateButton();
                                end;
                            end;

                            Row:UpdateButton();
                            Dropdown:Display();

                            Library:SafeCallback(Dropdown.Callback, Dropdown.Value);
                            Library:SafeCallback(Dropdown.Changed, Dropdown.Value);

                            Library:AttemptSave();
                        end;
                    end;
                end);

                Rows[Index] = Row;
            end;
            for Index, Row in ipairs(Rows) do
                local ValueIndex = First + Index - 1;
                local Value = Shown[ValueIndex];
                Row.Button.Visible = Value ~= nil;
                if Row.Value ~= Value then
                    Row.Scroller:Stop();
                    Row.Value = Value;
                    Row.Label.Text = Value or '';
                    if Row.Icon then
                        Row.Icon.Image = Dropdown:GetValueIcon(Value);
                    end;
                end;
                Row.Button.Position = UDim2.fromOffset(0, (ValueIndex - 1) * ROW_HEIGHT);
                if Value == nil then
                    Row.Scroller.Wanted = false;
                    Row.Scroller:Stop();
                end;
                Row:UpdateButton();
            end;
        end;

        function Dropdown:BuildDropdownList()
            local Top = IsSearchable() and SEARCH_HEIGHT + LIST_PAD or 0;
            SearchRow.Visible = Top > 0;
            Scrolling.Position = UDim2.fromOffset(LIST_PAD, LIST_PAD + Top);
            Scrolling.Size = UDim2.new(1, -LIST_PAD * 2, 1, -(LIST_PAD * 2 + Top));
            ApplyFilter();
            -- height from all values, not the matches, so the list does not jump around while typing
            local Y = math.clamp(#Dropdown.Values * ROW_HEIGHT, 0, MAX_DROPDOWN_ITEMS * ROW_HEIGHT) + LIST_PAD * 2 + Top;
            RecalculateListSize(Y);
            Dropdown:Display();
            Dropdown:RenderRows(true);
        end;

        SearchBox:GetPropertyChangedSignal('Text'):Connect(function()
            ApplyFilter();
            Scrolling.CanvasPosition = Vector2.zero;
            Dropdown:RenderRows(true);
        end);

        Scrolling:GetPropertyChangedSignal('CanvasPosition'):Connect(function()
            Dropdown:RenderRows();
        end);
        Scrolling:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()
            Dropdown:RenderRows(true);
        end);

        function Dropdown:SetValues(NewValues)
            if Library:NeedsUIThread() then
                return Library:RunOnUIThread(Dropdown.SetValues, Dropdown, NewValues);
            end;

            if NewValues then
                Dropdown.Values = NewValues;
            end;

            Dropdown:BuildDropdownList();
        end;

        function Dropdown:OpenDropdown()
            -- width from the header as it is now: built once, the list stayed narrow after the window was resized
            RecalculateListSize(ListOuter.Size.Y.Offset);
            RecalculateListPosition();
            ListInner.BackgroundTransparency = Library.GlassTransparency; -- the menu's tint (Menu opacity slider)
            ListOuter.Visible = true;
            PlaceListBacking();
            SearchBox.Text = ''; -- each open starts unfiltered (also re-renders the rows)
            Dropdown:RenderRows(true);
            Library.OpenedFrames[ListOuter] = true;
            if SearchRow.Visible and not IsMobile then
                SearchBox:CaptureFocus(); -- type straight away; phones only get the keyboard when they tap the box
            end;
            -- The list unfolds out of the box it covers: from the box's height to its own, easing out, the rows
            -- showing as it grows. Opened upward (near the bottom of the screen) it grows up from the box's lower edge.
            -- No fade: one property eased on one frame, which is what keeps it calm. (Library.Animations)
            local Scale = math.max(Library.UIScale or 1, 0.01);
            OpenFull, OpenRest = ListOuter.Size, ListOuter.Position;
            local Start = math.min(DropdownOuter.AbsoluteSize.Y / Scale, OpenFull.Y.Offset);
            local Upward = OpenRest.Y.Offset < DropdownOuter.AbsolutePosition.Y - 1;

            ListOuter.Size = UDim2.fromOffset(OpenFull.X.Offset, Start);
            if Upward then
                ListOuter.Position = OpenRest + UDim2.fromOffset(0, (OpenFull.Y.Offset - Start) * Scale);
            end;

            local Tween = Library:CreateTween(ListOuter, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
                Size = OpenFull;
                Position = OpenRest;
            });

            OpenTween = Tween;
            Tween:Play();

            if Tween.Completed then
                Tween.Completed:Once(function()
                    if OpenTween == Tween then OpenTween = nil; end;
                end);
            else -- animations off: already at its goal
                OpenTween = nil;
            end;

            Library:Animate(DropdownArrow, 0.15, { Rotation = 180 });
        end;

        function Dropdown:CloseDropdown()
            EndOpenTween();
            ListOuter.Visible = false;
            Library.OpenedFrames[ListOuter] = nil;
            for _, Row in ipairs(Rows) do
                Row.Hovered = false; -- a hidden row gets no MouseLeave
                Row.Button.BackgroundTransparency = Row.Rest;
            end;
            if SearchBox:IsFocused() then
                SearchBox:ReleaseFocus();
            end;
            Library:Animate(DropdownArrow, 0.15, { Rotation = 0 });
        end;

        function Dropdown:OnChanged(Func)
            Dropdown.Changed = Func;
            Func(Dropdown.Value);
        end;

        function Dropdown:SetValue(Val)
            if Library:NeedsUIThread() then
                return Library:RunOnUIThread(Dropdown.SetValue, Dropdown, Val);
            end;

            if Dropdown.Multi then
                local nTable = {};

                for Value, Bool in next, Val do
                    if table.find(Dropdown.Values, Value) then
                        nTable[Value] = true
                    end;
                end;

                Dropdown.Value = nTable;
            else
                if (not Val) then
                    Dropdown.Value = nil;
                elseif table.find(Dropdown.Values, Val) then
                    Dropdown.Value = Val;
                end;
            end;

            Dropdown:Display();
            Dropdown:RenderRows(true);

            Library:SafeCallback(Dropdown.Callback, Dropdown.Value);
            Library:SafeCallback(Dropdown.Changed, Dropdown.Value);
            Library:AttemptSave();
        end;

        DropdownOuter.InputBegan:Connect(function(Input)
            if IsTap(Input) and not Library:MouseIsOverOpenedFrame() then
                if ListOuter.Visible then
                    Dropdown:CloseDropdown();
                else
                    Dropdown:OpenDropdown();
                end;
            end;
        end);

        Library:GiveSignal(InputService.InputBegan:Connect(function(Input)
            if IsClick(Input) then
                -- the header toggles the list itself; the list can sit above it when flipped near the screen bottom
                if not Library:IsMouseOverFrame(ListOuter) and not Library:IsMouseOverFrame(DropdownOuter) then
                    Dropdown:CloseDropdown();
                end;
            end;
        end));

        Dropdown:BuildDropdownList();
        Dropdown:Display();

        local Defaults = {}

        if type(Info.Default) == 'string' then
            local Idx = table.find(Dropdown.Values, Info.Default)
            if Idx then
                table.insert(Defaults, Idx)
            end
        elseif type(Info.Default) == 'table' then
            for _, Value in next, Info.Default do
                local Idx = table.find(Dropdown.Values, Value)
                if Idx then
                    table.insert(Defaults, Idx)
                end
            end
        elseif type(Info.Default) == 'number' and Dropdown.Values[Info.Default] ~= nil then
            table.insert(Defaults, Info.Default)
        end

        if next(Defaults) then
            for i = 1, #Defaults do
                local Index = Defaults[i]
                if Info.Multi then
                    Dropdown.Value[Dropdown.Values[Index]] = true
                else
                    Dropdown.Value = Dropdown.Values[Index];
                end

                if (not Info.Multi) then break end
            end

            Dropdown:BuildDropdownList();
            Dropdown:Display();
        end

        Groupbox:AddBlank(Info.BlankSize or 5);
        Groupbox:Resize();

        Options[Idx] = Dropdown;

        return Dropdown;
    end;

    function Funcs:AddDependencyBox()
        local Depbox = {
            Dependencies = {};
        };
        
        local Groupbox = self;
        local Container = Groupbox.Container;

        local Holder = Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(1, 0, 0, 0);
            Visible = false;
            Parent = Container;
        });

        local Frame = Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(1, 0, 1, 0);
            Visible = true;
            Parent = Holder;
        });

        local Layout = Library:Create('UIListLayout', {
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            Parent = Frame;
        });

        function Depbox:Resize()
            Holder.Size = UDim2.new(1, 0, 0, Layout.AbsoluteContentSize.Y);
            Groupbox:Resize();
        end;

        Layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
            Depbox:Resize();
        end);

        Holder:GetPropertyChangedSignal('Visible'):Connect(function()
            Depbox:Resize();
        end);

        function Depbox:Update()
            for _, Dependency in next, Depbox.Dependencies do
                local Elem = Dependency[1];
                local Value = Dependency[2];

                -- a function element is a computed condition (e.g. "toggle A or toggle B"); re-read on every update
                local Current = type(Elem) == 'function' and Elem() or (type(Elem) == 'table' and Elem.Type == 'Toggle' and Elem.Value);

                if (type(Elem) == 'function' or Elem.Type == 'Toggle') and Current ~= Value then
                    Holder.Visible = false;
                    Depbox:Resize();
                    return;
                end;
            end;

            Holder.Visible = true;
            Depbox:Resize();
        end;

        function Depbox:SetupDependencies(Dependencies)
            for _, Dependency in next, Dependencies do
                assert(type(Dependency) == 'table', 'SetupDependencies: Dependency is not of type `table`.');
                assert(Dependency[1], 'SetupDependencies: Dependency is missing element argument.');
                assert(Dependency[2] ~= nil, 'SetupDependencies: Dependency is missing value argument.');
            end;

            Depbox.Dependencies = Dependencies;
            Depbox:Update();
        end;

        Depbox.Container = Frame;

        setmetatable(Depbox, BaseGroupbox);

        table.insert(Library.DependencyBoxes, Depbox);

        return Depbox;
    end;

    BaseGroupbox.__index = Funcs;
    BaseGroupbox.__namecall = function(Table, Key, ...)
        return Funcs[Key](...);
    end;
end;

-- < Create other UI elements >
do
    Library.NotificationArea = Library:Create('Frame', {
        BackgroundTransparency = 1;
        Position = UDim2.new(0, 0, 0, 40);
        Size = UDim2.new(0, 300, 0, 200);
        ZIndex = 100;
        Parent = ScreenGui;
    });

    Library:Create('UIListLayout', {
        Padding = UDim.new(0, 4);
        FillDirection = Enum.FillDirection.Vertical;
        SortOrder = Enum.SortOrder.LayoutOrder;
        Parent = Library.NotificationArea;
    });

    local WatermarkOuter = Library:Create('Frame', {
        AnchorPoint = Vector2.new(0.5, 0);
        BorderColor3 = Color3.new(0, 0, 0);
        Position = UDim2.new(0.5, 0, 0, -25);
        Size = UDim2.new(0, 213, 0, 20);
        ZIndex = 200;
        Visible = false;
        Parent = ScreenGui;
    });

    local WatermarkInner = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderColor3 = Library.AccentColor;
        BorderMode = Enum.BorderMode.Inset;
        Size = UDim2.new(1, 0, 1, 0);
        ZIndex = 201;
        Parent = WatermarkOuter;
    });

    Library:AddToRegistry(WatermarkInner, {
        BorderColor3 = 'AccentColor';
    }, true);

    local InnerFrame = Library:Create('Frame', {
        BackgroundColor3 = Color3.new(1, 1, 1);
        BorderSizePixel = 0;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 202;
        Parent = WatermarkInner;
    });

    local Gradient = Library:Create('UIGradient', {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
            ColorSequenceKeypoint.new(1, Library.MainColor),
        });
        Rotation = -90;
        Parent = InnerFrame;
    });

    Library:AddToRegistry(Gradient, {
        Color = function()
            return ColorSequence.new({
                ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
                ColorSequenceKeypoint.new(1, Library.MainColor),
            });
        end
    });

    local WatermarkLabel = Library:CreateLabel({
        Position = UDim2.new(0, 5, 0, 0);
        Size = UDim2.new(1, -4, 1, 0);
        Text = '';
        TextSize = 14;
        TextXAlignment = Enum.TextXAlignment.Left;
        ZIndex = 203;
        Parent = InnerFrame;
    });

    Library.Watermark = WatermarkOuter;
    Library.WatermarkText = WatermarkLabel;
    Library:MakeDraggable(Library.Watermark);



    local KeybindOuter = Library:Create('Frame', {
        AnchorPoint = Vector2.new(0, 0.5);
        BorderColor3 = Color3.new(0, 0, 0);
        Position = UDim2.new(0, 10, 0.5, 0);
        Size = UDim2.new(0, 210, 0, 20);
        Visible = false;
        ZIndex = 100;
        Parent = ScreenGui;
    });

    local KeybindInner = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderColor3 = Library.OutlineColor;
        BorderMode = Enum.BorderMode.Inset;
        Size = UDim2.new(1, 0, 1, 0);
        ZIndex = 101;
        Parent = KeybindOuter;
    });

    Library:AddToRegistry(KeybindInner, {
        BackgroundColor3 = 'MainColor';
        BorderColor3 = 'OutlineColor';
    }, true);

    local ColorFrame = Library:Create('Frame', {
        BackgroundColor3 = Library.AccentColor;
        BorderSizePixel = 0;
        Size = UDim2.new(1, 0, 0, 2);
        ZIndex = 102;
        Parent = KeybindInner;
    });

    Library:AddToRegistry(ColorFrame, {
        BackgroundColor3 = 'AccentColor';
    }, true);

    local KeybindLabel = Library:CreateLabel({
        Size = UDim2.new(1, 0, 0, 20);
        Position = UDim2.fromOffset(5, 2),
        TextXAlignment = Enum.TextXAlignment.Left,

        Text = 'Keybinds';
        ZIndex = 104;
        Parent = KeybindInner;
    });

    local KeybindContainer = Library:Create('Frame', {
        BackgroundTransparency = 1;
        Size = UDim2.new(1, 0, 1, -20);
        Position = UDim2.new(0, 0, 0, 20);
        ZIndex = 1;
        Parent = KeybindInner;
    });

    Library:Create('UIListLayout', {
        FillDirection = Enum.FillDirection.Vertical;
        SortOrder = Enum.SortOrder.LayoutOrder;
        Parent = KeybindContainer;
    });

    Library:Create('UIPadding', {
        PaddingLeft = UDim.new(0, 5),
        Parent = KeybindContainer,
    })

    Library.KeybindFrame = KeybindOuter;
    Library.KeybindContainer = KeybindContainer;
    Library:MakeDraggable(KeybindOuter);
end;

-- The bar only shows once SetWatermark has given it text, so a script that never sets one gets no empty box.
function Library:SetWatermarkVisibility(Bool)
    Library.WatermarkEnabled = (not not Bool);
    Library.Watermark.Visible = Library.WatermarkEnabled and Library.WatermarkText.Text ~= '';
end;

-- Resizes the keybind list HUD to fit its entries. The frame only shows while it is enabled AND at
-- least one KeyPicker (without NoUI) is listed, so there is never an empty "Keybinds" box on screen.
function Library:UpdateKeybindFrame()
    local YSize, XSize, Count = 0, 0, 0;

    for _, Label in next, Library.KeybindContainer:GetChildren() do
        if Label:IsA('TextLabel') and Label.Visible then
            Count = Count + 1;
            YSize = YSize + 18;
            XSize = math.max(XSize, Label.TextBounds.X);
        end;
    end;

    Library.KeybindFrame.Size = UDim2.new(0, math.max(XSize + 10, 210), 0, YSize + 23);
    Library.KeybindFrame.Visible = (Library.KeybindFrameEnabled == true) and Count > 0;
end;

function Library:SetKeybindFrameVisibility(Bool)
    Library.KeybindFrameEnabled = (not not Bool);
    Library:UpdateKeybindFrame();
end;

function Library:SetWatermark(Text)
    if Library:NeedsUIThread() then
        return Library:RunOnUIThread(Library.SetWatermark, Library, Text);
    end;

    local X, Y = Library:GetTextBounds(Text, Library.Font, 14);
    Library.Watermark.Size = UDim2.new(0, X + 15, 0, (Y * 1.5) + 3);
    Library.WatermarkText.Text = Text;

    if Library.WatermarkEnabled == nil then
        Library:SetWatermarkVisibility(true);
    else
        Library.Watermark.Visible = Library.WatermarkEnabled and Text ~= '';
    end;
end;

-- Shared by Library:Modal and Library:ChangeLog: a dialog of Width x Height over the dimmed menu window, which takes
-- no input meanwhile. It hides and comes back with the menu.
-- shortcut: covers the main window only, floating panels stay usable; a ScreenGui of its own when that matters.
local DIALOG_FOOTER = IsMobile and 40 or 32;

local function DialogBorderColor()
    return Library.OutlineColor:Lerp(Library.FontColor, 0.3);
end;

local function OpenDialog(Width, Height)
    local Window = assert(Library.MainWindow, 'Library dialog: no window yet');

    -- an open dropdown list or color picker would stay over the dimmed window
    for Frame in next, Library.OpenedFrames do
        Frame.Visible = false;
        Library.OpenedFrames[Frame] = nil;
    end;

    -- Only a button keeps a click from the controls under it (live test: an Active frame over a toggle did not), and
    -- the menu's fade leaves buttons alone. So a clear button takes the input and a frame in it does the dimming.
    -- The button starts under the title bar, so the window can still be dragged by it; the dim covers that too.
    local Title = Library.WindowTitleHeight or 0;
    local Blocker = Library:Create('TextButton', {
        AutoButtonColor = false;
        BackgroundTransparency = 1;
        Position = UDim2.fromOffset(0, Title);
        Size = UDim2.new(1, 0, 1, -Title);
        Text = '';
        ZIndex = 300;
        Parent = Window;
    });

    local Dim = Library:Create('Frame', {
        BackgroundColor3 = Color3.new(0, 0, 0);
        BackgroundTransparency = 0.5;
        BorderSizePixel = 0;
        Position = UDim2.fromOffset(0, -Title);
        Size = UDim2.new(1, 0, 1, Title);
        ZIndex = 300;
        Parent = Blocker;
    });

    -- The dim fades in and out: the whole menu going dark, or bright again, in one frame was a flash.
    -- shortcut: a menu closed within these 0.18 s caches the half-faded dim as its real value (that dialog then
    -- stays lighter); tell the menu's fade about the goal first if that ever shows.
    local Animated = Library.Animations and Window.Visible;
    if Animated then
        Dim.BackgroundTransparency = 1;
        Library:Animate(Dim, 0.18, { BackgroundTransparency = 0.5 });
    end;

    local Frame = Library:Create('Frame', {
        AnchorPoint = Vector2.new(0.5, 0.5);
        BackgroundColor3 = Library.MainColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0.5, 0, 0.5, -Title / 2); -- centred on the whole window
        Size = UDim2.fromOffset(Width, Height);
        ZIndex = 302;
        Parent = Blocker;
    });

    Library:AddToRegistry(Frame, { BackgroundColor3 = 'MainColor' });
    Library:Create('UICorner', { CornerRadius = UDim.new(0, 6); Parent = Frame });

    -- border and shadow as on the dropdown list
    Library:AddToRegistry(Library:Create('UIStroke', {
        Color = DialogBorderColor();
        Thickness = 1;
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border;
        Parent = Frame;
    }), { Color = DialogBorderColor });

    local Shadow = Library:AddGlow(Frame, 14, 301);
    Shadow.ImageColor3 = Color3.new(0, 0, 0);
    Shadow.ImageTransparency = 0.3;
    Shadow.Position = UDim2.new(0.5, 0, 0.5, 4);

    -- pop in by scale: the transparencies belong to the menu's fade
    local Pop = Library:Create('UIScale', { Scale = Animated and 0.97 or 1; Parent = Frame });
    Library:Animate(Pop, 0.18, { Scale = 1 });

    local Dialog = { Frame = Frame };
    local Closed = false;
    local Done = Instance.new('BindableEvent'); -- Close, or the window itself going away
    Blocker.Destroying:Connect(function() Done:Fire(); end);

    function Dialog.Rule(Position, Size)
        Library:AddToRegistry(Library:Create('Frame', {
            BackgroundColor3 = DialogBorderColor();
            BorderSizePixel = 0;
            Position = Position;
            Size = Size;
            ZIndex = 304;
            Parent = Frame;
        }), { BackgroundColor3 = DialogBorderColor });
    end;

    -- The buttons split the foot of the dialog evenly; the first is the primary one: accent text, on the right.
    -- OnPick(Index) runs on a tap. Returns the buttons' labels, for dialogs that rename them.
    function Dialog.Footer(Names, OnPick)
        local Labels = {};
        Dialog.Rule(UDim2.new(0, 0, 1, -DIALOG_FOOTER - 1), UDim2.new(1, 0, 0, 1));

        for Index, Name in next, Names do
            local Slot = #Names - Index; -- from the right: the primary one ends up there

            local Part = Library:Create('Frame', {
                BackgroundTransparency = 1;
                Position = UDim2.new(Slot / #Names, 0, 1, -DIALOG_FOOTER);
                Size = UDim2.new(1 / #Names, 0, 0, DIALOG_FOOTER);
                ZIndex = 303;
                Parent = Frame;
            });

            if Slot > 0 then
                Dialog.Rule(UDim2.new(Slot / #Names, 0, 1, -DIALOG_FOOTER), UDim2.new(0, 1, 0, DIALOG_FOOTER));
            end;

            -- Hover fill, inset so it stays clear of the dialog's round corners. By color and never by transparency:
            -- the transparencies belong to the menu's fade.
            local Pill = Library:Create('Frame', {
                BackgroundColor3 = Library.MainColor;
                BorderSizePixel = 0;
                Position = UDim2.fromOffset(4, 4);
                Size = UDim2.new(1, -8, 1, -8);
                ZIndex = 303;
                Parent = Part;
            });

            Library:AddToRegistry(Pill, { BackgroundColor3 = 'MainColor' });
            Library:Create('UICorner', { CornerRadius = UDim.new(0, 4); Parent = Pill });

            local Label = Library:CreateLabel({
                Size = UDim2.fromScale(1, 1);
                Text = Name;
                TextSize = 14;
                ZIndex = 305;
                Parent = Part;
            });

            if Index == 1 then
                Library:RemoveFromRegistry(Label);
                Label.TextColor3 = Library.AccentColor;
                Library:AddToRegistry(Label, { TextColor3 = 'AccentColor' });
            end;

            Labels[Index] = Label;

            Part.MouseEnter:Connect(function()
                Library:Animate(Pill, 0.1, { BackgroundColor3 = Library.MainColor:Lerp(Library.AccentColor, 0.3) });
            end);

            Part.MouseLeave:Connect(function()
                Library:Animate(Pill, 0.15, { BackgroundColor3 = Library.MainColor });
            end);

            Part.InputBegan:Connect(function(Input)
                if IsTap(Input) and not Closed then
                    OnPick(Index);
                end;
            end);
        end;

        return Labels;
    end;

    function Dialog.Close()
        if Closed then return; end;
        Closed = true;

        -- the theme registry would keep the destroyed pieces otherwise
        for _, Desc in next, Blocker:GetDescendants() do
            Library:RemoveFromRegistry(Desc);
        end;

        Done:Fire(); -- the caller goes on now; the dim only fades behind it

        if Library.Animations and Window.Visible then
            Frame.Visible = false;
            Library:Animate(Dim, 0.12, { BackgroundTransparency = 1 });
            task.delay(0.12, function() Blocker:Destroy(); end);
        else
            Blocker:Destroy();
        end;
    end;

    -- yields until Close, or until the window itself goes away
    function Dialog.Wait()
        if Closed or not Blocker.Parent then return; end;
        Done.Event:Wait();
    end;

    return Dialog;
end;

-- Modal dialog over the menu window, as VS Code's: the window dims and takes no input until a button is picked.
-- Yields and returns the picked button's text (nil if the window is destroyed first). The first button is the
-- primary one, on the right.
--   if Library:Modal({ Title = 'Delete preset?', Text = 'This cannot be undone.', Buttons = { 'Delete', 'Cancel' } }) == 'Delete' then
function Library:Modal(Info)
    if Library:NeedsUIThread() then
        return Library:RunOnUIThread(Library.Modal, Library, Info);
    end;

    local Names = Info.Buttons or { 'OK' };
    local Text = Info.Text or '';
    local WIDTH, PAD, TITLE_HEIGHT = 280, 14, 18;

    local _, TextHeight = Library:GetTextBounds(Text, Library.Font, 14, Vector2.new(WIDTH - PAD * 2, 1920));
    local TextBlock = Text ~= '' and TextHeight + 8 or 0;
    local Dialog = OpenDialog(WIDTH, PAD + TITLE_HEIGHT + TextBlock + PAD + 1 + DIALOG_FOOTER);

    Library:CreateLabel({
        Position = UDim2.fromOffset(PAD, PAD);
        Size = UDim2.new(1, -PAD * 2, 0, TITLE_HEIGHT);
        Text = Info.Title or '';
        TextSize = 15;
        TextTruncate = Enum.TextTruncate.AtEnd;
        ZIndex = 303;
        Parent = Dialog.Frame;
    });

    Library:CreateLabel({
        Position = UDim2.fromOffset(PAD, PAD + TITLE_HEIGHT + 8);
        Size = UDim2.new(1, -PAD * 2, 0, TextHeight + WRAP_SLACK);
        Text = Text;
        TextSize = 14;
        TextTransparency = 0.25; -- under the title in weight
        TextWrapped = true;
        TextYAlignment = Enum.TextYAlignment.Top;
        Visible = Text ~= '';
        ZIndex = 303;
        Parent = Dialog.Frame;
    });

    local Choice;
    Dialog.Footer(Names, function(Index)
        Choice = Names[Index];
        Dialog.Close();
    end);

    Dialog.Wait();
    return Choice;
end;

-- What's new, one change per page: a preview strip (kind tag, mark, menu path), the change's name and text, page
-- dots, and Skip / Back | Next / Done. Yields; returns true once read through or skipped, nil if the window went
-- away first. Showing it only once per version is the caller's: save the version when this returns true.
--   Library:ChangeLog({ Title = "What's new", Pages = {
--       { Title = 'Auto Position', Text = 'Picks the spot ...', Kind = 'changed', Path = 'Gameplay > Auto Play > Position' },
--   } })
local CHANGE_KINDS = { -- the colors of the Discord change log; Lucide icons, as the font's + ~ - came out tiny
    new = { Tag = 'NEW', Icon = 'plus', Color = Color3.fromRGB(115, 201, 145) };
    changed = { Tag = 'CHANGED', Icon = 'arrow-right-left', Color = Color3.fromRGB(226, 192, 141) };
    fixed = { Tag = 'FIXED', Icon = 'check', Color = Color3.fromRGB(241, 76, 76) };
};

function Library:ChangeLog(Info)
    if Library:NeedsUIThread() then
        return Library:RunOnUIThread(Library.ChangeLog, Library, Info);
    end;

    local Pages = Info.Pages;
    assert(type(Pages) == 'table' and #Pages > 0, 'Library:ChangeLog: no Pages');

    local WIDTH, PAD, TITLE_HEIGHT, PREVIEW = 320, 14, 18, 70;
    local TOP = PAD + TITLE_HEIGHT + 8;
    local TEXT_TOP = PREVIEW + 10 + 18 + 6; -- under the preview and the page's name

    -- one size for every page, the tallest text's, so the buttons stay put while paging
    local TextHeight = 0;
    for _, Page in next, Pages do
        local _, Height = Library:GetTextBounds(Page.Text or '', Library.Font, 14, Vector2.new(WIDTH - PAD * 2, 1920));
        TextHeight = math.max(TextHeight, Height);
    end;

    local DotsTop = TOP + TEXT_TOP + TextHeight + 16;
    local Dialog = OpenDialog(WIDTH, DotsTop + 6 + 12 + 1 + DIALOG_FOOTER);
    local Frame = Dialog.Frame;

    Library:CreateLabel({
        Position = UDim2.fromOffset(PAD, PAD);
        Size = UDim2.new(1, -PAD * 2 - 50, 0, TITLE_HEIGHT);
        Text = Info.Title or "What's new";
        TextSize = 15;
        TextTruncate = Enum.TextTruncate.AtEnd;
        TextXAlignment = Enum.TextXAlignment.Left;
        ZIndex = 303;
        Parent = Frame;
    });

    local Counter = Library:CreateLabel({
        AnchorPoint = Vector2.new(1, 0);
        Position = UDim2.new(1, -PAD, 0, PAD);
        Size = UDim2.fromOffset(50, TITLE_HEIGHT);
        TextSize = 13;
        TextTransparency = 0.5;
        TextXAlignment = Enum.TextXAlignment.Right;
        ZIndex = 303;
        Parent = Frame;
    });

    -- the page's own content, slid in on a page change
    local Content = Library:Create('Frame', {
        BackgroundTransparency = 1;
        Position = UDim2.fromOffset(0, TOP);
        Size = UDim2.new(1, 0, 0, TEXT_TOP + TextHeight + WRAP_SLACK);
        ZIndex = 303;
        Parent = Frame;
    });

    local Preview = Library:Create('Frame', {
        BackgroundColor3 = Library.BackgroundColor;
        BorderSizePixel = 0;
        Position = UDim2.fromOffset(12, 0);
        Size = UDim2.new(1, -24, 0, PREVIEW);
        ZIndex = 303;
        Parent = Content;
    });

    Library:AddToRegistry(Preview, { BackgroundColor3 = 'BackgroundColor' });
    Library:Create('UICorner', { CornerRadius = UDim.new(0, 4); Parent = Preview });
    Library:AddToRegistry(Library:Create('UIStroke', {
        Color = DialogBorderColor();
        Thickness = 1;
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border;
        Parent = Preview;
    }), { Color = DialogBorderColor });

    local Tag = Library:Create('Frame', {
        BackgroundTransparency = 0.8;
        BorderSizePixel = 0;
        Position = UDim2.fromOffset(8, 8);
        ZIndex = 304;
        Parent = Preview;
    });

    Library:Create('UICorner', { CornerRadius = UDim.new(0, 3); Parent = Tag });
    local TagStroke = Library:Create('UIStroke', { Thickness = 1; ApplyStrokeMode = Enum.ApplyStrokeMode.Border; Parent = Tag });
    local TagLabel = Library:CreateLabel({ Size = UDim2.fromScale(1, 1); TextSize = 11; ZIndex = 305; Parent = Tag });

    local Icons = {};
    for Key, Kind in next, CHANGE_KINDS do
        Icons[Key] = Library:CreateIcon(Kind.Icon, {
            AnchorPoint = Vector2.new(0.5, 0.5);
            Color = function() return Kind.Color; end;
            Size = 24;
            Thickness = 2;
            ZIndex = 304;
            Parent = Preview;
        });
    end;

    local Path = Library:CreateLabel({
        Position = UDim2.fromOffset(8, 46);
        Size = UDim2.new(1, -16, 0, 16);
        TextSize = 13;
        TextTransparency = 0.35;
        TextTruncate = Enum.TextTruncate.AtEnd;
        ZIndex = 304;
        Parent = Preview;
    });

    local Name = Library:CreateLabel({
        Position = UDim2.fromOffset(PAD, PREVIEW + 10);
        Size = UDim2.new(1, -PAD * 2, 0, 18);
        TextSize = 15;
        TextTruncate = Enum.TextTruncate.AtEnd;
        ZIndex = 303;
        Parent = Content;
    });

    local Body = Library:CreateLabel({
        Position = UDim2.fromOffset(PAD, TEXT_TOP);
        Size = UDim2.new(1, -PAD * 2, 0, TextHeight + WRAP_SLACK);
        TextSize = 14;
        TextTransparency = 0.25;
        TextWrapped = true;
        TextYAlignment = Enum.TextYAlignment.Top;
        ZIndex = 303;
        Parent = Content;
    });

    local Dots = {};
    local DotsLeft = (WIDTH - (#Pages * 12 - 6)) / 2;
    for Index = 1, #Pages do
        Dots[Index] = Library:Create('Frame', {
            BorderSizePixel = 0;
            Position = UDim2.fromOffset(DotsLeft + (Index - 1) * 12, DotsTop);
            Size = UDim2.fromOffset(6, 6);
            ZIndex = 303;
            Parent = Frame;
        });
        Library:Create('UICorner', { CornerRadius = UDim.new(1, 0); Parent = Dots[Index] });
    end;

    local Current, Finished = 1, false;
    local Labels;

    -- Colors and texts only: the transparencies belong to the menu's fade, which caches them while it is hidden.
    local function Show(Index, Direction)
        Current = Index;
        local Page = Pages[Index];
        local KindKey = CHANGE_KINDS[Page.Kind] and Page.Kind or 'new';
        local Kind = CHANGE_KINDS[KindKey];

        Counter.Text = Index .. ' / ' .. #Pages;
        TagLabel.Text = Kind.Tag;
        TagLabel.TextColor3 = Kind.Color;
        Tag.BackgroundColor3 = Kind.Color;
        TagStroke.Color = Kind.Color;
        Tag.Size = UDim2.fromOffset(Library:GetTextBounds(Kind.Tag, Library.Font, 11) + 12, 16);
        for Key, Icon in next, Icons do
            Icon.Visible = Key == KindKey;
            Icon.Position = UDim2.new(0.5, 0, 0, Page.Path and 28 or PREVIEW / 2); -- centred when there is no path
        end;
        Path.Text = Page.Path or '';
        Name.Text = Page.Title or '';
        Body.Text = Page.Text or '';
        -- a list (one item a line) reads down the left; a sentence stays centred
        Body.TextXAlignment = Body.Text:find('\n') and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center;

        for Dot, Frame in next, Dots do
            Frame.BackgroundColor3 = Dot == Index and Library.AccentColor or DialogBorderColor();
        end;

        Labels[1].Text = Index == #Pages and 'Done' or 'Next';
        Labels[2].Text = Index == 1 and 'Skip' or 'Back';

        if Direction and Library.Animations then
            Content.Position = UDim2.fromOffset(Direction * 10, TOP);
            Library:Animate(Content, 0.18, { Position = UDim2.fromOffset(0, TOP) });
        end;
    end;

    Labels = Dialog.Footer({ 'Next', 'Skip' }, function(Button)
        if Button == 1 and Current < #Pages then
            Show(Current + 1, 1);
        elseif Button == 2 and Current > 1 then
            Show(Current - 1, -1);
        else -- Done, or Skip on the first page
            Finished = true;
            Dialog.Close();
        end;
    end);

    Show(1);
    Dialog.Wait();
    return Finished or nil;
end;

function Library:Notify(Text, Time)
    if Library:NeedsUIThread() then
        return Library:RunOnUIThread(Library.Notify, Library, Text, Time);
    end;

    local XSize, YSize = Library:GetTextBounds(Text, Library.Font, 14);

    YSize = YSize + 7

    local NotifyOuter = Library:Create('Frame', {
        BorderColor3 = Color3.new(0, 0, 0);
        Position = UDim2.new(0, 100, 0, 10);
        Size = UDim2.new(0, 0, 0, YSize);
        ClipsDescendants = true;
        ZIndex = 100;
        Parent = Library.NotificationArea;
    });

    local NotifyInner = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderColor3 = Library.OutlineColor;
        BorderMode = Enum.BorderMode.Inset;
        Size = UDim2.new(1, 0, 1, 0);
        ZIndex = 101;
        Parent = NotifyOuter;
    });

    Library:AddToRegistry(NotifyInner, {
        BackgroundColor3 = 'MainColor';
        BorderColor3 = 'OutlineColor';
    }, true);

    local InnerFrame = Library:Create('Frame', {
        BackgroundColor3 = Color3.new(1, 1, 1);
        BorderSizePixel = 0;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 102;
        Parent = NotifyInner;
    });

    local Gradient = Library:Create('UIGradient', {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
            ColorSequenceKeypoint.new(1, Library.MainColor),
        });
        Rotation = -90;
        Parent = InnerFrame;
    });

    Library:AddToRegistry(Gradient, {
        Color = function()
            return ColorSequence.new({
                ColorSequenceKeypoint.new(0, Library:GetDarkerColor(Library.MainColor)),
                ColorSequenceKeypoint.new(1, Library.MainColor),
            });
        end
    });

    local NotifyLabel = Library:CreateLabel({
        Position = UDim2.new(0, 4, 0, 0);
        Size = UDim2.new(1, -4, 1, 0);
        Text = Text;
        TextXAlignment = Enum.TextXAlignment.Left;
        TextSize = 14;
        ZIndex = 103;
        Parent = InnerFrame;
    });

    local LeftColor = Library:Create('Frame', {
        BackgroundColor3 = Library.AccentColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, -1, 0, -1);
        Size = UDim2.new(0, 3, 1, 2);
        ZIndex = 104;
        Parent = NotifyOuter;
    });

    Library:AddToRegistry(LeftColor, {
        BackgroundColor3 = 'AccentColor';
    }, true);

    -- Time left: an accent bar along the bottom that empties over the notification's duration.
    local Duration = Time or 5;
    local TimeBar = Library:Create('Frame', {
        AnchorPoint = Vector2.new(0, 1);
        BackgroundColor3 = Library.AccentColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 2, 1, 0);
        Size = UDim2.new(1, -2, 0, 2);
        ZIndex = 104;
        Parent = NotifyOuter;
    });

    Library:AddToRegistry(TimeBar, {
        BackgroundColor3 = 'AccentColor';
    }, true);

    Library:Animate(NotifyOuter, 0.4, { Size = UDim2.new(0, XSize + 8 + 4, 0, YSize) });
    -- linear, not Library:CreateTween: the countdown runs even with Animations off, it is information
    TweenService:Create(TimeBar, TweenInfo.new(Duration, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 2) }):Play();

    task.spawn(function()
        task.wait(Duration);

        -- fade out (Library.Animations), then free the slot so the ones below move up
        if Library.Animations then
            Library:FadeTree(NotifyOuter, false, 0.35);
            task.wait(0.35);
        end;

        NotifyOuter:Destroy();
    end);
end;

-- =====================================================================
-- Sections: every groupbox and tabbox can be folded (the -/+ in its header), dragged by its header to another
-- spot in its tab (an accent box shows where it will land), or dropped outside the window to float as its own
-- panel. A floating panel's pin square keeps it on screen while the menu is hidden (StayOnHide). The layout is
-- written to Library.LayoutFile (SaveManager:SetFolder sets it) after every change.
-- =====================================================================
Library.Sections = {};
Library.LayoutFile = nil;
Library.Toggled = false;

local SectionDragThreshold = 6;     -- px of mouse travel before a header press becomes a drag
local SectionTouchHold = TOUCH_HOLD; -- s a finger must rest on a header before the box can be dragged
local SectionPlaceholder, SectionPlaceholderStroke;

local function MousePoint()
    return Vector2.new(Mouse.X, Mouse.Y);
end;

local function PointInFrame(Frame, Point)
    local Pos, Size = Frame.AbsolutePosition, Frame.AbsoluteSize;
    return Point.X >= Pos.X and Point.X <= Pos.X + Size.X and Point.Y >= Pos.Y and Point.Y <= Pos.Y + Size.Y;
end;

local function SortedBoxes(Column, Skip)
    local Boxes = {};

    for _, Child in next, Column:GetChildren() do
        if Child:IsA('GuiObject') and Child ~= Skip and Child ~= SectionPlaceholder then
            table.insert(Boxes, Child);
        end;
    end;

    table.sort(Boxes, function(A, B)
        return A.LayoutOrder < B.LayoutOrder;
    end);

    return Boxes;
end;

local function RenumberColumn(Column)
    for Index, Box in next, SortedBoxes(Column) do
        Box.LayoutOrder = Index * 10;
    end;
end;

-- Moves a section's box; the flag stops ScreenGui.DescendantRemoving from dropping its theme registrations.
local function MoveSectionBox(Section, Parent)
    Library.MovingSection = true;
    local Ok, Err = pcall(function()
        Section.Outer.Parent = Parent;
    end);
    Library.MovingSection = false;

    if not Ok then
        warn(Err);
    end;
end;

-- Front-most floating panel. With Global ZIndex, elements of two overlapping panels interleaved (one's dropdown
-- and buttons showing through the other, live 2026-10-15; a CanvasGroup per panel did not separate them), so each
-- panel has its own ScreenGui and DisplayOrder decides which is on top: 1..999, under the menu's 1000.
local PanelTop = 0;

local function RaiseSection(Section)
    if PanelTop >= 998 then
        local Order = {};

        for _, Other in next, Library.Sections do
            if Other.Gui then
                table.insert(Order, Other);
            end;
        end;

        table.sort(Order, function(A, B)
            return A.Gui.DisplayOrder < B.Gui.DisplayOrder;
        end);

        for Index, Other in next, Order do
            Other.Gui.DisplayOrder = Index;
        end;

        PanelTop = #Order;
    end;

    PanelTop = PanelTop + 1;
    Section.Gui.DisplayOrder = PanelTop;
end;

-- Section frames float inside a holder with its own UIScale, so they keep the window's size.
local function SectionHolder(Section)
    if not Section.Holder then
        local Gui = Instance.new('ScreenGui');
        ProtectGui(Gui);
        Gui.ZIndexBehavior = Enum.ZIndexBehavior.Global;
        Gui.DisplayOrder = 1;
        Gui.Parent = CoreGui;
        table.insert(PanelGuis, Gui);
        Section.Gui = Gui;

        Section.Holder = Library:Create('Frame', {
            BackgroundTransparency = 1;
            AutomaticSize = Enum.AutomaticSize.Y;
            Size = UDim2.fromOffset(260, 0);
            Visible = false;
            ZIndex = 1;
            Parent = Gui;
        });

        Library:RegisterPopup(Section.Holder);
        Kept[Section.Holder] = {};

        Section.Holder.InputBegan:Connect(function(Input)
            if IsClick(Input) then
                RaiseSection(Section);
            end;
        end);
    end;

    return Section.Holder;
end;

local PIN_FOLD_STROKE = 1; -- header icons sit next to 14px text; 2px strokes looked bolder than the title

function Library:UpdateSectionButtons(Section)
    Section.FoldBar.Visible = Section.Folded; -- the vertical bar turns the minus into a plus
    Section.PinButton.Visible = Section.Floating;
    if Section.LayoutHeader then
        Section.LayoutHeader(); -- the pin only shows while floating; the header makes room for it
    end;
    Section.PinOn.Visible = Section.Stay;
    Section.PinOff.Visible = not Section.Stay;

    if Section.Holder then
        Section.Holder.Visible = Section.Floating and (Section.Stay or Library.Toggled);
    end;

    -- Frosted glass: a docked box sits on the window's tint, so it only adds a faint panel; floating, it is the tint
    if Section.Inner then
        Section.Inner.BackgroundTransparency = Section.Floating and Library.GlassTransparency or 0.75;
    end;
end;

-- Folding (Library.Animations): the content fades out while the box closes, then hides; unfolding grows the box while
-- its rows fade in top to bottom a beat apart, and the -/+ spins. FoldRest / UnfoldRest keep the content's real
-- transparencies, so a fold interrupted halfway never leaves rows half faded. Instant: no animation (layout loading).
local FOLD_TIME = 0.22;
local ROW_FADE_TIME = 0.1; -- each row's own fade-in once the edge reaches it

function Library:SetSectionFolded(Section, Folded, Instant)
    Folded = Folded and true or false;

    local Outer = Section.Outer;
    local Content = Section.Content and Section.Content();
    local Animate = Library.Animations and not Instant and Content ~= nil and Folded ~= Section.Folded;
    local Token = {};
    Section.FoldToken = Token;
    Section.Animating = nil;
    Section.Switching = nil;

    if Section.FoldRest then
        Library:RestoreTree(Section.FoldRest); -- a fold-out that was still running
        Section.FoldRest = nil;
    end;

    Section.Folded = Folded;
    Library:UpdateSectionButtons(Section);

    if not Animate then
        Section.ApplyFold();
        Outer.ClipsDescendants = false;
        return;
    end;

    Section.FoldButton.Rotation = Folded and -180 or 180;
    Library:Animate(Section.FoldButton, 0.28, { Rotation = 0 });
    Outer.ClipsDescendants = true;

    if Folded then
        Section.FoldRest = Library:FadeTree(Content, false, FOLD_TIME * 0.8, Section.UnfoldRest);
        Section.UnfoldRest = nil;
        Section.Animating = true;
        Library:Animate(Outer, FOLD_TIME, { Size = UDim2.new(1, 0, 0, Section.FoldedHeight) });

        task.delay(FOLD_TIME + 0.02, function()
            if Section.FoldToken ~= Token then
                return;
            end;

            Section.Animating = nil;
            Section.ApplyFold();
            Library:RestoreTree(Section.FoldRest);
            Section.FoldRest = nil;
            Outer.ClipsDescendants = false;
        end);
    else
        local From = Outer.Size;
        Section.ApplyFold();
        local To = Outer.Size;
        Outer.Size = From;
        Section.Animating = true;
        Library:Animate(Outer, FOLD_TIME, { Size = To });

        task.delay(FOLD_TIME + 0.02, function()
            if Section.FoldToken == Token then
                Section.Animating = nil;
                Section.ApplyFold(); -- picks up anything that resized meanwhile
            end;
        end);

        -- each row fades in as the opening edge reaches it: the height eases out (Quad), so the edge passes fraction
        -- F of the content at FOLD_TIME * (1 - sqrt(1 - F)); the whole list is in by the time the box is open
        local Rows, Total = {}, 0;

        for _, Child in next, Content:GetChildren() do
            if Child:IsA('GuiObject') and Child.Visible then
                table.insert(Rows, Child);
                Total = Total + Child.Size.Y.Offset;
            end;
        end;

        local Rest, Top = {}, 0;

        for _, Child in next, Rows do
            local Fraction = math.clamp(Top / math.max(Total, 1), 0, 1);
            local Reached = FOLD_TIME * (1 - math.sqrt(1 - Fraction));
            Library:FadeTree(Child, true, ROW_FADE_TIME, Rest, math.max(Reached - ROW_FADE_TIME / 2, 0));
            Top = Top + Child.Size.Y.Offset;
        end;

        Section.UnfoldRest = Rest;

        task.delay(FOLD_TIME + ROW_FADE_TIME + 0.05, function()
            if Section.FoldToken == Token then
                Outer.ClipsDescendants = false;
                Section.UnfoldRest = nil;
            end;
        end);
    end;
end;

function Library:DockSection(Section, Side, Order)
    local Column = Side == 2 and Section.Tab.RightSide or Section.Tab.LeftSide;

    Section.Outer.LayoutOrder = Order or Section.DefaultOrder;
    MoveSectionBox(Section, Column);
    Section.Floating = false;
    RenumberColumn(Column);
    Library:UpdateSectionButtons(Section);
end;

function Library:FloatSection(Section, X, Y)
    local Holder = SectionHolder(Section);
    local Screen = ScreenGui.AbsoluteSize;

    Section.Width = Section.Width or (Section.Tab.LeftSide.AbsoluteSize.X / Library.UIScale);
    Holder.Size = UDim2.fromOffset(Section.Width, 0);
    -- keep at least the header on screen (the screen can be smaller than when the layout was saved)
    Holder.Position = UDim2.fromOffset(
        math.clamp(X, 0, math.max(Screen.X - 40, 0)),
        math.clamp(Y, 0, math.max(Screen.Y - 20, 0))
    );
    MoveSectionBox(Section, Holder);
    Section.Floating = true;
    RaiseSection(Section);
    Library:UpdateSectionButtons(Section);
end;

-- Floating panels without StayOnHide follow the menu; called by Library:Toggle.
function Library:UpdateFloatingSections()
    for _, Section in next, Library.Sections do
        if Section.Holder then
            Section.Holder.Visible = Section.Floating and (Section.Stay or Library.Toggled);
        end;
    end;
end;

function Library:GetLayout()
    local Data = {};

    for _, Section in next, Library.Sections do
        local Entry = { Folded = Section.Folded };

        if Section.Floating then
            Entry.Float = { Section.Holder.Position.X.Offset, Section.Holder.Position.Y.Offset };
            Entry.Width = Section.Width;
            Entry.Stay = Section.Stay;
        else
            Entry.Side = Section.Outer.Parent == Section.Tab.RightSide and 2 or 1;
            Entry.Order = Section.Outer.LayoutOrder;
        end;

        Data[Section.Key] = Entry;
    end;

    Data['@Menu'] = { Open = Library.Toggled };
    return Data;
end;

function Library:ApplyLayout(Data)
    if type(Data) ~= 'table' then
        return;
    end;

    for _, Section in next, Library.Sections do
        local Entry = Data[Section.Key];

        if type(Entry) == 'table' then
            if type(Entry.Float) == 'table' then
                Section.Width = tonumber(Entry.Width) or Section.Width;
                Section.Stay = Entry.Stay ~= false;
                Library:FloatSection(Section, tonumber(Entry.Float[1]) or 0, tonumber(Entry.Float[2]) or 0);
            elseif Entry.Side then
                Library:DockSection(Section, tonumber(Entry.Side), tonumber(Entry.Order));
            end;

            Library:SetSectionFolded(Section, Entry.Folded == true, true);
        end;
    end;

    -- the menu opens or stays hidden the way it was left (nil when the file predates this)
    local Menu = Data['@Menu'];
    Library.SavedOpen = nil;
    if type(Menu) == 'table' and type(Menu.Open) == 'boolean' then Library.SavedOpen = Menu.Open; end;
    if Library.SavedOpen ~= nil and Library.SavedOpen ~= Library.Toggled then
        Library:Toggle(Library.SavedOpen);
    end;
end;

function Library:SaveLayout()
    if not (Library.LayoutFile and writefile) then
        return;
    end;

    pcall(function()
        writefile(Library.LayoutFile, game:GetService('HttpService'):JSONEncode(Library:GetLayout()));
    end);
end;

function Library:LoadLayout()
    if not Library.LayoutFile then return; end;
    Library.LayoutLoaded = true; -- from now on Toggle saves the open state (earlier it would overwrite the saved layout)
    if not (isfile and isfile(Library.LayoutFile)) then
        return;
    end;

    local Ok, Data = pcall(function()
        return game:GetService('HttpService'):JSONDecode(readfile(Library.LayoutFile));
    end);

    if Ok then
        Library:ApplyLayout(Data);
    end;
end;

function Library:ResetLayout()
    -- every box back to its default column and order in one pass (docking one at a time renumbered the columns
    -- between moves, so equal orders could swap), folded per Section.DefaultFolded
    for _, Section in next, Library.Sections do
        Section.Stay = true;
        Section.Floating = false;
        Section.Outer.LayoutOrder = Section.DefaultOrder;
        MoveSectionBox(Section, Section.DefaultSide == 2 and Section.Tab.RightSide or Section.Tab.LeftSide);
        Library:UpdateSectionButtons(Section);
        Library:SetSectionFolded(Section, Section.DefaultFolded == true);
    end;

    Library:SaveLayout();
end;

-- The column of the section's own tab under Point, and the LayoutOrder that puts the box in front of the first
-- box whose middle is below Point (or at the end).
local function SectionDropTarget(Section, Point)
    local Tab = Section.Tab;

    if not (Tab.WindowOuter.Visible and Tab.Frame.Visible) then
        return;
    end;

    for _, Column in next, { Tab.LeftSide, Tab.RightSide } do
        if PointInFrame(Column, Point) then
            local Order = 5;

            for _, Box in next, SortedBoxes(Column, Section.Outer) do
                if Point.Y < Box.AbsolutePosition.Y + Box.AbsoluteSize.Y / 2 then
                    return Column, Box.LayoutOrder - 5;
                end;

                Order = Box.LayoutOrder + 5;
            end;

            return Column, Order;
        end;
    end;
end;

-- Touch: the finger's InputObject (nil for a mouse).
local function DragSection(Section, Touch)
    local Start, Began = MousePoint(), os.clock();

    while IsHeld() do
        local Moved = (MousePoint() - Start).Magnitude >= SectionDragThreshold;

        if Touch then
            -- a finger holds still first; one that moves at once is scrolling and pulled the box out of the window
            if Moved then
                return;
            end;

            if os.clock() - Began >= SectionTouchHold then
                break;
            end;
        elseif Moved then
            break;
        end;

        RenderStepped:Wait();
    end;

    if Library.DraggingSection or not IsHeld() then
        return; -- a click, not a drag
    end;

    if Touch then
        LongPressed[Touch] = true; -- picked up: lifting the finger is not a tap on the sub-tab it rested on
    end;

    Library.DraggingSection = Section;

    local Box = Section.Outer;
    local Grab = Start - Box.AbsolutePosition;
    local From = { Floating = Section.Floating, Parent = Box.Parent, Order = Box.LayoutOrder, At = Box.AbsolutePosition };

    if not SectionPlaceholder then
        SectionPlaceholder = Library:Create('Frame', {
            BackgroundTransparency = 0.85;
            BorderSizePixel = 0;
            ZIndex = 2;
        });

        SectionPlaceholderStroke = Library:Create('UIStroke', {
            Thickness = 1;
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border;
            Parent = SectionPlaceholder;
        });
    end;

    SectionPlaceholder.BackgroundColor3 = Library.AccentColor;
    SectionPlaceholderStroke.Color = Library.AccentColor;
    local PlaceholderHeight = Box.AbsoluteSize.Y / Library.UIScale;
    SectionPlaceholder.Size = UDim2.new(1, 0, 0, PlaceholderHeight);

    if not Section.Floating then
        Section.Width = Box.AbsoluteSize.X / Library.UIScale;
    end;

    local Holder = SectionHolder(Section);
    Holder.Size = UDim2.fromOffset(Section.Width, 0);
    Holder.Position = UDim2.fromOffset(Box.AbsolutePosition.X, Box.AbsolutePosition.Y);
    MoveSectionBox(Section, Holder);
    RaiseSection(Section);
    Holder.Visible = true;
    Section.Gui.DisplayOrder = ScreenGui.DisplayOrder + 1; -- over the window while it moves

    local Column, Order;
    local ShownColumn, ShownOrder;

    while IsHeld() do
        local Point = MousePoint();
        Holder.Position = UDim2.fromOffset(Point.X - Grab.X, Point.Y - Grab.Y);
        Column, Order = SectionDropTarget(Section, Point);

        if Column then
            if Column ~= ShownColumn or Order ~= ShownOrder then
                -- a new slot: the gap opens from nothing, so the boxes around it ease aside (Library.Animations)
                ShownColumn, ShownOrder = Column, Order;
                SectionPlaceholder.LayoutOrder = Order;
                SectionPlaceholder.Parent = Column;
                SectionPlaceholder.Size = UDim2.new(1, 0, 0, Library.Animations and 0 or PlaceholderHeight);
                Library:Animate(SectionPlaceholder, 0.15, { Size = UDim2.new(1, 0, 0, PlaceholderHeight) });
            end;
        else
            ShownColumn, ShownOrder = nil, nil;
            SectionPlaceholder.Parent = nil;
        end;

        RenderStepped:Wait();
    end;

    -- glide the box onto Target (screen px) before it is put down (Library.Animations)
    local function Snap(Target)
        if Library.Animations and Target then
            Library:Animate(Holder, 0.16, { Position = UDim2.fromOffset(Target.X, Target.Y) });
            task.wait(0.17);
        end;
    end;

    local Point = MousePoint();
    local Window = Section.Tab.WindowOuter;

    if Column then
        Snap(SectionPlaceholder.Parent and SectionPlaceholder.AbsolutePosition);
        SectionPlaceholder.Parent = nil;
        Library:DockSection(Section, Column == Section.Tab.RightSide and 2 or 1, Order);
    elseif Window.Visible and PointInFrame(Window, Point) then
        -- dropped on the window but not on a column (title, tab bar): put it back
        SectionPlaceholder.Parent = nil;
        Snap(From.At);
        if From.Floating then
            Library:FloatSection(Section, From.At.X, From.At.Y);
        else
            Library:DockSection(Section, From.Parent == Section.Tab.RightSide and 2 or 1, From.Order);
        end;
    else
        SectionPlaceholder.Parent = nil;
        Library:FloatSection(Section, Point.X - Grab.X, Point.Y - Grab.Y);
    end;

    Library.DraggingSection = nil;
    RaiseSection(Section); -- back under the menu, on top of the other panels
    Library:SaveLayout();
end;

-- Info: Key, Outer (the box frame), Inner (where the header buttons go), Tab (the window tab's columns),
-- Side, HeaderHeight (px from the top that starts a drag). The caller sets Section.ApplyFold.
function Library:RegisterSection(Info)
    local Section = {
        Key = Info.Key;
        Outer = Info.Outer;
        Tab = Info.Tab;
        HeaderHeight = Info.HeaderHeight;
        DefaultSide = Info.Side;
        DefaultOrder = Info.Outer.LayoutOrder;
        Folded = false;
        Floating = false;
        Stay = true;
        ApplyFold = function() end;
    };

    -- Frosted glass: a floating panel has no window behind it, so it carries its own blur
    if Library.GlassTransparency > 0 or Library.Blur then -- Blur: a glass window whose opacity is set to solid
        Section.Inner = Info.Inner; -- tinted by Library:UpdateSectionButtons
        Info.Outer.BackgroundTransparency = 1;
        Info.Inner.BackgroundTransparency = 0.75;
        -- A border is as see-through as its frame's background: the outer one (outline color) vanished with it, and
        -- the inner black one was left as a near-black line around every box. The boxes draw their outline as lines
        -- instead (Tab:AddGroupbox / Tab:AddTabbox).
        Info.Inner.BorderSizePixel = 0;

        Library:AddGlass(Info.Outer, function()
            local Shown = Section.Floating and Section.Holder ~= nil and Section.Holder.Visible;
            return Shown, Shown;
        end);
    end;

    -- Lucide minus / plus (one 'plus' icon; UpdateSectionButtons hides its vertical bar while unfolded)
    Section.FoldButton = Library:Create('Frame', {
        BackgroundTransparency = 1;
        Position = UDim2.new(1, -16, 0, 2);
        Size = UDim2.fromOffset(14, 16);
        ZIndex = 12;
        Parent = Info.Inner;
    });

    local _, FoldPieces = Library:CreateIcon('plus', {
        AnchorPoint = Vector2.new(0.5, 0.5);
        Position = UDim2.fromScale(0.5, 0.5);
        Size = 12;
        Thickness = PIN_FOLD_STROKE;
        ZIndex = 12;
        Parent = Section.FoldButton;
    });
    Section.FoldBar = FoldPieces[2];
    Section.FoldBar.Visible = false; -- unfolded: a minus. Without a saved layout nothing else set it, and every box showed +

    -- Lucide pin (stays while the menu is hidden) / pin-off (hides with the menu)
    Section.PinButton = Library:Create('Frame', {
        BackgroundTransparency = 1;
        Position = UDim2.new(1, -31, 0, 3);
        Size = UDim2.fromOffset(13, 13);
        Visible = false;
        ZIndex = 12;
        Parent = Info.Inner;
    });

    Section.PinOn = Library:CreateIcon('pin', { Color = 'AccentColor'; Size = 13; Thickness = PIN_FOLD_STROKE; ZIndex = 12; Parent = Section.PinButton });
    Section.PinOff = Library:CreateIcon('pin-off', {
        Color = function() return Library.OutlineColor:Lerp(Library.FontColor, 0.5); end;
        Size = 13;
        Thickness = PIN_FOLD_STROKE;
        ZIndex = 12;
        Parent = Section.PinButton;
    });

    Library:AddToolTip('Stay on screen while the menu is hidden', Section.PinButton);

    Section.FoldButton.InputBegan:Connect(function(Input)
        if IsTap(Input) and not Library:MouseIsOverOpenedFrame() then
            Library:SetSectionFolded(Section, not Section.Folded);
            Library:SaveLayout();
        end;
    end);

    Section.PinButton.InputBegan:Connect(function(Input)
        if IsTap(Input) then
            Section.Stay = not Section.Stay;
            Library:UpdateSectionButtons(Section);
            Library:SaveLayout();
        end;
    end);

    Section.Outer.InputBegan:Connect(function(Input)
        if not IsClick(Input) or Library:MouseIsOverOpenedFrame() then
            return;
        end;

        -- the press itself, not the shared Mouse position: a stale value above the box also passed "<= header"
        local Y = (Input.Position.Y - Section.Outer.AbsolutePosition.Y) / Library.UIScale;
        if Y >= 0 and Y <= Section.HeaderHeight then
            DragSection(Section, Input.UserInputType == Enum.UserInputType.Touch and Input); -- the touch itself
        end;
    end);

    table.insert(Library.Sections, Section);
    return Section;
end;

-- Fading a whole tree. A CanvasGroup's GroupTransparency did nothing in this executor's CoreGui (live 2026-10-16), so
-- like the menu fade this eases each descendant's own transparency. Rest[instance] = { property = value } is what
-- "shown" means: filled from the current values when missing, and put back with RestoreTree once a hidden tree is
-- out of sight, so the next fade starts from the real values.
local function TreeFadeProperties(Instance)
    if Instance:IsA('TextLabel') or Instance:IsA('TextButton') or Instance:IsA('TextBox') then
        return { 'TextTransparency', 'BackgroundTransparency' };
    elseif Instance:IsA('ImageLabel') or Instance:IsA('ImageButton') then
        return { 'ImageTransparency', 'BackgroundTransparency' };
    elseif Instance:IsA('Frame') or Instance:IsA('ScrollingFrame') then
        return { 'BackgroundTransparency' };
    elseif Instance:IsA('UIStroke') then
        return { 'Transparency' };
    end;
end;

-- What is on screen of a tree: Root and its visible descendants, leaving out hidden branches (folded content, other
-- tabs) and anything outside the clipping frames it sits in (rows scrolled out of a column). Returns the list, Root
-- first, and the same as a set. Fading only these is what keeps a fade off the frame time: see Library:Toggle and
-- Tab:ShowTab for the measurements.
local CULL_MARGIN = 40; -- px around a clipping frame still counted as on screen (glows spill past their frames)

function Library:ShownTree(Root)
    local Shown, InShown = { Root }, { [Root] = true };

    -- X0..Y1: the window of the clipping frames Node sits in (nil = none)
    local function Collect(Node, X0, Y0, X1, Y1)
        for _, Child in next, Node:GetChildren() do
            if Child:IsA('GuiObject') then
                if Child.Visible then
                    local Pos, Size = Child.AbsolutePosition, Child.AbsoluteSize;
                    local AX, AY = Pos.X, Pos.Y;
                    local BX, BY = AX + Size.X, AY + Size.Y;

                    if not X0 or (BX >= X0 - CULL_MARGIN and AX <= X1 + CULL_MARGIN
                        and BY >= Y0 - CULL_MARGIN and AY <= Y1 + CULL_MARGIN) then

                        Shown[#Shown + 1] = Child;
                        InShown[Child] = true;

                        if Child.ClipsDescendants then
                            Collect(Child,
                                X0 and math.max(X0, AX) or AX, Y0 and math.max(Y0, AY) or AY,
                                X1 and math.min(X1, BX) or BX, Y1 and math.min(Y1, BY) or BY);
                        else
                            Collect(Child, X0, Y0, X1, Y1);
                        end;
                    end;
                end;
            elseif Child:IsA('UIStroke') then
                Shown[#Shown + 1] = Child;
                InShown[Child] = true;
            end;
        end;
    end;

    Collect(Root);
    return Shown, InShown;
end;

-- Delay (optional): seconds before the tween starts; a tree being shown goes transparent at once and waits.
-- Only (optional): the instances to fade instead of the whole tree, e.g. Library:ShownTree(Root).
-- Rest.Tweens: the fades started with this Rest, so RestoreTree can stop the ones still running.
function Library:FadeTree(Root, Visible, Time, Rest, Delay, Only)
    Rest = Rest or {};
    local Tweens = Rest.Tweens or {};
    Rest.Tweens = Tweens;
    local Info = TweenInfo.new(Time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, Delay or 0);

    local List = Only;

    if not List then
        List = Root:GetDescendants();
        table.insert(List, 1, Root); -- the root as well: a label row is itself the thing to fade
    end;

    for _, Desc in next, List do
        local Properties = TreeFadeProperties(Desc);

        if Properties then
            local Saved = Rest[Desc];

            if not Saved then
                Saved = {};

                for _, Property in next, Properties do
                    Saved[Property] = Desc[Property];
                end;

                Rest[Desc] = Saved;
            end;

            local Goal = {};

            for Property, Value in next, Saved do
                if Value < 1 then
                    if Visible then
                        Desc[Property] = 1;
                    end;

                    Goal[Property] = Visible and Value or 1;
                end;
            end;

            if next(Goal) then
                local Tween = TweenService:Create(Desc, Info, Goal);
                Tweens[#Tweens + 1] = Tween;
                Tween:Play();
            end;
        end;
    end;

    return Rest;
end;

-- For state shown as a transparency (a dimmed label): tells the menu's open / close fade the value the instance
-- should have. Changed while the menu is hidden, it would otherwise fade back in to the value it had when it was
-- closed: a toggle switched by its keybind kept the old brightness of its label. Library:CreateWindow replaces this.
function Library:RememberTransparency(Instance, Property, Value)
end;

function Library:RestoreTree(Rest)
    if not Rest then
        return;
    end;

    -- a fade still running would carry on over the values put back here (a tab hidden mid slide went on fading
    -- out, and stayed invisible, once the menu's own fade no longer ran over every instance)
    for _, Tween in next, Rest.Tweens or {} do
        Tween:Cancel();
    end;
    Rest.Tweens = nil;

    for Desc, Saved in next, Rest do
        for Property, Value in next, Saved do
            pcall(function()
                Desc[Property] = Value;
            end);
        end;
    end;
end;

function Library:CreateWindow(...)
    local Arguments = { ... }
    local Config = { AnchorPoint = Vector2.zero }

    if type(...) == 'table' then
        Config = ...;
    else
        Config.Title = Arguments[1]
        Config.AutoShow = Arguments[2] or false;
    end

    if type(Config.Title) ~= 'string' then Config.Title = 'No title' end
    if type(Config.TabPadding) ~= 'number' then Config.TabPadding = 0 end
    if type(Config.MenuFadeTime) ~= 'number' then Config.MenuFadeTime = 0.2 end

    if typeof(Config.Position) ~= 'UDim2' then Config.Position = UDim2.fromOffset(175, 50) end
    if typeof(Config.Size) ~= 'UDim2' then Config.Size = UDim2.fromOffset(550, 600) end

    -- Phones: shrink the window to fit the screen and center it (the corner grip resizes it from there).
    local Viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize;
    if IsMobile and Viewport then
        Config.Size = UDim2.fromOffset(
            math.min(Config.Size.X.Offset, math.floor(Viewport.X * 0.92)),
            math.min(Config.Size.Y.Offset, math.floor(Viewport.Y * 0.85))
        );
        Config.Center = true;
    end;

    if Config.Center then
        Config.AnchorPoint = Vector2.new(0.5, 0.5)
        Config.Position = UDim2.fromScale(0.5, 0.5)
    end

    local Window = {
        Tabs = {};
    };

    -- Tab bar shades (the outline pieces below carry them, so they follow its rounded corners). Glass: the window
    -- tint is the content shade, so the bar around the active tab is darkened over it. Solid: the bar is already the
    -- darker color, so the active tab is filled with the content color.
    local Glass = Library.GlassTransparency > 0;
    local TAB_SHADE = 0.4;
    local TAB_HEIGHT, TAB_PADDING = 26, 12; -- VS Code proportions: room above / below and either side of the name
    local TAB_RADIUS = 5;                   -- corners of the outline around the active tab
    -- Title bar. On glass the box under it is clear, so the title is centred between the window's top edge and the
    -- tab bar 8px further down: 10px above and below the text, as in VS Code's title bar.
    local TITLE_HEIGHT = 28;
    -- Margins at the window's sides and bottom, kept small so the sections sit close to its edge (they added up to
    -- 24 px of empty frame each side: 8 + 8 + 7).
    --   WINDOW_PAD: window edge to the panel under the title. On glass that panel is clear, so the margin was all air.
    --   PANEL_PAD:  that panel to the tab bar and the content box.
    --   COLUMN_PAD: the content box to the two columns of sections.
    local WINDOW_PAD = Glass and 2 or 8;
    local PANEL_PAD, COLUMN_PAD = 4, 4;

    -- 1px outline pieces of the tab bar and content box. On glass the theme's outline color sinks into the blurred
    -- scene behind it, so it is lifted toward the font color (as the off toggle boxes are).
    local function LineColor()
        return Glass and Library.OutlineColor:Lerp(Library.FontColor, 0.2) or Library.OutlineColor;
    end;

    local function Line(Properties)
        Properties.BackgroundColor3 = LineColor();
        Properties.BorderSizePixel = 0;
        local Frame = Library:Create('Frame', Properties);
        Library:AddToRegistry(Frame, { BackgroundColor3 = LineColor });
        return Frame;
    end;

    local Outer = Library:Create('Frame', {
        AnchorPoint = Config.AnchorPoint,
        BackgroundColor3 = Color3.new(0, 0, 0);
        BorderSizePixel = 0;
        Position = Config.Position,
        Size = Config.Size,
        Visible = false;
        ZIndex = 1;
        Parent = ScreenGui;
    });

    Library:MakeDraggable(Outer, TITLE_HEIGHT, true);
    Library.WindowTitleHeight = TITLE_HEIGHT; -- dialogs leave the title bar draggable (OpenDialog)

    -- NieR-style resize grip: a triangle of 2px accent dots in the bottom-right corner, faint at rest and solid on
    -- hover / while dragging. Drag it (mouse or finger) to resize; the top-left corner stays put.
    local MinWindowSize = Vector2.new(400, 300);
    local ResizeGrip = Library:Create('Frame', {
        Name = 'ResizeGrip';
        AnchorPoint = Vector2.new(1, 1);
        BackgroundTransparency = 1;
        Position = UDim2.new(1, 0, 1, 0);
        Size = IsMobile and UDim2.fromOffset(28, 28) or UDim2.fromOffset(16, 16);
        ZIndex = 20;
        Parent = Outer;
    });

    local GripDots = {};
    local GripIdle = 0.55;
    for Column = 0, 2 do
        for Row = 0, 2 - Column do
            local Dot = Library:Create('Frame', {
                AnchorPoint = Vector2.new(1, 1);
                BackgroundColor3 = Library.AccentColor;
                BackgroundTransparency = GripIdle;
                BorderSizePixel = 0;
                Position = UDim2.new(1, -3 - Column * 4, 1, -3 - Row * 4);
                Size = UDim2.fromOffset(2, 2);
                ZIndex = 21;
                Parent = ResizeGrip;
            });
            Library:AddToRegistry(Dot, { BackgroundColor3 = 'AccentColor' });
            table.insert(GripDots, Dot);
        end;
    end;

    local GripHovered, Resizing = false, false;
    local function RefreshGrip()
        for _, Dot in next, GripDots do
            Library:Animate(Dot, 0.15, { BackgroundTransparency = (GripHovered or Resizing) and 0 or GripIdle });
        end;
    end;

    ResizeGrip.MouseEnter:Connect(function() GripHovered = true; RefreshGrip(); end);
    ResizeGrip.MouseLeave:Connect(function() GripHovered = false; RefreshGrip(); end);

    ResizeGrip.InputBegan:Connect(function(Input)
        if not IsClick(Input) or Resizing then return; end;

        Resizing = true;
        RefreshGrip();

        local StartPointer = Vector2.new(Mouse.X, Mouse.Y);
        local StartSize, StartPosition = Outer.Size, Outer.Position;
        local Anchor = Outer.AnchorPoint;

        while IsHeld() and Outer.Parent do
            -- pointer moves in screen pixels; Size is unscaled UI pixels, Position is screen pixels
            local Scale = math.max(Library.UIScale or 1, 0.01);
            local Delta = (Vector2.new(Mouse.X, Mouse.Y) - StartPointer) / Scale;
            -- it may get narrower than its tabs: the tab bar scrolls then (TabArea)
            local Width = math.max(StartSize.X.Offset + Delta.X, MinWindowSize.X);
            local Height = math.max(StartSize.Y.Offset + Delta.Y, MinWindowSize.Y);

            Outer.Size = UDim2.new(StartSize.X.Scale, Width, StartSize.Y.Scale, Height);
            -- shift by the anchored share of the growth so the top-left corner stays fixed
            Outer.Position = StartPosition + UDim2.fromOffset(
                Anchor.X * (Width - StartSize.X.Offset) * Scale,
                Anchor.Y * (Height - StartSize.Y.Offset) * Scale
            );

            RenderStepped:Wait();
        end;

        Resizing = false;
        RefreshGrip();
    end);

    -- Soft accent-colored glow behind the window; see Library:SetGlow. ZIndex 0 puts it under Outer
    -- (the ScreenGui uses Global ZIndex), and being a child it scales and drags with the window.
    local Glow = Library:AddGlow(Outer, Library.GlowSize, 0, 'AccentColor');
    Glow.ImageTransparency = Library.GlowEnabled and Library.GlowTransparency or 1;
    Library.WindowGlow = Library.WindowGlow or Glow;

    local Inner = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 1;
        Parent = Outer;
    });

    Library:AddToRegistry(Inner, {
        BackgroundColor3 = 'MainColor';
    });

    -- The accent border is a 1px stroke with a vertical gradient instead of a flat BorderColor3, so it can
    -- carry the same top-to-bottom hue range as the gradient accent (see Library:GetAccentSequence).
    local BorderStroke = Library:Create('UIStroke', {
        Color = Color3.new(1, 1, 1);
        Thickness = 1;
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border;
        LineJoinMode = Enum.LineJoinMode.Miter;
        Parent = Inner;
    });

    local BorderGradient = Library:Create('UIGradient', {
        Color = Library:GetAccentSequence();
        Rotation = 90;
        Parent = BorderStroke;
    });

    Library:AddToRegistry(BorderGradient, {
        Color = function()
            return Library:GetAccentSequence();
        end;
    });

    Library.WindowBorderGradient = Library.WindowBorderGradient or BorderGradient;

    -- as wide as the window less a margin, and cut with "..." there: a zero-width label let a long title run out
    -- past both edges of a narrowed window
    -- Title alone sits centred, as always. With Version / Channel / Subtitle / TitleNote the bar becomes a header: the
    -- title on the left with the version and the channel as badges, the subtitle centred, the note (an invite, a
    -- status) on the right.
    local Header = Config.Version or Config.Channel or Config.Subtitle or Config.TitleNote;
    local TITLE_BAR, TITLE_PAD = TITLE_HEIGHT + (Glass and 8 or 0), 12;
    local WindowLabel = Library:CreateLabel({
        Position = UDim2.new(0, Header and TITLE_PAD or 10, 0, 0);
        Size = UDim2.new(1, -20, 0, TITLE_BAR);
        Text = Config.Title or '';
        TextTruncate = Enum.TextTruncate.AtEnd;
        TextXAlignment = Header and Enum.TextXAlignment.Left or Enum.TextXAlignment.Center;
        ZIndex = 1;
        Parent = Inner;
    });

    local FitTitle = function() end;

    if Header then
        local Subtitle, Note;
        local SubtitleWidth, NoteWidth = 0, 0;
        local Badges = {}; -- { frame, width }, left to right after the title

        -- Pill after the title: Tint over the menu color as the fill (Mix = how much of it), Tint as the outline.
        -- Tint is a registry color key (follows the theme) or a fixed Color3; TintText colors the text too.
        local function AddBadge(Text, TextSize, Tint, Mix, TintText)
            local Fixed = typeof(Tint) == 'Color3';
            local function Color() return Fixed and Tint or Library[Tint]; end;

            local Width = Library:GetTextBounds(Text, Library.Font, TextSize) + 14;
            local Badge = Library:Create('Frame', {
                AnchorPoint = Vector2.new(0, 0.5);
                BackgroundColor3 = Library.MainColor;
                BorderSizePixel = 0;
                Size = UDim2.fromOffset(Width, 18);
                ZIndex = 1;
                Parent = Inner;
            });

            Library:AddToRegistry(Badge, { BackgroundColor3 = 'MainColor' });
            Library:Create('UICorner', { CornerRadius = UDim.new(1, 0); Parent = Badge });

            -- The tint is a see-through frame of its own in the accent: a plain registry color key, which is what an
            -- animated or gradient accent repaints (Library:UpdateAccentColors). Mixed into one color it needed a
            -- function there, and those only run on a theme change: with the rainbow on, the badge stayed the red
            -- the rainbow happened to be at when the window was built.
            local Fill = Library:Create('Frame', {
                BackgroundColor3 = Color();
                BackgroundTransparency = 1 - Mix;
                BorderSizePixel = 0;
                Size = UDim2.fromScale(1, 1);
                ZIndex = 2;
                Parent = Badge;
            });

            Library:Create('UICorner', { CornerRadius = UDim.new(1, 0); Parent = Fill });

            local Stroke = Library:Create('UIStroke', {
                Color = Color();
                Thickness = 1;
                ApplyStrokeMode = Enum.ApplyStrokeMode.Border;
                Parent = Badge;
            });

            local Label = Library:CreateLabel({
                Size = UDim2.fromScale(1, 1);
                Text = Text;
                TextSize = TextSize;
                ZIndex = 3;
                Parent = Badge;
            });

            if TintText then
                Library:RemoveFromRegistry(Label);
                Label.TextColor3 = Color();
            end;

            if not Fixed then
                Library:AddToRegistry(Fill, { BackgroundColor3 = Tint });
                Library:AddToRegistry(Stroke, { Color = Tint });
                if TintText then Library:AddToRegistry(Label, { TextColor3 = Tint }); end;
            end;

            table.insert(Badges, { Badge, Width });
        end;

        if Config.Version then
            AddBadge(Config.Version, 12, 'AccentColor', 0.35);
        end;

        if Config.Channel then -- the release channel (BETA, ...): green on every theme, apart from the accent
            AddBadge(Config.Channel, 11, Color3.fromRGB(152, 195, 121), 0.25, true);
        end;

        if Config.Subtitle then
            SubtitleWidth = Library:GetTextBounds(Config.Subtitle, Library.Font, 14);
            Subtitle = Library:CreateLabel({
                AnchorPoint = Vector2.new(0.5, 0);
                Position = UDim2.fromScale(0.5, 0);
                Size = UDim2.fromOffset(SubtitleWidth + 2, TITLE_BAR);
                Text = Config.Subtitle;
                TextSize = 14;
                TextTransparency = 0.2; -- a step under the title; 0.5 was too faint to read
                ZIndex = 1;
                Parent = Inner;
            });
        end;

        if Config.TitleNote then
            NoteWidth = Library:GetTextBounds(Config.TitleNote, Library.Font, 14);
            Note = Library:CreateLabel({
                AnchorPoint = Vector2.new(1, 0);
                Position = UDim2.new(1, -TITLE_PAD, 0, 0);
                Size = UDim2.fromOffset(NoteWidth + 2, TITLE_BAR);
                Text = Config.TitleNote;
                TextSize = 14;
                TextTransparency = 0.2;
                TextXAlignment = Enum.TextXAlignment.Right;
                ZIndex = 1;
                Parent = Inner;
            });
        end;

        -- A narrowed window drops what no longer fits instead of running the texts into each other: the subtitle
        -- first, then the note. From the window's own Size, as its AbsoluteSize moves with the open / close scale.
        FitTitle = function()
            local Width = Outer.Size.X.Scale == 0 and Outer.Size.X.Offset or Inner.AbsoluteSize.X;
            local Left = TITLE_PAD + Library:GetTextBounds(WindowLabel.Text, Library.Font, 16);
            local GAP = 16;

            for Index, Badge in next, Badges do
                local Gap = Index == 1 and 10 or 6;
                Badge[1].Position = UDim2.fromOffset(Left + Gap, TITLE_BAR / 2);
                Left = Left + Gap + Badge[2];
            end;

            local ShowNote = Note ~= nil and Left + GAP + NoteWidth + TITLE_PAD <= Width;
            if Note then Note.Visible = ShowNote; end;

            -- Centred in the window while that clears its neighbours, else centred in the room between them (the
            -- menu's default 550 px with two badges and an invite), else hidden.
            if Subtitle then
                local From = Left + GAP;
                local To = Width - (ShowNote and NoteWidth + TITLE_PAD + GAP or TITLE_PAD);
                local Centre = Width / 2;

                if Centre - SubtitleWidth / 2 < From or Centre + SubtitleWidth / 2 > To then
                    Centre = (From + To) / 2;
                end;

                Subtitle.Visible = To - From >= SubtitleWidth;
                Subtitle.Position = UDim2.fromOffset(math.floor(Centre), 0);
            end;
        end;

        Outer:GetPropertyChangedSignal('Size'):Connect(FitTitle);
        FitTitle();
    end;

    local MainSectionOuter = Library:Create('Frame', {
        BackgroundColor3 = Library.BackgroundColor;
        BorderColor3 = Library.OutlineColor;
        Position = UDim2.new(0, WINDOW_PAD, 0, TITLE_HEIGHT);
        Size = UDim2.new(1, -WINDOW_PAD * 2, 1, -(TITLE_HEIGHT + WINDOW_PAD));
        ZIndex = 1;
        Parent = Inner;
    });

    Library:AddToRegistry(MainSectionOuter, {
        BackgroundColor3 = 'BackgroundColor';
        BorderColor3 = 'OutlineColor';
    });

    local MainSectionInner = Library:Create('Frame', {
        BackgroundColor3 = Library.BackgroundColor;
        BorderColor3 = Color3.new(0, 0, 0);
        BorderMode = Enum.BorderMode.Inset;
        Position = UDim2.new(0, 0, 0, 0);
        Size = UDim2.new(1, 0, 1, 0);
        ZIndex = 1;
        Parent = MainSectionOuter;
    });

    Library:AddToRegistry(MainSectionInner, {
        BackgroundColor3 = 'BackgroundColor';
    });

    -- The tab strip scrolls sideways once the tabs no longer fit, as VS Code's does: the mouse wheel or a swipe moves
    -- it, a tab that is opened scrolls into view (Window:RevealTab), and a thin bar along its bottom edge shows while
    -- the pointer is over it (always on touch screens, which have no pointer).
    local TabArea = Library:Create('ScrollingFrame', {
        BackgroundTransparency = 1;
        BorderSizePixel = 0;
        Position = UDim2.new(0, PANEL_PAD, 0, 8);
        Size = UDim2.new(1, -PANEL_PAD * 2, 0, TAB_HEIGHT);
        CanvasSize = UDim2.new();
        ScrollingDirection = Enum.ScrollingDirection.X;
        ElasticBehavior = Enum.ElasticBehavior.Never;
        ScrollBarThickness = 2;
        ScrollBarImageColor3 = Library.FontColor;
        ScrollBarImageTransparency = IsMobile and 0.5 or 1;
        TopImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png';
        BottomImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png';
        ZIndex = 7; -- its scroll bar over the bar's shades and names
        Parent = MainSectionInner;
    });

    Library:AddToRegistry(TabArea, { ScrollBarImageColor3 = 'FontColor' });

    if not IsMobile then
        TabArea.MouseEnter:Connect(function() TabArea.ScrollBarImageTransparency = 0.5; end);
        TabArea.MouseLeave:Connect(function() TabArea.ScrollBarImageTransparency = 1; end);
    end;

    local TabListLayout = Library:Create('UIListLayout', {
        Padding = UDim.new(0, Config.TabPadding);
        FillDirection = Enum.FillDirection.Horizontal;
        SortOrder = Enum.SortOrder.LayoutOrder;
        Parent = TabArea;
    });
    Window.TabListLayout = TabListLayout;

    -- Tabs that nearly fill the bar are widened to end exactly on its right edge (one px past the strip, on the
    -- outline's edge column): the few px left over looked like a sliver of an extra tab. Window.TabsWidth is their
    -- natural width, which the resize grip keeps the window wider than.
    local AllTabs = {};
    local function FitTabs()
        -- measured, not summed from the frames' offsets: an inset border (MainSectionInner) also narrows its contents
        local ScaleObject = Outer:FindFirstChildOfClass('UIScale');
        local BarWidth = math.floor(TabArea.AbsoluteSize.X / math.max(ScaleObject and ScaleObject.Scale or 1, 0.01) + 0.5);
        local Used = 0;

        for _, Tab in next, AllTabs do
            Used = Used + Tab.NaturalWidth + Config.TabPadding;
        end;

        local Spare = BarWidth + 1 - Used;
        local Fit = BarWidth > 0 and Spare > 0 and Spare <= TAB_PADDING * 3;

        for Index, Tab in next, AllTabs do
            local More = Fit and (math.floor(Spare / #AllTabs) + (Index <= Spare % #AllTabs and 1 or 0)) or 0;
            Tab.Button.Size = UDim2.new(0, Tab.NaturalWidth + More, 1, 0);
        end;

        Window.TabsWidth = Used;
        TabArea.CanvasSize = UDim2.fromOffset(Used > BarWidth and Used or 0, 0); -- more tabs than fit: scroll
    end;

    TabArea:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()
        FitTabs();

        if Window.ActiveTab then
            Window:RevealTab(Window.ActiveTab); -- the window was narrowed: the active tab stays in the bar
        end;
    end);

    -- Tab bar outline, VS Code style: a line along the top, and one along the bottom that turns up either side of
    -- the active tab into its outline, every turn rounded. Three stroked rounded boxes, each seen through a clip that
    -- shows only its part: the top half of the active tab's box (its top corners), and the bottom half of a box left
    -- and right of it (the bottom corners). A box runs TabReach px past its clip wherever its edge must not show.
    -- The layer is 1px larger than the tab strip all round; Window:MoveUnderline slides the pieces to the active tab.
    local TabHalf, TabReach = math.floor((TAB_HEIGHT + 2) / 2), TAB_RADIUS + 4;
    local TabLower = TAB_HEIGHT + 2 - TabHalf;
    local TabOutline = Library:Create('Frame', {
        BackgroundTransparency = 1;
        ClipsDescendants = true; -- the active tab's outline goes with its tab when that is scrolled out of the bar
        Position = TabArea.Position - UDim2.fromOffset(1, 1);
        Size = TabArea.Size + UDim2.fromOffset(2, 2);
        ZIndex = 4;
        Parent = MainSectionInner;
    });

    -- Fill (optional): the registry color the box is filled with, and its transparency. The shades ride on the same
    -- boxes as the outline, so a fill never sticks out past a rounded corner. Stroke = false: a fill-only piece.
    local function OutlinePiece(ClipProperties, BoxProperties, Fill, FillTransparency, Stroke)
        local ZIndex = Stroke == false and 3 or 4; -- a fill-only piece stays under the other pieces' lines
        ClipProperties.BackgroundTransparency = 1;
        ClipProperties.ClipsDescendants = true;
        ClipProperties.ZIndex = ZIndex;
        ClipProperties.Parent = TabOutline;
        local Clip = Library:Create('Frame', ClipProperties);

        BoxProperties.BackgroundColor3 = Fill and Library[Fill] or nil;
        BoxProperties.BackgroundTransparency = Fill and FillTransparency or 1;
        BoxProperties.BorderSizePixel = 0;
        BoxProperties.ZIndex = ZIndex;
        BoxProperties.Parent = Clip;
        local Box = Library:Create('Frame', BoxProperties);

        Library:Create('UICorner', { CornerRadius = UDim.new(0, TAB_RADIUS); Parent = Box });

        if Fill then
            Library:AddToRegistry(Box, { BackgroundColor3 = Fill });
        end;

        if Stroke ~= false then
            Library:AddToRegistry(Library:Create('UIStroke', {
                Color = LineColor();
                Thickness = 1;
                ApplyStrokeMode = Enum.ApplyStrokeMode.Border;
                Parent = Box;
            }), { Color = LineColor });
        end;

        return Clip, Box;
    end;

    -- The bar's shade either side of the active tab. Bottom half: the outline boxes themselves. Top half (glass
    -- only; a solid bar already is that color): fill-only boxes sharing the bar's rounded top corners.
    local BarShade = Glass and TAB_SHADE or 0;
    local ActiveClip, ActiveBox = OutlinePiece({}, { Position = UDim2.fromOffset(1, 1) }, not Glass and 'MainColor', 0);
    local LeftClip, LeftBox = OutlinePiece({ Position = UDim2.fromOffset(0, TabHalf) }, { Position = UDim2.fromOffset(-TabReach, -TabReach) }, 'BackgroundColor', BarShade);
    local RightClip = OutlinePiece({}, {
        Position = UDim2.fromOffset(1, -TabReach);
        Size = UDim2.new(1, TabReach - 1, 0, TabLower - 1 + TabReach);
    }, 'BackgroundColor', BarShade);
    local UpperLeftClip, UpperRightClip;

    if Glass then
        UpperLeftClip = OutlinePiece({}, {
            Position = UDim2.fromOffset(1, 1);
            Size = UDim2.new(1, TabReach, 0, TAB_HEIGHT + TabReach);
        }, 'BackgroundColor', BarShade, false);
        UpperRightClip = OutlinePiece({}, {
            Position = UDim2.fromOffset(-TabReach, 1);
            Size = UDim2.new(1, TabReach - 1, 0, TAB_HEIGHT + TabReach);
        }, 'BackgroundColor', BarShade, false);
    end;

    -- The bar's own outline: the top line with rounded ends (the top half of a box as wide as the bar), then both
    -- sides straight down into the content box's outline. The sides are plain lines: a box seen through a 1px wide
    -- clip did not draw at all in the live menu.
    OutlinePiece({ Size = UDim2.new(1, 0, 0, TabHalf) }, { Position = UDim2.fromOffset(1, 1); Size = UDim2.new(1, -2, 0, TAB_HEIGHT + TabReach) });
    Line({ Position = UDim2.fromOffset(0, TabHalf); Size = UDim2.fromOffset(1, TabLower); ZIndex = 4; Parent = TabOutline });
    Line({ Position = UDim2.new(1, -1, 0, TabHalf); Size = UDim2.fromOffset(1, TabLower); ZIndex = 4; Parent = TabOutline });

    -- Solid menu: the active tab's bottom half, in the content color, under the boxes left and right of it (their
    -- fill covers it up to their rounded corners). It also covers the content box's top border below the tab.
    local ActiveLower = not Glass and Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderSizePixel = 0;
        ZIndex = 3;
        Parent = TabOutline;
    });

    if ActiveLower then
        Library:AddToRegistry(ActiveLower, { BackgroundColor3 = 'MainColor' });
    end;

    local OutlineTweens = {};

    function Window:MoveUnderline(Instant)
        local Tab = Window.ActiveTab;
        if not Tab then
            return;
        end;

        -- a slide still running would carry on to where the tab was before the bar scrolled
        for _, Tween in next, OutlineTweens do
            Tween:Cancel();
        end;
        table.clear(OutlineTweens);

        -- AbsolutePosition is in screen px; the window's UIScale (menu scale and the open/close zoom) divides it out
        local ScaleObject = Outer:FindFirstChildOfClass('UIScale');
        local Scale = math.max(ScaleObject and ScaleObject.Scale or 1, 0.01);
        local Width = Tab.Button.Size.X.Offset;
        -- rounded: UDim offsets are whole numbers and would otherwise truncate (1-2px off at scale 1.3)
        local Left = math.floor((Tab.Button.AbsolutePosition.X - TabArea.AbsolutePosition.X) / Scale + 0.5);
        local BarWidth = math.floor(TabArea.AbsoluteSize.X / Scale + 0.5);
        -- In TabOutline columns the active tab's outline stands on Left and Left + Width. Scrolled out past the left
        -- end both are negative, past the right end both lie beyond the bar: the pieces either side of the tab are
        -- then empty or the whole bar (never a negative size), and the layer clips the tab's own outline.
        local LeftEnd = math.max(Left + 1, 0);
        local RightStart = math.min(Left + Width, BarWidth + 2);
        local Goals = {
            [ActiveClip] = { Position = UDim2.fromOffset(Left, 0); Size = UDim2.fromOffset(Width + 1, TabHalf) };
            [ActiveBox] = { Size = UDim2.fromOffset(Width - 1, TAB_HEIGHT + TabReach) };
            [LeftClip] = { Size = UDim2.fromOffset(LeftEnd, TabLower) };
            [LeftBox] = { Size = UDim2.fromOffset(math.max(Left + TabReach, 0), TabLower - 1 + TabReach) };
            [RightClip] = { Position = UDim2.fromOffset(RightStart, TabHalf); Size = UDim2.new(1, -RightStart, 0, TabLower) };
        };

        if ActiveLower then
            -- as wide as the tab plus the corners turning away from it, kept off the content box's side borders
            local From, To = math.max(Left - TAB_RADIUS, 1), math.min(Left + Width + TAB_RADIUS, BarWidth);
            Goals[ActiveLower] = { Position = UDim2.fromOffset(From, TabHalf); Size = UDim2.fromOffset(math.max(To - From + 1, 0), TabLower) };
        end;

        if UpperLeftClip then
            Goals[UpperLeftClip] = { Size = UDim2.fromOffset(LeftEnd, TabHalf) };
            Goals[UpperRightClip] = { Position = UDim2.fromOffset(RightStart, 0); Size = UDim2.new(1, -RightStart, 0, TabHalf) };
        end;

        for Object, Goal in next, Goals do
            if Instant then
                Library:Create(Object, Goal);
            else
                table.insert(OutlineTweens, Library:Animate(Object, 0.2, Goal));
            end;
        end;

        -- the outline already stands on the active tab's two edges
        for _, Other in next, Window.Tabs do
            Other.Divider.Visible = not (Other == Tab or Other.Index + 1 == Tab.Index);
        end;
        Tab.Divider.Visible = false; -- the first tab is shown before it is in Window.Tabs
    end;

    -- tabs added or reordered move the active button: put the bar back under it
    TabListLayout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
        Window:MoveUnderline(true);
    end);

    -- and so does scrolling the strip
    TabArea:GetPropertyChangedSignal('CanvasPosition'):Connect(function()
        Window:MoveUnderline(true);
    end);

    -- Scrolls the strip just far enough to show all of Tab (one clicked while half off an end, or opened from code).
    function Window:RevealTab(Tab)
        local View, Canvas = TabArea.AbsoluteSize.X, TabArea.CanvasPosition.X;
        local Left = Tab.Button.AbsolutePosition.X - TabArea.AbsolutePosition.X + Canvas; -- in the canvas, screen px
        local Right = Left + Tab.Button.AbsoluteSize.X;

        if View <= 0 then
            return; -- not laid out yet
        elseif Left < Canvas then
            Canvas = Left;
        elseif Right > Canvas + View then
            Canvas = Right - View;
        end;

        TabArea.CanvasPosition = Vector2.new(math.max(Canvas, 0), 0);
    end;

    local TabContainer = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderColor3 = Library.OutlineColor;
        Position = UDim2.new(0, PANEL_PAD, 0, 8 + TAB_HEIGHT + 1);
        Size = UDim2.new(1, -PANEL_PAD * 2, 1, -(8 + TAB_HEIGHT + 1 + PANEL_PAD));
        ClipsDescendants = true; -- tab content slides in from the sides (Tab:ShowTab)
        ZIndex = 2;
        Parent = MainSectionInner;
    });
    

    Library:AddToRegistry(TabContainer, {
        BackgroundColor3 = 'MainColor';
        BorderColor3 = 'OutlineColor';
    });

    -- Frosted glass: only Inner tints the window; the layers stacked on it go clear so the blur shows through.
    if Glass then
        Outer.BackgroundTransparency = 1;
        Inner.BackgroundTransparency = Library.GlassTransparency;
        MainSectionOuter.BackgroundTransparency = 1;
        MainSectionInner.BackgroundTransparency = 1;
        TabContainer.BackgroundTransparency = 1;

        -- The content box's outline: its own border is as clear as its background. Left, right and bottom only; the
        -- top edge is the tab bar's bottom line (TabOutline), open under the active tab.
        local Top = TabContainer.Position.Y.Offset - 1;
        local Edge = PANEL_PAD - 1; -- the outline stands one px outside the box
        Line({ Position = UDim2.new(0, Edge, 0, Top); Size = UDim2.new(0, 1, 1, -Top - Edge); ZIndex = 3; Parent = MainSectionInner });
        -- Both stop GRIP_GAP px short of the bottom right corner: the resize grip's dots sit there, and with the box
        -- this close to the window's edge its outline ran through them.
        local GRIP_GAP = 6;
        Line({ Position = UDim2.new(1, -PANEL_PAD, 0, Top); Size = UDim2.new(0, 1, 1, -Top - Edge - GRIP_GAP); ZIndex = 3; Parent = MainSectionInner });
        Line({ Position = UDim2.new(0, Edge, 1, -PANEL_PAD); Size = UDim2.new(1, -Edge * 2 - GRIP_GAP, 0, 1); ZIndex = 3; Parent = MainSectionInner });

        Library:AddGlass(Outer, function()
            return Outer.Visible, Library.Toggled;
        end);
    end;

    function Window:SetWindowTitle(Title)
        WindowLabel.Text = Title;
        FitTitle();
    end;

    -- Removes this window, its sections and their floating panels. For scripts that rebuild their window on the
    -- same library (a re-run with the library kept), which otherwise stacks a new window on the old one.
    function Window:Destroy()
        for Index = #Library.Sections, 1, -1 do
            local Section = Library.Sections[Index];

            if Section.Tab.WindowOuter == Outer then
                if Section.Gui then
                    Section.Gui:Destroy();
                end;

                table.remove(Library.Sections, Index);
            end;
        end;

        -- the first window's scale / glow / border objects are what SetScale, SetGlow and the accent update; let the
        -- next window take those slots
        for _, Key in next, { 'MainWindow', 'WindowScale', 'WindowGlow', 'WindowBorderGradient' } do
            local Object = Library[Key];

            if Object and (Object == Outer or Object:IsDescendantOf(Outer)) then
                Library[Key] = nil;
            end;
        end;

        Outer:Destroy();
    end;

    function Window:AddTab(Name)
        Window.TabCount = (Window.TabCount or 0) + 1;

        local Tab = {
            Groupboxes = {};
            Tabboxes = {};
            Index = Window.TabCount; -- left-to-right position, for the slide direction
        };

        local TabButtonWidth = Library:GetTextBounds(Name, Library.Font, 16);

        -- VS Code style tab: a box with a divider on its right and the name dimmed while inactive. The active one takes
        -- the content's shade, loses its bottom line and gets the rounded outline (Window:MoveUnderline).
        local TabButton = Library:Create('Frame', {
            BackgroundTransparency = 1; -- the bar's shades are on the outline pieces (TabOutline), under the name
            BorderSizePixel = 0;
            Size = UDim2.new(0, TabButtonWidth + TAB_PADDING * 2, 1, 0);
            ZIndex = 1;
            Parent = TabArea;
        });

        -- as between VS Code's inactive tabs: fainter than the outline, half the tab's height, centred;
        -- Window:MoveUnderline hides the ones the outline replaces
        Tab.Divider = Line({ AnchorPoint = Vector2.new(1, 0.5); BackgroundTransparency = 0.5; Position = UDim2.new(1, 0, 0.5, 0); Size = UDim2.new(0, 1, 0.5, 0); ZIndex = 5; Parent = TabButton });

        Tab.Button = TabButton; -- Window:MoveUnderline puts the outline around it
        Tab.NaturalWidth = TabButton.Size.X.Offset;
        table.insert(AllTabs, Tab);
        FitTabs();

        local TabButtonLabel = Library:CreateLabel({
            Position = UDim2.new(0, 0, 0, 0);
            Size = UDim2.new(1, 0, 1, 0);
            Text = Name;
            TextTransparency = 0.45;
            ZIndex = 6; -- over the bar's shades and outline
            Parent = TabButton;
        });

        local TabLabelStroke = TabButtonLabel:FindFirstChildOfClass('UIStroke');
        if TabLabelStroke then
            TabLabelStroke.Transparency = 0.45;
        end;

        local TabTweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
        local TabActive = false;

        local function FadeTabLabel(Transparency)
            Library:RememberTransparency(TabButtonLabel, 'TextTransparency', Transparency);
            Library:CreateTween(TabButtonLabel, TabTweenInfo, { TextTransparency = Transparency }):Play();
            if TabLabelStroke then
                Library:RememberTransparency(TabLabelStroke, 'Transparency', Transparency);
                Library:CreateTween(TabLabelStroke, TabTweenInfo, { Transparency = Transparency }):Play();
            end;
        end;

        TabButton.MouseEnter:Connect(function()
            if not TabActive then
                FadeTabLabel(0.2);
            end;
        end);

        TabButton.MouseLeave:Connect(function()
            if not TabActive then
                FadeTabLabel(0.45);
            end;
        end);

        local TabFrame = Library:Create('Frame', {
            Name = 'TabFrame',
            BackgroundTransparency = 1;
            Position = UDim2.new(0, 0, 0, 0);
            Size = UDim2.new(1, 0, 1, 0);
            Visible = false;
            ZIndex = 2;
            Parent = TabContainer;
        });

        local LeftSide = Library:Create('ScrollingFrame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Position = UDim2.new(0, COLUMN_PAD, 0, COLUMN_PAD);
            Size = UDim2.new(0.5, -(COLUMN_PAD + 4), 1, -COLUMN_PAD * 2);
            CanvasSize = UDim2.new(0, 0, 0, 0);
            BottomImage = '';
            TopImage = '';
            ScrollBarThickness = 0;
            ZIndex = 2;
            Parent = TabFrame;
        });

        local RightSide = Library:Create('ScrollingFrame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Position = UDim2.new(0.5, 4, 0, COLUMN_PAD);
            Size = UDim2.new(0.5, -(COLUMN_PAD + 4), 1, -COLUMN_PAD * 2);
            CanvasSize = UDim2.new(0, 0, 0, 0);
            BottomImage = '';
            TopImage = '';
            ScrollBarThickness = 0;
            ZIndex = 2;
            Parent = TabFrame;
        });

        Library:Create('UIListLayout', {
            Padding = UDim.new(0, 8);
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            HorizontalAlignment = Enum.HorizontalAlignment.Center;
            Parent = LeftSide;
        });

        Library:Create('UIListLayout', {
            Padding = UDim.new(0, 8);
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            HorizontalAlignment = Enum.HorizontalAlignment.Center;
            Parent = RightSide;
        });

        for _, Side in next, { LeftSide, RightSide } do
            local Layout = Side:WaitForChild('UIListLayout');
            local function UpdateCanvas()
                -- Layout bounds are screen pixels; CanvasSize offsets are unscaled UI pixels.
                local ScaleObject = Outer:FindFirstChildOfClass('UIScale');
                local Scale = math.max(ScaleObject and ScaleObject.Scale or Library.UIScale or 1, 0.01);
                Side.CanvasSize = UDim2.fromOffset(0, math.ceil(Layout.AbsoluteContentSize.Y / Scale) + 8);
            end;
            Layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(UpdateCanvas);
            Side:GetPropertyChangedSignal('AbsoluteSize'):Connect(UpdateCanvas);
            task.defer(UpdateCanvas);
        end;

        -- what a section needs to find its way back (see Library:RegisterSection)
        local SectionTab = { Name = Name, LeftSide = LeftSide, RightSide = RightSide, Frame = TabFrame, WindowOuter = Outer };
        local SectionCount, TabboxCount = 0, 0;

        local function NextSectionOrder()
            SectionCount = SectionCount + 1;
            return SectionCount * 10;
        end;

        -- Switching tabs (Library.Animations): the new content fades in over a short slide from the side of the tab that
        -- was clicked (a tab to the right comes in from the right); the old content goes at once. It used to slide out
        -- 40 px the other way under the new one coming in: two pages of text crossing each other for a fifth of a
        -- second, which is restless to look at. Tab.FadeRest holds a tab's real transparencies for as long as its
        -- fade runs. A fade that starts without them takes whatever the content shows at that moment for real, and a
        -- tab caught half faded (clicked through quickly, or while the menu itself fades) stayed faded for good.
        local SLIDE_PX, SLIDE_TIME = 12, 0.2;

        -- Ends this tab's slide at once, its content back at its real transparencies (Library:Toggle reads them).
        function Tab:EndSlide()
            if Tab.FadeRest then
                Tab.FadeToken = {};
                Library:RestoreTree(Tab.FadeRest);
                Tab.FadeRest = nil;
                TabFrame.Visible = TabActive;
            end;
        end;

        function Tab:ShowTab()
            local Previous = Window.ActiveTab;
            local Direction = (Previous and Previous ~= Tab) and (Tab.Index > Previous.Index and 1 or -1) or 0;

            -- only a window at rest slides: hidden, or mid open / close fade, its content is not at its real values
            if not Outer.Visible or Window.Fading then
                Direction = 0;
            end;

            for _, Other in next, Window.Tabs do
                if Other ~= Tab then
                    Other:HideTab();
                end;
            end;

            Window:RevealTab(Tab); -- before it is the active one: the outline then slides to it from where the old tab now is
            Window.ActiveTab = Tab;
            TabActive = true;
            FadeTabLabel(0);
            Window:MoveUnderline(Previous == nil); -- slides from the previous tab; the first one just appears

            local Token = {};
            Tab.FadeToken = Token; -- cancels this tab's own unfinished hide
            TabFrame.Visible = true;

            if Library.Animations and Direction ~= 0 then
                TabFrame.Position = UDim2.fromOffset(Direction * SLIDE_PX, 0);
                -- Only what is on screen: fading the whole page (2048 instances on the largest tab of the Anime
                -- Adventures menu) took 25 ms and made a 47 ms frame at the start of every switch, against 11 ms
                -- for a switch without animation (live, 2026-11-22). The rest keeps its real values, unseen.
                Tab.FadeRest = Library:FadeTree(TabFrame, true, SLIDE_TIME, Tab.FadeRest, nil, (Library:ShownTree(TabFrame)));
                Library:Animate(TabFrame, SLIDE_TIME, { Position = UDim2.new() });

                task.delay(SLIDE_TIME + 0.02, function()
                    if Tab.FadeToken == Token then
                        Tab.FadeRest = nil; -- faded in: from here the content's own values are the real ones
                    end;
                end);
            else
                Library:RestoreTree(Tab.FadeRest);
                Tab.FadeRest = nil;
                TabFrame.Position = UDim2.new();
            end;
        end;

        function Tab:HideTab()
            TabActive = false;
            FadeTabLabel(0.45);
            -- A fade-in still running on it carries on unseen to its real values (Tab.FadeRest, ShowTab).
            TabFrame.Visible = false;
        end;

        function Tab:SetLayoutOrder(Position)
            TabButton.LayoutOrder = Position;
            TabListLayout:ApplyLayout();
        end;

        function Tab:AddGroupbox(Info)
            local Groupbox = {};

            local BoxOuter = Library:Create('Frame', {
                BackgroundColor3 = Library.BackgroundColor;
                BorderColor3 = Library.OutlineColor;
                BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.new(1, 0, 0, 507 + 2);
                LayoutOrder = NextSectionOrder();
                ZIndex = 2;
                Parent = Info.Side == 1 and LeftSide or RightSide;
            });

            Library:AddToRegistry(BoxOuter, {
                BackgroundColor3 = 'BackgroundColor';
                BorderColor3 = 'OutlineColor';
            });

            local BoxInner = Library:Create('Frame', {
                BackgroundColor3 = Library.BackgroundColor;
                BorderColor3 = Color3.new(0, 0, 0);
                -- BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.new(1, -2, 1, -2);
                Position = UDim2.new(0, 1, 0, 1);
                ZIndex = 4;
                Parent = BoxOuter;
            });

            Library:AddToRegistry(BoxInner, {
                BackgroundColor3 = 'BackgroundColor';
            });

            local Highlight = Library:Create('Frame', {
                BackgroundColor3 = Library.AccentColor;
                BorderSizePixel = 0;
                Size = UDim2.new(1, 0, 0, 2);
                ZIndex = 5;
                Parent = BoxInner;
            });

            Library:AddToRegistry(Highlight, {
                BackgroundColor3 = 'AccentColor';
            });

            -- On glass the box's own border does not show (Library:RegisterSection): its outline is these lines, as
            -- around a tabbox. The accent line above is the top edge.
            if Glass then
                Line({ Size = UDim2.new(0, 1, 1, 0); ZIndex = 5; Parent = BoxInner });
                Line({ AnchorPoint = Vector2.new(1, 0); Position = UDim2.new(1, 0, 0, 0); Size = UDim2.new(0, 1, 1, 0); ZIndex = 5; Parent = BoxInner });
                Line({ AnchorPoint = Vector2.new(0, 1); Position = UDim2.new(0, 0, 1, 0); Size = UDim2.new(1, 0, 0, 1); ZIndex = 5; Parent = BoxInner });
            end;

            local GroupboxLabel = Library:CreateLabel({
                Size = UDim2.new(1, 0, 0, 18);
                Position = UDim2.new(0, 4, 0, 2);
                TextSize = 14;
                Text = Info.Name;
                TextXAlignment = Enum.TextXAlignment.Center;
                ZIndex = 5;
                Parent = BoxInner;
            });

            local Container = Library:Create('Frame', {
                BackgroundTransparency = 1;
                Position = UDim2.new(0, 8, 0, 20); -- 8 px clear of the side lines; the controls leave 4 on the right themselves
                Size = UDim2.new(1, -12, 1, -20);
                ZIndex = 1;
                Parent = BoxInner;
            });

            Library:Create('UIListLayout', {
                FillDirection = Enum.FillDirection.Vertical;
                SortOrder = Enum.SortOrder.LayoutOrder;
                Parent = Container;
            });

            local Section = Library:RegisterSection({
                Key = Name .. '/' .. tostring(Info.Name);
                Outer = BoxOuter;
                Inner = BoxInner;
                Tab = SectionTab;
                Side = Info.Side == 1 and 1 or 2;
                HeaderHeight = 20;
            });

            Section.ApplyFold = function()
                Container.Visible = not Section.Folded;
                Groupbox:Resize();
            end;
            Section.Content = function()
                return Container;
            end;
            Section.FoldedHeight = 20 + 2 + 2;
            -- floating: keep the centred title clear of the pin + fold icons on the right (same gap on the left)
            GroupboxLabel.TextTruncate = Enum.TextTruncate.AtEnd;
            Section.LayoutHeader = function()
                GroupboxLabel.Position = Section.Floating and UDim2.new(0, 34, 0, 2) or UDim2.new(0, 4, 0, 2);
                GroupboxLabel.Size = Section.Floating and UDim2.new(1, -68, 0, 18) or UDim2.new(1, 0, 0, 18);
            end;

            function Groupbox:Resize()
                if Section.Animating then
                    return; -- SetSectionFolded is easing the height and resizes once it is done
                end;

                if Section.Folded then
                    BoxOuter.Size = UDim2.new(1, 0, 0, 20 + 2 + 2);
                    return;
                end;

                local Size = 0;

                for _, Element in next, Groupbox.Container:GetChildren() do
                    if (not Element:IsA('UIListLayout')) and Element.Visible then
                        Size = Size + Element.Size.Y.Offset;
                    end;
                end;

                BoxOuter.Size = UDim2.new(1, 0, 0, 20 + Size + 2 + 2);
            end;

            Groupbox.Container = Container;
            setmetatable(Groupbox, BaseGroupbox);

            Groupbox:AddBlank(3);
            Groupbox:Resize();

            Tab.Groupboxes[Info.Name] = Groupbox;

            return Groupbox;
        end;

        function Tab:AddLeftGroupbox(Name)
            return Tab:AddGroupbox({ Side = 1; Name = Name; });
        end;

        function Tab:AddRightGroupbox(Name)
            return Tab:AddGroupbox({ Side = 2; Name = Name; });
        end;

        function Tab:AddTabbox(Info)
            local Tabbox = {
                Tabs = {};
            };

            local BoxOuter = Library:Create('Frame', {
                BackgroundColor3 = Library.BackgroundColor;
                BorderColor3 = Library.OutlineColor;
                BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.new(1, 0, 0, 0);
                LayoutOrder = NextSectionOrder();
                ZIndex = 2;
                Parent = Info.Side == 1 and LeftSide or RightSide;
            });

            Library:AddToRegistry(BoxOuter, {
                BackgroundColor3 = 'BackgroundColor';
                BorderColor3 = 'OutlineColor';
            });

            local BoxInner = Library:Create('Frame', {
                BackgroundColor3 = Library.BackgroundColor;
                BorderColor3 = Color3.new(0, 0, 0);
                -- BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.new(1, -2, 1, -2);
                Position = UDim2.new(0, 1, 0, 1);
                ZIndex = 4;
                Parent = BoxOuter;
            });

            Library:AddToRegistry(BoxInner, {
                BackgroundColor3 = 'BackgroundColor';
            });

            -- Header, as VS Code's editor tabs: the tab strip is the box's top 23 px. The active tab carries the box's
            -- 2 px accent line (only as wide as that tab), has the content's color and is open at the bottom; the rest
            -- of the strip is shaded, with a line under it and one after every tab. Then 3 px and the content.
            local TabStripTop = 0;
            local TabStripHeight = 23;
            local DividerY = TabStripTop + TabStripHeight;
            local ContentTop = DividerY + 4;

            local TabboxButtons = Library:Create('Frame', {
                BackgroundTransparency = 1;
                Position = UDim2.new(0, 0, 0, TabStripTop);
                Size = UDim2.new(1, -18, 0, TabStripHeight); -- room for the fold button (and the pin: LayoutHeader)
                ZIndex = 5;
                Parent = BoxInner;
            });

            TabboxCount = TabboxCount + 1;

            local Section = Library:RegisterSection({
                Key = Name .. '/' .. (Info.Name or ('#tabbox' .. TabboxCount));
                Outer = BoxOuter;
                Inner = BoxInner;
                Tab = SectionTab;
                Side = Info.Side == 1 and 1 or 2;
                HeaderHeight = ContentTop;
            });

            Section.ApplyFold = function()
                for _, SubTab in next, Tabbox.Tabs do
                    SubTab.Container.Visible = (not Section.Folded) and Tabbox.ActiveTab == SubTab;
                end;

                if Tabbox.ActiveTab then
                    Tabbox.ActiveTab:Resize();
                end;
            end;
            Section.Content = function()
                return Tabbox.ActiveTab and Tabbox.ActiveTab.Container;
            end;
            Section.FoldedHeight = DividerY + 1 + 4; -- ends on the line under the strip (BoxInner is 4 px shorter than the box)
            -- the strip leaves room for the fold button, and for the pin as well while floating
            local function HeaderReserve()
                return Section.Floating and 34 or 18;
            end;
            Section.LayoutHeader = function()
                TabboxButtons.Size = UDim2.new(1, -HeaderReserve(), 0, TabStripHeight);
                Tabbox:MoveUnderline(true);
            end;

            Library:Create('UIListLayout', {
                FillDirection = Enum.FillDirection.Horizontal;
                HorizontalAlignment = Enum.HorizontalAlignment.Left;
                SortOrder = Enum.SortOrder.LayoutOrder;
                Parent = TabboxButtons;
            });

            -- Every line of the box is one continuous outline (in the outline color; only the active tab's top line
            -- is accent): around the whole box, with the dividers between the tabs and the line under the strip
            -- running into it. On glass the box's own border is as clear as its background, so it is drawn as lines
            -- here; a solid box's border already is that outline.
            if Glass then
                Line({ Size = UDim2.new(1, 0, 0, 1); ZIndex = 5; Parent = BoxInner });
                Line({ Size = UDim2.new(0, 1, 1, 0); ZIndex = 5; Parent = BoxInner });
                Line({ AnchorPoint = Vector2.new(1, 0); Position = UDim2.new(1, 0, 0, 0); Size = UDim2.new(0, 1, 1, 0); ZIndex = 5; Parent = BoxInner });
                Line({ AnchorPoint = Vector2.new(0, 1); Position = UDim2.new(0, 0, 1, 0); Size = UDim2.new(1, 0, 0, 1); ZIndex = 5; Parent = BoxInner });
            end;

            -- The line under the strip, in two pieces that leave the active tab open at the bottom.
            local DividerLeft = Line({ Position = UDim2.fromOffset(0, DividerY); Size = UDim2.fromOffset(0, 1); ZIndex = 5; Parent = BoxInner });
            local DividerRight = Line({ Position = UDim2.fromOffset(0, DividerY); Size = UDim2.new(1, 0, 0, 1); ZIndex = 5; Parent = BoxInner });

            -- The active tab has the color of the content under it, as in VS Code: it is the rest of the strip that is
            -- shaded, a little darker than whatever the box shows (so it works on glass and in any theme). One piece
            -- left and one right of the active tab, sliding with its accent line. They live in BoxInner, not the
            -- strip, which a UIListLayout arranges. (A lighter fill on the active tab itself made it a different
            -- color from its own content.)
            local function StripShade()
                return Library:Create('Frame', {
                    BackgroundColor3 = Color3.new(0, 0, 0);
                    BackgroundTransparency = 0.75;
                    BorderSizePixel = 0;
                    ZIndex = 4;
                    Parent = BoxInner;
                });
            end;

            local ShadeLeft, ShadeRight = StripShade(), StripShade();

            local TabboxUnderline = Library:Create('Frame', {
                BackgroundColor3 = Library.AccentColor;
                BorderSizePixel = 0;
                Size = UDim2.new(0, 0, 0, 2);
                ZIndex = 10;
                Parent = BoxInner;
            });

            Library:AddToRegistry(TabboxUnderline, {
                BackgroundColor3 = 'AccentColor';
            });

            local TabboxTabCount = 0;
            local TabList = {};  -- in strip order
            local TAB_PAD = 16;  -- a tab is its name and this much room around it

            -- Tabs are left aligned, each as wide as its name. Names that do not all fit share the strip in proportion
            -- to their length, and truncate.
            function Tabbox:FitTabs()
                local Available = TabboxButtons.AbsoluteSize.X / math.max(Library.UIScale or 1, 0.01);
                local Total = 0;

                for _, Tab in next, TabList do
                    Total = Total + Tab.TextWidth + TAB_PAD;
                end;

                local Shrink = (Available > 0 and Total > Available) and Available / Total or 1;
                local Left = 0;

                for _, Tab in next, TabList do
                    Tab.Width = math.floor((Tab.TextWidth + TAB_PAD) * Shrink);
                    Tab.Left = Left;
                    Left = Left + Tab.Width;
                    Tab.Button.Size = UDim2.new(0, Tab.Width, 1, 0);
                end;
            end;

            TabboxButtons:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()
                Tabbox:MoveUnderline(true); -- the box was resized: the tabs may fit now, or no longer
            end);

            -- Puts the accent line and the gap in the bottom line on the active tab, and the shade either side of it.
            function Tabbox:MoveUnderline(Instant)
                local Active = Tabbox.ActiveTab;
                if not Active then
                    return;
                end;

                Tabbox:FitTabs();

                -- a tab's last column is its divider: the bottom line starts again there
                local Left, Width = Active.Left, Active.Width;
                local Goals = {
                    [TabboxUnderline] = { Position = UDim2.fromOffset(Left, 0); Size = UDim2.fromOffset(Width, 2) };
                    [ShadeLeft] = { Size = UDim2.fromOffset(Left, DividerY) };
                    [ShadeRight] = { Position = UDim2.fromOffset(Left + Width, 0); Size = UDim2.new(1, -(Left + Width), 0, DividerY) };
                    [DividerLeft] = { Size = UDim2.fromOffset(Left, 1) };
                    [DividerRight] = { Position = UDim2.fromOffset(Left + Width - 1, DividerY); Size = UDim2.new(1, -(Left + Width - 1), 0, 1) };
                };

                -- no line after the last tab, unless it is the active one's edge: with the strip full, it boxed the
                -- fold button in like one more tab
                for Index, Tab in next, TabList do
                    Tab.Divider.Visible = Index < #TabList or Tab == Active;
                end;

                for Object, Goal in next, Goals do
                    if Instant then
                        Library:Create(Object, Goal);
                    else
                        Library:Animate(Object, 0.2, Goal);
                    end;
                end;
            end;

            function Tabbox:AddTab(Name)
                local Tab = {};
                local TabInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
                local Active = false;

                -- The name (dimmed while inactive) and a divider on the tab's right edge; the active tab's accent
                -- line and shade are Tabbox:MoveUnderline's.
                local Button = Library:Create('Frame', {
                    BackgroundTransparency = 1;
                    BorderSizePixel = 0;
                    Size = UDim2.new(0, 0, 1, 0); -- Tabbox:FitTabs
                    ZIndex = 6;
                    Parent = TabboxButtons;
                });

                Tab.Divider = Line({ AnchorPoint = Vector2.new(1, 0); Position = UDim2.new(1, 0, 0, 0); Size = UDim2.new(0, 1, 1, 0); ZIndex = 6; Parent = Button });

                local ButtonLabel = Library:CreateLabel({
                    Position = UDim2.fromOffset(0, 2); -- under the accent line
                    Size = UDim2.new(1, -1, 1, -2);
                    TextSize = 14;
                    Text = Name;
                    TextTransparency = 0.45;
                    TextTruncate = Enum.TextTruncate.AtEnd;
                    TextXAlignment = Enum.TextXAlignment.Center;
                    ZIndex = 7;
                    Parent = Button;
                });

                local ButtonLabelStroke = ButtonLabel:FindFirstChildOfClass('UIStroke');
                if ButtonLabelStroke then
                    ButtonLabelStroke.Transparency = 0.45;
                end;

                TabboxTabCount = TabboxTabCount + 1;
                Tab.Index = TabboxTabCount;
                Tab.Button = Button;
                Tab.TextWidth = Library:GetTextBounds(Name, Library.Font, 14);
                Button.LayoutOrder = TabboxTabCount; -- the strip order must match TabList for the accent line's position
                table.insert(TabList, Tab);

                local function FadeLabel(Transparency)
                    Library:RememberTransparency(ButtonLabel, 'TextTransparency', Transparency);
                    Library:CreateTween(ButtonLabel, TabInfo, { TextTransparency = Transparency }):Play();
                    if ButtonLabelStroke then
                        Library:RememberTransparency(ButtonLabelStroke, 'Transparency', Transparency);
                        Library:CreateTween(ButtonLabelStroke, TabInfo, { Transparency = Transparency }):Play();
                    end;
                end;

                Button.MouseEnter:Connect(function()
                    if not Active then
                        FadeLabel(0.2);
                    end;
                end);

                Button.MouseLeave:Connect(function()
                    if not Active then
                        FadeLabel(0.45);
                    end;
                end);

                local Container = Library:Create('Frame', {
                    BackgroundTransparency = 1;
                    Position = UDim2.new(0, 8, 0, ContentTop);
                    Size = UDim2.new(1, -12, 1, -ContentTop);
                    ZIndex = 1;
                    Visible = false;
                    Parent = BoxInner;
                });

                Library:Create('UIListLayout', {
                    FillDirection = Enum.FillDirection.Vertical;
                    SortOrder = Enum.SortOrder.LayoutOrder;
                    Parent = Container;
                });

                function Tab:Show()
                    for _, Tab in next, Tabbox.Tabs do
                        Tab:Hide();
                    end;

                    local First = Tabbox.ActiveTab == nil;
                    local Switching = not First and Tabbox.ActiveTab ~= Tab;
                    local From = BoxOuter.Size;
                    Active = true;
                    Tabbox.ActiveTab = Tab;
                    Container.Visible = not Section.Folded;
                    FadeLabel(0);
                    Tabbox:MoveUnderline(First); -- slides from the previous tab; the first one just appears

                    if Section.Animating then
                        if not Section.Switching then
                            return; -- mid fold: SetSectionFolded resizes once it ends
                        end;
                        Section.Animating = nil; -- mid switch: this one takes over from the current height
                    end;

                    Tab:Resize();

                    -- Switching sub-tabs (Library.Animations): the box eases from the old tab's height to this one's
                    -- (expanding or folding up) while the new rows fade in. Shares FoldToken / Animating with folding,
                    -- so a fold or another switch mid-way takes over cleanly.
                    if not (Switching and Library.Animations and Container.Visible) then
                        return;
                    end;

                    local To = BoxOuter.Size;
                    local Token = {};
                    Section.FoldToken = Token;
                    Section.Animating = true;
                    Section.Switching = true;
                    BoxOuter.ClipsDescendants = true;
                    BoxOuter.Size = From;
                    Library:Animate(BoxOuter, FOLD_TIME, { Size = To });
                    -- a tab shown again while its last fade-in is still running has half-faded rows: reuse the real
                    -- values saved then, or FadeTree would take the half-faded ones as real and leave the rows dim
                    local Now = os.clock();
                    if not (Tab.SwitchRest and Now < Tab.SwitchRestUntil) then
                        Tab.SwitchRest = nil;
                    end;
                    Tab.SwitchRest = Library:FadeTree(Container, true, FOLD_TIME, Tab.SwitchRest);
                    Tab.SwitchRestUntil = Now + FOLD_TIME + 0.05;

                    task.delay(FOLD_TIME + 0.02, function()
                        if Section.FoldToken ~= Token then
                            return;
                        end;

                        Section.Animating = nil;
                        Section.Switching = nil;
                        BoxOuter.ClipsDescendants = false;
                        Tabbox.ActiveTab:Resize(); -- picks up anything that changed size meanwhile
                    end);
                end;

                function Tab:Hide()
                    Active = false;
                    Container.Visible = false;
                    FadeLabel(0.45);
                end;

                function Tab:Resize()
                    if Section.Animating then
                        return; -- SetSectionFolded is easing the height and resizes once it is done
                    end;

                    if Section.Folded then
                        BoxOuter.Size = UDim2.new(1, 0, 0, Section.FoldedHeight);
                        return;
                    end;

                    if (not Container.Visible) then
                        return;
                    end;

                    local Size = 0;

                    for _, Element in next, Tab.Container:GetChildren() do
                        if (not Element:IsA('UIListLayout')) and Element.Visible then
                            Size = Size + Element.Size.Y.Offset;
                        end;
                    end;

                    BoxOuter.Size = UDim2.new(1, 0, 0, ContentTop + Size + 2 + 2);
                end;

                Button.InputBegan:Connect(function(Input)
                    if IsTap(Input) and not Library:MouseIsOverOpenedFrame() then
                        Tab:Show();
                        Tab:Resize();
                    end;
                end);

                Tab.Container = Container;
                Tabbox.Tabs[Name] = Tab;

                setmetatable(Tab, BaseGroupbox);

                Tab:AddBlank(3);
                Tab:Resize();

                -- Show first tab (number is 2 cus of the UIListLayout that also sits in that instance)
                if #TabboxButtons:GetChildren() == 2 then
                    Tab:Show();
                end;

                Tabbox:MoveUnderline(true); -- sizes the new tab (and the others, should they no longer all fit)

                return Tab;
            end;

            Tab.Tabboxes[Info.Name or ''] = Tabbox;

            return Tabbox;
        end;

        function Tab:AddLeftTabbox(Name)
            return Tab:AddTabbox({ Name = Name, Side = 1; });
        end;

        function Tab:AddRightTabbox(Name)
            return Tab:AddTabbox({ Name = Name, Side = 2; });
        end;

        TabButton.InputBegan:Connect(function(Input)
            if IsTap(Input) then
                Tab:ShowTab();
            end;
        end);

        -- This was the first tab added, so we show it by default.
        if #TabContainer:GetChildren() == 1 then
            Tab:ShowTab();
        end;

        Window.Tabs[Name] = Tab;
        return Tab;
    end;

    local ModalElement = Library:Create('TextButton', {
        BackgroundTransparency = 1;
        Size = UDim2.new(0, 0, 0, 0);
        Visible = true;
        Text = '';
        Modal = false;
        Parent = ScreenGui;
    });

    local TransparencyCache = {};
    local ActiveTweens = {};
    local Toggled = false;
    local ToggleGeneration = 0;
    local CursorRunning = false;

    function Library:RememberTransparency(Instance, Property, Value)
        local Cache = TransparencyCache[Instance];

        if Cache then
            Cache[Property] = Value;
        end;
    end;

    -- Frosted glass tint of a window built with GlassTransparency > 0 (0 = solid, blur off). Also patches the fade's
    -- cached value, which is what the next show restores.
    function Library:SetGlassTransparency(Value)
        Library.GlassTransparency = Value;
        Inner.BackgroundTransparency = Value;

        if TransparencyCache[Inner] then
            TransparencyCache[Inner].BackgroundTransparency = Value;
        end;

        -- Still fading in: that tween would carry on to the old value, and the menu kept it from then on. A saved
        -- opacity arriving at script start, while the menu opens, was lost this way. A new tween replaces it.
        if Window.Fading and Library.Toggled then
            Library:Animate(Inner, 0, { BackgroundTransparency = Value });
        end;

        for _, Section in next, Library.Sections do
            if Section.Inner and Section.Floating then
                Section.Inner.BackgroundTransparency = Value;
            end;
        end;
    end;

    -- Scales the whole window slightly while it fades, which reads a lot smoother than a flat alpha fade. 3%: at 5%
    -- the edges of a 550 px window travelled 14 px each, enough to read as a zoom instead of a fade.
    local MENU_ZOOM = 0.97;
    local WindowScale = Library:Create('UIScale', {
        Scale = Library.UIScale;
        Parent = Outer;
    });

    -- shared lists: this runs once per faded instance on every open / close
    local FADE_IMAGE = { 'ImageTransparency', 'BackgroundTransparency' };
    local FADE_TEXT = { 'TextTransparency', 'BackgroundTransparency' };
    local FADE_FRAME = { 'BackgroundTransparency' };
    local FADE_STROKE = { 'Transparency' };

    local function GetFadeProperties(Desc)
        if Desc:IsA('ImageLabel') then
            return FADE_IMAGE;
        elseif Desc:IsA('TextLabel') or Desc:IsA('TextBox') then
            return FADE_TEXT;
        elseif Desc:IsA('Frame') or Desc:IsA('ScrollingFrame') then
            return FADE_FRAME;
        elseif Desc:IsA('UIStroke') then
            return FADE_STROKE;
        end;
    end;

    -- The open / close fade eases each instance's own transparency (see Library:FadeTree for why), and doing that
    -- for the whole window froze the game: 7199 descendants in the Anime Adventures menu, 74 ms inside Toggle and a
    -- 125 ms frame on every open and close (live, 2026-11-21). Only what is on screen is faded: FadedShown collects
    -- the visible tree, leaving out the other tabs, folded content and rows scrolled out of a clipping frame.
    -- Everything else keeps its real transparencies throughout; nobody sees it.
    -- Faded: the instances a fade has touched and that may not be back at their real values yet.
    local Faded = {};

    local function FadedShown()
        return Library:ShownTree(Outer);
    end;

    local function RunCursor()
        if CursorRunning then
            return;
        end;

        CursorRunning = true;

        task.spawn(function()
            local State = InputService.MouseIconEnabled;

            local Cursor = Drawing.new('Triangle');
            Cursor.Thickness = 1;
            Cursor.Filled = true;
            Cursor.Transparency = 0;
            Cursor.Visible = true;

            local CursorOutline = Drawing.new('Triangle');
            CursorOutline.Thickness = 1;
            CursorOutline.Filled = false;
            CursorOutline.Color = Color3.new(0, 0, 0);
            CursorOutline.Transparency = 0;
            CursorOutline.Visible = true;

            local Alpha = 0;

            while ScreenGui.Parent do
                local Delta = RenderStepped:Wait();
                local Step = Delta / math.max(Library.MenuFadeTime or Config.MenuFadeTime, 0.01);

                Alpha = math.clamp(Alpha + (Toggled and Step or -Step), 0, 1);

                if (not Toggled) and Alpha <= 0 then
                    break;
                end;

                InputService.MouseIconEnabled = false;

                local mPos = InputService:GetMouseLocation();
                local Custom = Library.CursorAsset and Library.CursorImage;

                Cursor.Visible = not Custom;
                CursorOutline.Visible = not Custom;

                if Custom then
                    -- GUI space (no top-bar inset), 1px off the hotspot so the image is never the thing under the mouse
                    Custom.Visible = true;
                    Custom.ImageTransparency = 1 - Alpha;
                    local Hot = (Library.CursorHotspot or Vector2.zero) * (Library.CursorSize or 24);
                    Custom.Position = UDim2.fromOffset(Mouse.X + 1 - Hot.X, Mouse.Y + 1 - Hot.Y);
                end;

                Cursor.Color = Library.AccentColor;
                Cursor.Transparency = Alpha;
                CursorOutline.Transparency = Alpha;

                Cursor.PointA = Vector2.new(mPos.X, mPos.Y);
                Cursor.PointB = Vector2.new(mPos.X + 16, mPos.Y + 6);
                Cursor.PointC = Vector2.new(mPos.X + 6, mPos.Y + 16);

                CursorOutline.PointA = Cursor.PointA;
                CursorOutline.PointB = Cursor.PointB;
                CursorOutline.PointC = Cursor.PointC;
            end;

            InputService.MouseIconEnabled = State;

            if Library.CursorImage then
                Library.CursorImage.Visible = false;
            end;

            Cursor:Remove();
            CursorOutline:Remove();

            CursorRunning = false;
        end);
    end;

    -- Toggles the menu with an eased fade + scale. Pass true/false to force a state.
    -- Calling it again mid-animation reverses direction from wherever the fade currently is.
    function Library:Toggle(State)
        if Library:NeedsUIThread() then
            return Library:RunOnUIThread(Library.Toggle, Library, State);
        end;

        if State == nil then
            State = not Toggled;
        end;

        Toggled = (not not State);
        ModalElement.Modal = Toggled;
        Library.Toggled = Toggled;
        Library:UpdateFloatingSections();
        if Library.LayoutLoaded then Library:SaveLayout(); end;

        ToggleGeneration = ToggleGeneration + 1;
        local Generation = ToggleGeneration;

        local FadeTime = Library.Animations and (Library.MenuFadeTime or Config.MenuFadeTime) or 0;
        local Info = TweenInfo.new(
            FadeTime,
            Enum.EasingStyle.Quad,
            Toggled and Enum.EasingDirection.Out or Enum.EasingDirection.In
        );

        for _, Tween in next, ActiveTweens do
            Tween:Cancel();
        end;
        table.clear(ActiveTweens);

        local function Play(Instance, Goal)
            local Tween = Library:CreateTween(Instance, Info, Goal);
            table.insert(ActiveTweens, Tween);
            Tween:Play();
        end;

        local FromHidden = not Outer.Visible;

        -- a tab still sliding is mid fade: ended first, so the real transparencies are what is cached and faded from
        for _, Tab in next, Window.Tabs do
            Tab:EndSlide();
        end;

        Window.Fading = true; -- tabs switch without their slide meanwhile (Tab:ShowTab)

        if Toggled then
            Outer.Visible = true;

            if FromHidden then
                WindowScale.Scale = MENU_ZOOM * Library.UIScale;
            end;

            if not IsMobile then RunCursor(); end; -- no drawn cursor on touch-only screens
        else
            -- Close any dropdown / color picker popups so they don't linger after the window is gone.
            for Frame in next, Library.OpenedFrames do
                Frame.Visible = false;
                Library.OpenedFrames[Frame] = nil;
            end;
        end;

        Play(WindowScale, { Scale = (Toggled and 1 or MENU_ZOOM) * Library.UIScale });

        local Shown, InShown = FadedShown();

        -- left faded by an earlier toggle and off screen since (its tab was switched away while the menu was hidden):
        -- straight back to its real values
        for Desc in next, Faded do
            if not InShown[Desc] then
                Faded[Desc] = nil;

                for Prop, Value in next, TransparencyCache[Desc] do
                    Desc[Prop] = Value;
                end;
            end;
        end;

        for _, Desc in next, Shown do
            local Properties = GetFadeProperties(Desc);

            if not Properties then
                continue;
            end;

            local Cache = TransparencyCache[Desc];

            if (not Cache) then
                Cache = {};
                TransparencyCache[Desc] = Cache;
            end;

            -- not touched since the last finished fade-in: what it shows now is its real value (it may have changed
            -- while the menu was open: a toggle's dimmed label, the active tab's name)
            local Real = not Faded[Desc];
            local Goal;

            for _, Prop in next, Properties do
                if Real then
                    Cache[Prop] = Desc[Prop];
                end;

                local Value = Cache[Prop];

                if Value ~= 1 then
                    if Toggled and FromHidden then
                        Desc[Prop] = 1;
                    end;

                    Goal = Goal or {};
                    Goal[Prop] = Toggled and Value or 1;
                end;
            end;

            if Goal then
                Faded[Desc] = true;
                Play(Desc, Goal);
            end;
        end;

        task.delay(FadeTime, function()
            if Generation ~= ToggleGeneration then
                return;
            end;

            Outer.Visible = Toggled;
            Window.Fading = false;

            if Toggled then
                table.clear(Faded); -- faded in: everything shows its real values again
            end;
        end);
    end

    Library:GiveSignal(InputService.InputBegan:Connect(function(Input, Processed)
        if type(Library.ToggleKeybind) == 'table' and Library.ToggleKeybind.Type == 'KeyPicker' then
            if Input.UserInputType == Enum.UserInputType.Keyboard and Input.KeyCode.Name == Library.ToggleKeybind.Value then
                task.spawn(Library.Toggle)
            end
        elseif Input.KeyCode == Enum.KeyCode.RightControl or (Input.KeyCode == Enum.KeyCode.RightShift and (not Processed)) then
            task.spawn(Library.Toggle)
        end
    end))

    -- Touch screens have no menu key: a draggable on-screen button toggles the menu (a drag does not count as a tap).
    if InputService.TouchEnabled and not Library.MobileButton then
        local MobileButton = Library:Create('TextButton', {
            Name = 'MobileToggle';
            AutoButtonColor = false;
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.AccentColor;
            Position = UDim2.new(0, 12, 0.5, -18);
            Size = UDim2.fromOffset(60, 36);
            Font = Library.Font;
            Text = 'Menu';
            TextColor3 = Library.FontColor;
            TextSize = 14;
            ZIndex = 200;
            Parent = ScreenGui;
        });

        Library:AddToRegistry(MobileButton, {
            BackgroundColor3 = 'MainColor';
            BorderColor3 = 'AccentColor';
            TextColor3 = 'FontColor';
        }, true);

        Library:MakeDraggable(MobileButton, 36);

        local PressPosition;
        MobileButton.InputBegan:Connect(function(Input)
            if IsClick(Input) then PressPosition = MobileButton.Position; end;
        end);
        MobileButton.Activated:Connect(function()
            if PressPosition == MobileButton.Position then task.spawn(Library.Toggle); end;
        end);

        Library.MobileButton = MobileButton;
    end;

    if Config.AutoShow then task.spawn(Library.Toggle) end

    Window.Holder = Outer;
    Library.MainWindow = Library.MainWindow or Outer;
    Library.WindowScale = Library.WindowScale or WindowScale;

    return Window;
end;

local function OnPlayerChange()
    local PlayerList = GetPlayersString();

    for _, Value in next, Options do
        if Value.Type == 'Dropdown' and Value.SpecialType == 'Player' then
            Value:SetValues(PlayerList);
        end;
    end;
end;

Library:GiveSignal(Players.PlayerAdded:Connect(OnPlayerChange));
Library:GiveSignal(Players.PlayerRemoving:Connect(OnPlayerChange));

getgenv().Library = Library

-- Addons vendored from violin-suzutsuki/LinoriaLib (addons/ThemeManager.lua and addons/SaveManager.lua,
-- fetched 2026-10-10) so the client has no network dependency and cannot change underneath us.
-- Each is wrapped in a function so the original `return` at the end of the file still works.

local ThemeManager = (function()
local httpService = game:GetService('HttpService')
local ThemeManager = {} do
	ThemeManager.Folder = 'LinoriaLibSettings'
	-- if not isfolder(ThemeManager.Folder) then makefolder(ThemeManager.Folder) end

	ThemeManager.Library = nil
	ThemeManager.BuiltInThemes = {
		['Default'] 		= { 1, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"1c1c1c","AccentColor":"0055ff","BackgroundColor":"141414","OutlineColor":"323232"}') },
		['BBot'] 			= { 2, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"1e1e1e","AccentColor":"7e48a3","BackgroundColor":"232323","OutlineColor":"141414"}') },
		['Fatality']		= { 3, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"1e1842","AccentColor":"c50754","BackgroundColor":"191335","OutlineColor":"3c355d"}') },
		['Jester'] 			= { 4, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"242424","AccentColor":"db4467","BackgroundColor":"1c1c1c","OutlineColor":"373737"}') },
		['Mint'] 			= { 5, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"242424","AccentColor":"3db488","BackgroundColor":"1c1c1c","OutlineColor":"373737"}') },
		['Tokyo Night'] 	= { 6, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"191925","AccentColor":"6759b3","BackgroundColor":"16161f","OutlineColor":"323232"}') },
		['Ubuntu'] 			= { 7, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"3e3e3e","AccentColor":"e2581e","BackgroundColor":"323232","OutlineColor":"191919"}') },
		['Quartz'] 			= { 8, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"232330","AccentColor":"426e87","BackgroundColor":"1d1b26","OutlineColor":"27232f"}') },
		['Sakura'] = { 9, httpService:JSONDecode('{"FontColor":"fff0f6","MainColor":"2a1f2b","AccentColor":"ff8fb8","BackgroundColor":"211822","OutlineColor":"4a3346"}') },
		['Midnight Ocean'] = { 10, httpService:JSONDecode('{"FontColor":"e6f4ff","MainColor":"101a2b","AccentColor":"38bdf8","BackgroundColor":"0b1322","OutlineColor":"1f3350"}') },
		['Aurora'] = { 11, httpService:JSONDecode('{"FontColor":"eafffb","MainColor":"14201f","AccentColor":"5eead4","BackgroundColor":"0f1918","OutlineColor":"25403c"}') },
		['Dracula'] = { 12, httpService:JSONDecode('{"FontColor":"f8f8f2","MainColor":"282a36","AccentColor":"bd93f9","BackgroundColor":"21222c","OutlineColor":"44475a"}') },
		['Nord'] = { 13, httpService:JSONDecode('{"FontColor":"eceff4","MainColor":"2e3440","AccentColor":"88c0d0","BackgroundColor":"272c36","OutlineColor":"434c5e"}') },
		['Catppuccin'] = { 14, httpService:JSONDecode('{"FontColor":"cdd6f4","MainColor":"1e1e2e","AccentColor":"cba6f7","BackgroundColor":"181825","OutlineColor":"313244"}') },
		['Gruvbox'] = { 15, httpService:JSONDecode('{"FontColor":"ebdbb2","MainColor":"282828","AccentColor":"fe8019","BackgroundColor":"1d2021","OutlineColor":"504945"}') },
		['Cyberpunk'] = { 16, httpService:JSONDecode('{"FontColor":"e0fbfc","MainColor":"14121f","AccentColor":"fcee0a","BackgroundColor":"0d0b16","OutlineColor":"2e2a45"}') },
		['Rose Gold'] = { 17, httpService:JSONDecode('{"FontColor":"fff5f2","MainColor":"2b2224","AccentColor":"e8a598","BackgroundColor":"221b1c","OutlineColor":"4a3a3c"}') },
		['Royal Gold'] = { 18, httpService:JSONDecode('{"FontColor":"fff8e1","MainColor":"1a1a14","AccentColor":"d4af37","BackgroundColor":"141410","OutlineColor":"3a3626"}') },
		['VS Code'] = { 19, httpService:JSONDecode('{"FontColor":"cccccc","MainColor":"1f1f1f","AccentColor":"0078d4","BackgroundColor":"181818","OutlineColor":"2b2b2b"}') },
		['Everforest'] = { 20, httpService:JSONDecode('{"FontColor":"d3c6aa","MainColor":"2d353b","AccentColor":"a7c080","BackgroundColor":"232a2e","OutlineColor":"475258"}') },
		['Kanagawa'] = { 21, httpService:JSONDecode('{"FontColor":"dcd7ba","MainColor":"1f1f28","AccentColor":"7e9cd8","BackgroundColor":"16161d","OutlineColor":"363646"}') },
		['Sunset'] = { 22, httpService:JSONDecode('{"FontColor":"ffeee6","MainColor":"221c35","AccentColor":"ff7a59","BackgroundColor":"1a152b","OutlineColor":"3d3358"}') },
		['Crimson'] = { 23, httpService:JSONDecode('{"FontColor":"f5e6e6","MainColor":"1d1416","AccentColor":"e5484d","BackgroundColor":"151011","OutlineColor":"3d262a"}') },
		['Solarized'] = { 24, httpService:JSONDecode('{"FontColor":"eee8d5","MainColor":"073642","AccentColor":"b58900","BackgroundColor":"002b36","OutlineColor":"0f4b5a"}') },
	}

	function ThemeManager:ApplyTheme(theme)
		local customThemeData = self:GetCustomTheme(theme)
		local data = customThemeData or self.BuiltInThemes[theme]

		if not data then return end

		-- custom themes are just regular dictionaries instead of an array with { index, dictionary }

		local scheme = data[2]
		for idx, col in next, customThemeData or scheme do
			self.Library[idx] = Color3.fromHex(col)
			
			if Options[idx] then
				Options[idx]:SetValueRGB(Color3.fromHex(col))
			end
		end

		self:ThemeUpdate()
	end

	function ThemeManager:ThemeUpdate()
		-- This allows us to force apply themes without loading the themes tab :)
		local options = { "FontColor", "MainColor", "AccentColor", "BackgroundColor", "OutlineColor" }
		for i, field in next, options do
			if Options and Options[field] then
				self.Library[field] = Options[field].Value
			end
		end

		self.Library.AccentColorDark = self.Library:GetDarkerColor(self.Library.AccentColor);
		self.Library:UpdateColorsUsingRegistry()
	end

	function ThemeManager:LoadDefault()		
		local theme = 'VS Code'
		local content = isfile(self.Folder .. '/themes/default.txt') and readfile(self.Folder .. '/themes/default.txt')

		local isDefault = true
		if content then
			if self.BuiltInThemes[content] then
				theme = content
			elseif self:GetCustomTheme(content) then
				theme = content
				isDefault = false;
			end
		elseif self.BuiltInThemes[self.DefaultTheme] then
		 	theme = self.DefaultTheme
		end

		if isDefault then
			Options.ThemeManager_ThemeList:SetValue(theme)
		else
			self:ApplyTheme(theme)
		end
	end

	function ThemeManager:SaveDefault(theme)
		writefile(self.Folder .. '/themes/default.txt', theme)
	end

	-- colorsBox / customBox (optional): put the color pickers and the custom themes in boxes of their own
	-- (ApplyToTab: tabs of one tabbox); all three default to groupbox.
	function ThemeManager:CreateThemeManager(groupbox, colorsBox, customBox)
		colorsBox, customBox = colorsBox or groupbox, customBox or groupbox
		colorsBox:AddLabel('Background color'):AddColorPicker('BackgroundColor', { Default = self.Library.BackgroundColor });
		colorsBox:AddLabel('Main color')	:AddColorPicker('MainColor', { Default = self.Library.MainColor });
		colorsBox:AddLabel('Accent color'):AddColorPicker('AccentColor', { Default = self.Library.AccentColor });
		colorsBox:AddLabel('Outline color'):AddColorPicker('OutlineColor', { Default = self.Library.OutlineColor });
		colorsBox:AddLabel('Font color')	:AddColorPicker('FontColor', { Default = self.Library.FontColor });

		-- built-in accent animation; a client that made its own toggles (kenya_client) keeps them
		if not Toggles.RainbowAccent and not Toggles.GradientAccent then
			colorsBox:AddDivider()
			colorsBox:AddToggle('RainbowAccent', { Text = 'Animate accent', Default = false })
			colorsBox:AddToggle('GradientAccent', { Text = 'Gradient accent', Default = false, Tooltip = 'Spread the accent across the window instead of one flat color' })
			local function ApplyAccentMode()
				self.Library:SetRainbowAccent(Toggles.RainbowAccent.Value, Toggles.GradientAccent.Value)
			end
			Toggles.RainbowAccent:OnChanged(ApplyAccentMode)
			Toggles.GradientAccent:OnChanged(ApplyAccentMode)
		end

		local ThemesArray = {}
		for Name, Theme in next, self.BuiltInThemes do
			table.insert(ThemesArray, Name)
		end

		table.sort(ThemesArray, function(a, b) return self.BuiltInThemes[a][1] < self.BuiltInThemes[b][1] end)

		if colorsBox == groupbox then groupbox:AddDivider() end
		groupbox:AddDropdown('ThemeManager_ThemeList', { Text = 'Theme list', Values = ThemesArray, Default = 1 })

		groupbox:AddButton('Set as default', function()
			self:SaveDefault(Options.ThemeManager_ThemeList.Value)
			self.Library:Notify(string.format('Set default theme to %q', Options.ThemeManager_ThemeList.Value))
		end)

		Options.ThemeManager_ThemeList:OnChanged(function()
			self:ApplyTheme(Options.ThemeManager_ThemeList.Value)
		end)

		if customBox == groupbox then groupbox:AddDivider() end
		customBox:AddInput('ThemeManager_CustomThemeName', { Text = 'Custom theme name' })
		customBox:AddDropdown('ThemeManager_CustomThemeList', { Text = 'Custom themes', Values = self:ReloadCustomThemes(), AllowNull = true, Default = 1 })
		customBox:AddDivider()
		
		customBox:AddButton('Save theme', function() 
			self:SaveCustomTheme(Options.ThemeManager_CustomThemeName.Value)

			Options.ThemeManager_CustomThemeList:SetValues(self:ReloadCustomThemes())
			Options.ThemeManager_CustomThemeList:SetValue(nil)
		end):AddButton('Load theme', function() 
			self:ApplyTheme(Options.ThemeManager_CustomThemeList.Value) 
		end)

		customBox:AddButton('Refresh list', function()
			Options.ThemeManager_CustomThemeList:SetValues(self:ReloadCustomThemes())
			Options.ThemeManager_CustomThemeList:SetValue(nil)
		end)

		customBox:AddButton('Set as default', function()
			if Options.ThemeManager_CustomThemeList.Value ~= nil and Options.ThemeManager_CustomThemeList.Value ~= '' then
				self:SaveDefault(Options.ThemeManager_CustomThemeList.Value)
				self.Library:Notify(string.format('Set default theme to %q', Options.ThemeManager_CustomThemeList.Value))
			end
		end)

		ThemeManager:LoadDefault()

		local function UpdateTheme()
			self:ThemeUpdate()
		end

		Options.BackgroundColor:OnChanged(UpdateTheme)
		Options.MainColor:OnChanged(UpdateTheme)
		Options.AccentColor:OnChanged(UpdateTheme)
		Options.OutlineColor:OnChanged(UpdateTheme)
		Options.FontColor:OnChanged(UpdateTheme)
	end

	function ThemeManager:GetCustomTheme(file)
		local path = self.Folder .. '/themes/' .. file
		if not isfile(path) then
			return nil
		end

		local data = readfile(path)
		local success, decoded = pcall(httpService.JSONDecode, httpService, data)
		
		if not success then
			return nil
		end

		return decoded
	end

	function ThemeManager:SaveCustomTheme(file)
		if file:gsub(' ', '') == '' then
			return self.Library:Notify('Invalid file name for theme (empty)', 3)
		end

		local theme = {}
		local fields = { "FontColor", "MainColor", "AccentColor", "BackgroundColor", "OutlineColor" }

		for _, field in next, fields do
			theme[field] = Options[field].Value:ToHex()
		end

		writefile(self.Folder .. '/themes/' .. file .. '.json', httpService:JSONEncode(theme))
	end

	function ThemeManager:ReloadCustomThemes()
		local list = listfiles(self.Folder .. '/themes')

		local out = {}
		for i = 1, #list do
			local file = list[i]
			if file:sub(-5) == '.json' then
				-- i hate this but it has to be done ...

				local pos = file:find('.json', 1, true)
				local char = file:sub(pos, pos)

				while char ~= '/' and char ~= '\\' and char ~= '' do
					pos = pos - 1
					char = file:sub(pos, pos)
				end

				if char == '/' or char == '\\' then
					table.insert(out, file:sub(pos + 1))
				end
			end
		end

		return out
	end

	function ThemeManager:SetLibrary(lib)
		self.Library = lib
	end

	function ThemeManager:BuildFolderTree()
		local paths = {}

		-- build the entire tree if a path is like some-hub/phantom-forces
		-- makefolder builds the entire tree on Synapse X but not other exploits

		local parts = self.Folder:split('/')
		for idx = 1, #parts do
			paths[#paths + 1] = table.concat(parts, '/', 1, idx)
		end

		table.insert(paths, self.Folder .. '/themes')
		table.insert(paths, self.Folder .. '/settings')

		for i = 1, #paths do
			local str = paths[i]
			if not isfolder(str) then
				makefolder(str)
			end
		end
	end

	function ThemeManager:SetFolder(folder)
		self.Folder = folder
		self:BuildFolderTree()
	end

	function ThemeManager:CreateGroupBox(tab)
		assert(self.Library, 'Must set ThemeManager.Library first!')
		return tab:AddLeftGroupbox('Themes')
	end

	-- One 'Themes' tabbox: Theme (the list), Colors (the pickers, accent toggles), Custom (saved themes).
	function ThemeManager:ApplyToTab(tab)
		assert(self.Library, 'Must set ThemeManager.Library first!')
		local Tabbox = tab:AddLeftTabbox('Themes')
		self:CreateThemeManager(Tabbox:AddTab('Theme'), Tabbox:AddTab('Colors'), Tabbox:AddTab('Custom'))
	end

	function ThemeManager:ApplyToGroupbox(groupbox)
		assert(self.Library, 'Must set ThemeManager.Library first!')
		self:CreateThemeManager(groupbox)
	end

	-- Kenya Client style Settings: Menu groupbox (keybind, scale, fade, watermark / keybind HUD, unload)
	-- and Accent groupbox (animate, gradient, direction, custom colors). Call before ApplyToTab so the
	-- built-in accent toggles there are skipped. Returns the Menu and Accent groupboxes.
	function ThemeManager:BuildMenuSection(tab)
		-- One 'Menu' tabbox, a handful of controls a tab: General (keybind, scale, HUD, layout), Motion (animations,
		-- dragging), Glass (opacity and blur; frosted glass windows only) and Look (cursor, glow). Twelve controls
		-- in General alone read as clutter. The option ids are unchanged, so saved settings still load.
		local MenuTabs = tab:AddLeftTabbox('Menu')
		local MenuGroup, MotionGroup = MenuTabs:AddTab('General'), MenuTabs:AddTab('Motion')
		local GlassGroup = Library.Blur and MenuTabs:AddTab('Glass') -- a script that set GlassTransparency = 0 keeps its solid menu
		local LookGroup = MenuTabs:AddTab('Look')

		MenuGroup:AddLabel('Menu bind'):AddKeyPicker('MenuKeybind', { Default = 'End', NoUI = true, Text = 'Menu keybind' })
		MenuGroup:AddSlider('UIScale', { Text = 'UI scale', Default = 1, Min = 0.5, Max = 2, Rounding = 2, Suffix = 'x', HideMax = true, Tooltip = 'Size of the menu and its popups' })
		MotionGroup:AddToggle('UIAnimations', { Text = 'Animations', Default = true, Tooltip = 'Eased fades, slides and hovers. Off: everything changes instantly', Callback = function(Value) Library.Animations = Value end })
		MotionGroup:AddToggle('LightDrag', { Text = 'Light drag', Default = true, Tooltip = 'Drag the menu as an outline and move it on release: no FPS drop while dragging. Off: the menu follows the cursor', Callback = function(Value) Library.LightDrag = Value end })
		MotionGroup:AddSlider('MenuFadeTime', { Text = 'Open / close fade time', Default = 0.25, Min = 0, Max = 1, Rounding = 2, Suffix = 's', HideMax = true })
		if GlassGroup then
			GlassGroup:AddSlider('MenuOpacity', { Text = 'Menu opacity', Default = math.floor((1 - Library.GlassTransparency) * 100 + 0.5), Min = 20, Max = 100, Rounding = 0, Suffix = '%', HideMax = true, Tooltip = 'How solid the menu background is. Lower shows more of the blurred game behind it; 100% is solid and turns the blur off' })
			Options.MenuOpacity:OnChanged(function(Value) Library:SetGlassTransparency(1 - Value / 100) end)
			GlassGroup:AddSlider('BlurStrength', { Text = 'Blur strength', Default = 100, Min = 0, Max = 100, Rounding = 0, Suffix = '%', HideMax = true, Tooltip = 'How strongly the game behind the menu is blurred. 100% is the most the effect gives; 0% shows the game sharp' })
			Options.BlurStrength:OnChanged(function(Value) Library.BlurStrength = Value / 100 end)
			GlassGroup:AddToggle('BlurBillboards', { Text = 'Blur name tags', Default = true, Tooltip = 'While the menu is open, the game\'s name tags, health bars and damage numbers behind it blur with the scene. Off: they show sharp through the menu', Callback = function(Value) Library.BlurBillboards = Value end })
		end
		MenuGroup:AddToggle('ShowWatermark', { Text = 'Show watermark', Default = true, Tooltip = 'FPS / ping bar at the top of the screen' })
		MenuGroup:AddToggle('ShowKeybinds', { Text = 'Show keybind list', Default = true, Tooltip = 'HUD listing active keybinds (hidden while empty)' })
		LookGroup:AddInput('CursorImage', { Text = 'Custom cursor', Placeholder = 'Image URL, file or rbxassetid', Finished = true, Tooltip = 'Image shown as the menu cursor. A URL is downloaded once (getcustomasset). Empty: default triangle' })
		LookGroup:AddSlider('CursorSize', { Text = 'Cursor size', Default = 24, Min = 8, Max = 64, Rounding = 0, Suffix = 'px', HideMax = true })
		Options.CursorImage:OnChanged(function(Value) Library:SetCursor(Value) end)
		Options.CursorSize:OnChanged(function(Value) Library:SetCursor(nil, Value) end)
		LookGroup:AddToggle('WindowGlow', { Text = 'Window glow', Default = false, Tooltip = 'Soft accent-colored glow around the menu' })
		local GlowBox = LookGroup:AddDependencyBox()
		GlowBox:AddSlider('GlowSize', { Text = 'Glow size', Default = 30, Min = 5, Max = 100, Rounding = 0, Suffix = 'px', HideMax = true })
		GlowBox:AddSlider('GlowStrength', { Text = 'Glow strength', Default = 50, Min = 5, Max = 100, Rounding = 0, Suffix = '%', HideMax = true })
		GlowBox:SetupDependencies({ { Toggles.WindowGlow, true } })
		LookGroup:AddToggle('ElementGlow', { Text = 'Element glow', Default = false, Tooltip = 'Glow under switched-on toggles, slider fills and color swatches' })
		local ElementGlowBox = LookGroup:AddDependencyBox()
		ElementGlowBox:AddSlider('ElementGlowStrength', { Text = 'Element glow strength', Default = 45, Min = 5, Max = 100, Rounding = 0, Suffix = '%', HideMax = true })
		ElementGlowBox:SetupDependencies({ { Toggles.ElementGlow, true } })
		local function ApplyElementGlow()
		    Library:SetElementGlow(Toggles.ElementGlow.Value, 1 - Options.ElementGlowStrength.Value / 100)
		end
		Toggles.ElementGlow:OnChanged(ApplyElementGlow)
		Options.ElementGlowStrength:OnChanged(ApplyElementGlow)
		local function ApplyGlow()
		    Library:SetGlow(Toggles.WindowGlow.Value, Options.GlowSize.Value, 1 - Options.GlowStrength.Value / 100)
		end
		Toggles.WindowGlow:OnChanged(ApplyGlow)
		Options.GlowSize:OnChanged(ApplyGlow)
		Options.GlowStrength:OnChanged(ApplyGlow)
		MenuGroup:AddDivider()
		MenuGroup:AddButton({ Text = 'Reset layout', Func = function() Library:ResetLayout() end, Tooltip = 'Drag a section by its title to move it, or drop it outside the menu to keep it on screen. This puts every section back' })
		MenuGroup:AddButton('Unload', function() Library:Unload() end)

		local AccentGroup = tab:AddRightGroupbox('Accent')

		AccentGroup:AddToggle('RainbowAccent', { Text = 'Animate accent', Default = false, Tooltip = 'Rainbow: cycle the hue. Custom colors: flow them across the menu' })
		AccentGroup:AddToggle('GradientAccent', { Text = 'Gradient accent', Default = false, Tooltip = 'Spread the accent across the window instead of one flat color' })

		-- Everything below only does something while the accent animates or spreads; with both off it is one flat
		-- theme color, so the controls stay hidden instead of looking broken.
		local DynamicBox = AccentGroup:AddDependencyBox()
		AccentGroup = DynamicBox
		local SpeedBox = AccentGroup:AddDependencyBox()
		SpeedBox:AddSlider('RainbowSpeed', { Text = 'Animation speed', Default = 1, Min = 0.1, Max = 5, Rounding = 1, Suffix = 'x', HideMax = true })
		SpeedBox:SetupDependencies({ { Toggles.RainbowAccent, true } })

		-- Gradient shape (only shown while the gradient is on)
		local GradientBox = AccentGroup:AddDependencyBox()
		GradientBox:AddDropdown('GradientDirection', { Text = 'Gradient direction', Values = { 'Vertical', 'Horizontal', 'Diagonal' }, Default = 1 })
		GradientBox:AddToggle('GradientReverse', { Text = 'Reverse direction', Default = false })
		GradientBox:SetupDependencies({ { Toggles.GradientAccent, true } })

		-- Color source: rainbow hue wheel, or a blend between two colors of your choice
		AccentGroup:AddToggle('CustomGradientColors', { Text = 'Custom colors', Default = false, Tooltip = 'Blend between two colors instead of the rainbow' })

		local CustomBox = AccentGroup:AddDependencyBox()
		CustomBox:AddLabel('Color A (start)'):AddColorPicker('GradientColorA', { Default = Color3.fromRGB(0, 170, 255), Title = 'Gradient color A' })
		CustomBox:AddLabel('Color B (end)'):AddColorPicker('GradientColorB', { Default = Color3.fromRGB(170, 0, 255), Title = 'Gradient color B' })
		CustomBox:AddButton('Swap colors', function()
		    local A, B = Options.GradientColorA.Value, Options.GradientColorB.Value
		    Options.GradientColorA:SetValueRGB(B)
		    Options.GradientColorB:SetValueRGB(A)
		end)
		CustomBox:SetupDependencies({ { Toggles.CustomGradientColors, true } })

		local RainbowBox = AccentGroup:AddDependencyBox()
		RainbowBox:AddSlider('GradientSpread', { Text = 'Gradient spread', Default = 0.35, Min = 0.05, Max = 1, Rounding = 2, HideMax = true, Tooltip = 'How much of the hue wheel the gradient covers from start to end' })
		RainbowBox:AddSlider('RainbowSaturation', { Text = 'Rainbow saturation', Default = 80, Min = 0, Max = 100, Rounding = 0, Suffix = '%', HideMax = true })
		RainbowBox:AddSlider('RainbowBrightness', { Text = 'Rainbow brightness', Default = 100, Min = 20, Max = 100, Rounding = 0, Suffix = '%', HideMax = true })
		RainbowBox:SetupDependencies({ { Toggles.CustomGradientColors, false } })
		DynamicBox:SetupDependencies({ { function() return Toggles.RainbowAccent.Value or Toggles.GradientAccent.Value end, true } })

		local function ApplyAccentMode()
		    Library:SetRainbowAccent(Toggles.RainbowAccent.Value, Toggles.GradientAccent.Value)
		end

		Toggles.RainbowAccent:OnChanged(ApplyAccentMode)
		Toggles.GradientAccent:OnChanged(ApplyAccentMode)

		Options.RainbowSpeed:OnChanged(function(Value) Library.RainbowSpeed = Value end)
		Options.GradientSpread:OnChanged(function(Value) Library.GradientSpread = Value end)
		Options.GradientDirection:OnChanged(function(Value) Library.GradientDirection = Value end)
		Toggles.GradientReverse:OnChanged(function(Value) Library.GradientReverse = Value end)
		Options.RainbowSaturation:OnChanged(function(Value) Library.RainbowSaturation = Value / 100 end)
		Options.RainbowBrightness:OnChanged(function(Value) Library.RainbowValue = Value / 100 end)
		Options.GradientColorA:OnChanged(function(Value) Library.GradientColorA = Value end)
		Options.GradientColorB:OnChanged(function(Value) Library.GradientColorB = Value end)
		Toggles.CustomGradientColors:OnChanged(function(Value)
		    Library.GradientMode = Value and 'Custom' or 'Rainbow'
		    Library:RefreshAccent()
		end)
		Options.UIScale:OnChanged(function(Value) Library:SetScale(Value) end)
		Options.MenuFadeTime:OnChanged(function(Value) Library.MenuFadeTime = Value end)
		Toggles.ShowWatermark:OnChanged(function(Value) Library:SetWatermarkVisibility(Value) end)
		Toggles.ShowKeybinds:OnChanged(function(Value) Library:SetKeybindFrameVisibility(Value) end)

		Library.ToggleKeybind = Options.MenuKeybind -- Allows you to have a custom keybind for the menu

		return MenuGroup, AccentGroup
	end

	ThemeManager:BuildFolderTree()
end

return ThemeManager
end)()

local SaveManager = (function()
local httpService = game:GetService('HttpService')

local SaveManager = {} do
	SaveManager.Folder = 'LinoriaLibSettings'
	SaveManager.Ignore = {}
	SaveManager.Parser = {
		Toggle = {
			Save = function(idx, object) 
				return { type = 'Toggle', idx = idx, value = object.Value } 
			end,
			Load = function(idx, data)
				if Toggles[idx] then 
					Toggles[idx]:SetValue(data.value)
				end
			end,
		},
		Slider = {
			Save = function(idx, object)
				return { type = 'Slider', idx = idx, value = tostring(object.Value) }
			end,
			Load = function(idx, data)
				if Options[idx] then 
					Options[idx]:SetValue(data.value)
				end
			end,
		},
		Dropdown = {
			Save = function(idx, object)
				return { type = 'Dropdown', idx = idx, value = object.Value, mutli = object.Multi }
			end,
			Load = function(idx, data)
				if Options[idx] then 
					Options[idx]:SetValue(data.value)
				end
			end,
		},
		ColorPicker = {
			Save = function(idx, object)
				return { type = 'ColorPicker', idx = idx, value = object.Value:ToHex(), transparency = object.Transparency }
			end,
			Load = function(idx, data)
				if Options[idx] then 
					Options[idx]:SetValueRGB(Color3.fromHex(data.value), data.transparency)
				end
			end,
		},
		KeyPicker = {
			Save = function(idx, object)
				return { type = 'KeyPicker', idx = idx, mode = object.Mode, key = object.Value }
			end,
			Load = function(idx, data)
				if Options[idx] then 
					Options[idx]:SetValue({ data.key, data.mode })
				end
			end,
		},

		Input = {
			Save = function(idx, object)
				return { type = 'Input', idx = idx, text = object.Value }
			end,
			Load = function(idx, data)
				if Options[idx] and type(data.text) == 'string' then
					Options[idx]:SetValue(data.text)
				end
			end,
		},
	}

	function SaveManager:SetIgnoreIndexes(list)
		for _, key in next, list do
			self.Ignore[key] = true
		end
	end

	function SaveManager:SetFolder(folder)
		self.Folder = folder;
		self:BuildFolderTree();
		-- section layout (moved / folded / floating boxes) lives next to the configs and saves itself
		(self.Library or Library).LayoutFile = folder .. '/layout.json'
	end

	function SaveManager:Save(name)
		if (not name) then
			return false, 'no config file is selected'
		end

		local fullPath = self.Folder .. '/settings/' .. name .. '.json'

		local data = {
			objects = {}
		}

		for idx, toggle in next, Toggles do
			if self.Ignore[idx] then continue end

			table.insert(data.objects, self.Parser[toggle.Type].Save(idx, toggle))
		end

		for idx, option in next, Options do
			if not self.Parser[option.Type] then continue end
			if self.Ignore[idx] then continue end

			table.insert(data.objects, self.Parser[option.Type].Save(idx, option))
		end	

		local success, encoded = pcall(httpService.JSONEncode, httpService, data)
		if not success then
			return false, 'failed to encode data'
		end

		writefile(fullPath, encoded)
		return true
	end

	function SaveManager:Load(name)
		if (not name) then
			return false, 'no config file is selected'
		end
		
		local file = self.Folder .. '/settings/' .. name .. '.json'
		if not isfile(file) then return false, 'invalid file' end

		local success, decoded = pcall(httpService.JSONDecode, httpService, readfile(file))
		if not success then return false, 'decode error' end

		for _, option in next, decoded.objects do
			if self.Parser[option.type] then
				task.spawn(function() self.Parser[option.type].Load(option.idx, option) end) -- task.spawn() so the config loading wont get stuck.
			end
		end

		return true
	end

	function SaveManager:IgnoreThemeSettings()
		self:SetIgnoreIndexes({ 
			"BackgroundColor", "MainColor", "AccentColor", "OutlineColor", "FontColor", -- themes
			"ThemeManager_ThemeList", 'ThemeManager_CustomThemeList', 'ThemeManager_CustomThemeName', -- themes
		})
	end

	function SaveManager:BuildFolderTree()
		local paths = {
			self.Folder,
			self.Folder .. '/themes',
			self.Folder .. '/settings'
		}

		for i = 1, #paths do
			local str = paths[i]
			if not isfolder(str) then
				makefolder(str)
			end
		end
	end

	function SaveManager:RefreshConfigList()
		local list = listfiles(self.Folder .. '/settings')

		local out = {}
		for i = 1, #list do
			local file = list[i]
			if file:sub(-5) == '.json' then
				-- i hate this but it has to be done ...

				local pos = file:find('.json', 1, true)
				local start = pos

				local char = file:sub(pos, pos)
				while char ~= '/' and char ~= '\\' and char ~= '' do
					pos = pos - 1
					char = file:sub(pos, pos)
				end

				if char == '/' or char == '\\' then
					table.insert(out, file:sub(pos + 1, start - 1))
				end
			end
		end
		
		return out
	end

	function SaveManager:SetLibrary(library)
		self.Library = library
	end

	function SaveManager:LoadAutoloadConfig()
		-- hubs call this once every section exists, so it is also where the saved layout goes back on
		self.Library:LoadLayout()

		if isfile(self.Folder .. '/settings/autoload.txt') then
			local name = readfile(self.Folder .. '/settings/autoload.txt')

			local success, err = self:Load(name)
			if not success then
				return self.Library:Notify('Failed to load autoload config: ' .. err)
			end

			self.Library:Notify(string.format('Auto loaded config %q', name))
		end
	end


	function SaveManager:BuildConfigSection(tab)
		assert(self.Library, 'Must set SaveManager.Library')

		local section = tab:AddRightGroupbox('Configuration')

		section:AddInput('SaveManager_ConfigName',    { Text = 'Config name' })
		section:AddDropdown('SaveManager_ConfigList', { Text = 'Config list', Values = self:RefreshConfigList(), AllowNull = true })

		section:AddDivider()

		section:AddButton('Create config', function()
			local name = Options.SaveManager_ConfigName.Value

			if name:gsub(' ', '') == '' then 
				return self.Library:Notify('Invalid config name (empty)', 2)
			end

			local success, err = self:Save(name)
			if not success then
				return self.Library:Notify('Failed to save config: ' .. err)
			end

			self.Library:Notify(string.format('Created config %q', name))

			Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
			Options.SaveManager_ConfigList:SetValue(nil)
		end):AddButton('Load config', function()
			local name = Options.SaveManager_ConfigList.Value

			local success, err = self:Load(name)
			if not success then
				return self.Library:Notify('Failed to load config: ' .. err)
			end

			self.Library:Notify(string.format('Loaded config %q', name))
		end)

		section:AddButton('Overwrite config', function()
			local name = Options.SaveManager_ConfigList.Value

			local success, err = self:Save(name)
			if not success then
				return self.Library:Notify('Failed to overwrite config: ' .. err)
			end

			self.Library:Notify(string.format('Overwrote config %q', name))
		end)

		section:AddButton('Refresh list', function()
			Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
			Options.SaveManager_ConfigList:SetValue(nil)
		end)

		section:AddButton('Set as autoload', function()
			local name = Options.SaveManager_ConfigList.Value
			writefile(self.Folder .. '/settings/autoload.txt', name)
			SaveManager.AutoloadLabel:SetText('Current autoload config: ' .. name)
			self.Library:Notify(string.format('Set %q to auto load', name))
		end)

		SaveManager.AutoloadLabel = section:AddLabel('Current autoload config: none', true)

		if isfile(self.Folder .. '/settings/autoload.txt') then
			local name = readfile(self.Folder .. '/settings/autoload.txt')
			SaveManager.AutoloadLabel:SetText('Current autoload config: ' .. name)
		end

		SaveManager:SetIgnoreIndexes({ 'SaveManager_ConfigList', 'SaveManager_ConfigName' })
	end

	SaveManager:BuildFolderTree()
end

return SaveManager
end)()

Library.ThemeManager = ThemeManager
Library.SaveManager = SaveManager

return Library
