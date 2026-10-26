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
        Library:SetGlow(on, size, transparency)   -- accent glow around the window
        Library:SetElementGlow(on, transparency)  -- glow under toggles, slider fills and color swatches
        Library:AddGlow(parent, size, zindex, colorKey) -- add your own glow to any frame
        Groupbox:AddProgressBar(idx, { Text, Default, Min, Max, Suffix, Format }) -- read-only thin bar, update with :SetValue(n)
        Library:RunOnUIThread(fn, ...)            -- run a menu update from a game callback (CoreGui needs executor identity);
                                                  -- SetText / SetValue / Notify / Toggle / SetWatermark already do this themselves
        Sections (every groupbox / tabbox)        -- -/+ folds it; drag its title to move it (accent box = where it
                                                  -- lands); drop it outside the window to float it, its pin square
                                                  -- keeps it shown while the menu is hidden. Library:GetLayout(),
                                                  -- :ApplyLayout(t), :SaveLayout(), :LoadLayout(), :ResetLayout();
                                                  -- saved to Library.LayoutFile (SaveManager:SetFolder sets it,
                                                  -- SaveManager:LoadAutoloadConfig loads it)
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
]]

local InputService = game:GetService('UserInputService');
local TextService = game:GetService('TextService');
local CoreGui = game:GetService('CoreGui');
local Teams = game:GetService('Teams');
local Players = game:GetService('Players');
local RunService = game:GetService('RunService')
local TweenService = game:GetService('TweenService');
local RenderStepped = RunService.RenderStepped;
local LocalPlayer = Players.LocalPlayer;
local Mouse = LocalPlayer:GetMouse();

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

    FontColor = Color3.fromRGB(255, 255, 255);
    MainColor = Color3.fromRGB(28, 28, 28);
    BackgroundColor = Color3.fromRGB(20, 20, 20);
    AccentColor = Color3.fromRGB(0, 85, 255);
    OutlineColor = Color3.fromRGB(50, 50, 50);
    RiskColor = Color3.fromRGB(255, 50, 50),

    Black = Color3.new(0, 0, 0);
    Font = Enum.Font.Code,

    OpenedFrames = {};
    DependencyBoxes = {};

    Signals = {};
    ScreenGui = ScreenGui;
    PanelGuis = PanelGuis;

    Version = 8;          -- bump when the public API changes; clients check this against the GitHub copy
    UIScale = 1;          -- window + popup scale, see Library:SetScale
    Popups = {};          -- dropdown lists / color pickers / menus parented to the ScreenGui, scaled with the window
    RainbowSpeed = 1;     -- multiplier for the accent animation speed (hue cycle / custom color flow)
    GradientSpread = 0.35;-- hue range spread across the window when GradientAccent is on (rainbow mode)
    MenuFadeTime = nil;   -- overrides the window's MenuFadeTime when set (seconds)
    Animations = true;    -- eased UI changes (see Library:CreateTween); false makes everything snap

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

local function PingPong(X)
    X = X % 1;
    return 1 - math.abs(2 * X - 1);
end;

-- True while the library (not the theme) is driving the accent color.
local function AccentIsDynamic()
    return Library.RainbowAccent or Library.GradientAccent or Library.GradientMode == 'Custom';
end;

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

            -- While the menu is hidden only the HUD pieces (watermark, keybind list, notifications) need recoloring.
            local Hidden = Library.MainWindow and not Library.MainWindow.Visible;
            Library:UpdateAccentColors(Hidden and Library.HudRegistry or nil);
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

function Library:MakeDraggable(Instance, Cutoff)
    Instance.Active = true;

    Instance.InputBegan:Connect(function(Input)
        if Input.UserInputType == Enum.UserInputType.MouseButton1 then
            local ObjPos = Vector2.new(
                Mouse.X - Instance.AbsolutePosition.X,
                Mouse.Y - Instance.AbsolutePosition.Y
            );

            if ObjPos.Y > (Cutoff or 40) then
                return;
            end;

            while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
                Instance.Position = UDim2.new(
                    0,
                    Mouse.X - ObjPos.X + (Instance.AbsoluteSize.X * Instance.AnchorPoint.X),
                    0,
                    Mouse.Y - ObjPos.Y + (Instance.AbsoluteSize.Y * Instance.AnchorPoint.Y)
                );

                RenderStepped:Wait();
            end;
        end;
    end)
end;

function Library:AddToolTip(InfoStr, HoverInstance)
    -- Long tooltips wrap at 300 px instead of running off the edge of the screen.
    local X, Y = Library:GetTextBounds(InfoStr, Library.Font, 14, Vector2.new(300, math.huge));
    local Tooltip = Library:Create('Frame', {
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
        Text = InfoStr,
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

    -- Right of and below the cursor by default; flipped to the other side of the cursor when that would run
    -- past the screen edge, then clamped so it is always fully on screen.
    local function PlaceTooltip()
        local Screen = Library.ScreenGui.AbsoluteSize;
        local Width, Height = Tooltip.AbsoluteSize.X, Tooltip.AbsoluteSize.Y;
        local PosX, PosY = Mouse.X + 15, Mouse.Y + 12;

        if PosX + Width > Screen.X - 4 then
            PosX = Mouse.X - 10 - Width;
        end;

        if PosY + Height > Screen.Y - 4 then
            PosY = Mouse.Y - 6 - Height;
        end;

        PosX = math.clamp(PosX, 4, math.max(4, Screen.X - Width - 4));
        PosY = math.clamp(PosY, 4, math.max(4, Screen.Y - Height - 4));
        Tooltip.Position = UDim2.fromOffset(PosX, PosY);
    end;

    HoverInstance.MouseEnter:Connect(function()
        if Library:MouseIsOverOpenedFrame() then
            return
        end

        IsHovering = true

        PlaceTooltip()
        Tooltip.Visible = true

        while IsHovering do
            RunService.Heartbeat:Wait()
            PlaceTooltip()
        end
    end)

    HoverInstance.MouseLeave:Connect(function()
        IsHovering = false
        Tooltip.Visible = false
    end)
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

function Library:Unload()
    -- Unload all of the signals
    for Idx = #Library.Signals, 1, -1 do
        local Connection = table.remove(Library.Signals, Idx)
        Connection:Disconnect()
    end

     -- Call our unload callback, maybe to undo some hooks etc
    if Library.OnUnload then
        Library.OnUnload()
    end

    ScreenGui:Destroy()

    for _, Gui in next, PanelGuis do
        Gui:Destroy()
    end
end

function Library:OnUnload(Callback)
    Library.OnUnload = Callback
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

-- Scales the main window and every popup. 1 = default size.
function Library:SetScale(Scale)
    Scale = math.clamp(tonumber(Scale) or 1, 0.5, 2);
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

local BaseAddons = {};

do
    local Funcs = {};

    function Funcs:AddColorPicker(Idx, Info)
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

        -- Below the swatch, flipping to right-aligned / above it when it would leave the screen.
        local function PlacePicker()
            local Pos, Size = DisplayFrame.AbsolutePosition, DisplayFrame.AbsoluteSize;
            Library:PlacePopup(PickerFrameOuter, Pos.X, Pos.Y + 18, Pos.X + Size.X, Pos.Y - 4);
        end;

        DisplayFrame:GetPropertyChangedSignal('AbsolutePosition'):Connect(PlacePicker)

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

            DisplayFrame:GetPropertyChangedSignal('AbsolutePosition'):Connect(updateMenuPosition)
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
                    if Input.UserInputType ~= Enum.UserInputType.MouseButton1 then
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
            if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
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
            if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
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
            if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
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
                if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                    while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
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
            if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                local AbsPos, AbsSize = PickerFrameOuter.AbsolutePosition, PickerFrameOuter.AbsoluteSize;

                if Mouse.X < AbsPos.X or Mouse.X > AbsPos.X + AbsSize.X
                    or Mouse.Y < (AbsPos.Y - 20 - 1) or Mouse.Y > AbsPos.Y + AbsSize.Y then

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
        ColorPicker.DisplayFrame = DisplayFrame

        Options[Idx] = ColorPicker;

        return self;
    end;

    function Funcs:AddKeyPicker(Idx, Info)
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
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
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

        ToggleLabel:GetPropertyChangedSignal('AbsolutePosition'):Connect(PlaceModeSelect);

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
                if Input.UserInputType == Enum.UserInputType.MouseButton1 then
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
            if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
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

            if Input.UserInputType == Enum.UserInputType.MouseButton1 then
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

    function Funcs:AddLabel(Text, DoesWrap)
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
            local Y = select(2, Library:GetTextBounds(Text, Library.Font, 14, Vector2.new(TextLabel.AbsoluteSize.X, math.huge)))
            TextLabel.Size = UDim2.new(1, -4, 0, Y)
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

        function Label:SetText(Text)
            if Library:NeedsUIThread() then
                return Library:RunOnUIThread(Label.SetText, Label, Text);
            end;

            TextLabel.Text = Text

            if DoesWrap then
                local Y = select(2, Library:GetTextBounds(Text, Library.Font, 14, Vector2.new(TextLabel.AbsoluteSize.X, math.huge)))
                TextLabel.Size = UDim2.new(1, -4, 0, Y)
            end

            Groupbox:Resize();
        end

        if (not DoesWrap) then
            setmetatable(Label, BaseAddons);
        end

        Groupbox:AddBlank(5);
        Groupbox:Resize();

        return Label;
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
                Obj.Tooltip = Props.Tooltip
            else
                Obj.Text = select(1, ...)
                Obj.Func = select(2, ...)
            end

            assert(type(Obj.Func) == 'function', 'AddButton: `Func` callback is missing.');
        end

        ProcessButtonParams('Button', Button, ...)

        local Groupbox = self;
        local Container = Groupbox.Container;

        local function CreateBaseButton(Button)
            local Outer = Library:Create('Frame', {
                BackgroundColor3 = Color3.new(0, 0, 0);
                BorderColor3 = Color3.new(0, 0, 0);
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

            Library:AddToRegistry(Outer, {
                BorderColor3 = 'Black';
            });

            Library:AddToRegistry(Inner, {
                BackgroundColor3 = 'MainColor';
                BorderColor3 = 'OutlineColor';
            });

            Library:OnHighlight(Outer, Outer,
                { BorderColor3 = 'AccentColor' },
                { BorderColor3 = 'Black' }
            );

            return Outer, Inner, Label
        end

        local function InitEvents(Button)
            local function WaitForEvent(event, timeout, validator)
                local bindable = Instance.new('BindableEvent')
                local connection = event:Once(function(...)

                    if type(validator) == 'function' and validator(...) then
                        bindable:Fire(true)
                    else
                        bindable:Fire(false)
                    end
                end)
                task.delay(timeout, function()
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

                if Input.UserInputType ~= Enum.UserInputType.MouseButton1 then
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

                    local clicked = WaitForEvent(Button.Outer.InputBegan, 0.5, ValidateClick)

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

    function Funcs:AddDivider()
        local Groupbox = self;
        local Container = self.Container

        local Divider = {
            Type = 'Divider',
        }

        Groupbox:AddBlank(2);
        local DividerOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
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

        Library:AddToRegistry(DividerOuter, {
            BorderColor3 = 'Black';
        });

        Library:AddToRegistry(DividerInner, {
            BackgroundColor3 = 'MainColor';
            BorderColor3 = 'OutlineColor';
        });

        Groupbox:AddBlank(9);
        Groupbox:Resize();
    end

    function Funcs:AddInput(Idx, Info)
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
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
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

        Library:OnHighlight(TextBoxOuter, TextBoxOuter,
            { BorderColor3 = 'AccentColor' },
            { BorderColor3 = 'Black' }
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
        end;

        if Textbox.Finished then
            Box.FocusLost:Connect(function(enter)
                if not enter then return end

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

        -- Rounded checkbox: an outlined box whose accent fill grows from the centre when the toggle is on. The
        -- label dims while off, so the active options stand out at a glance.
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

        local ToggleStroke = Library:Create('UIStroke', {
            Color = Library.OutlineColor;
            Thickness = 1;
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border;
            Parent = ToggleOuter;
        });

        Library:AddToRegistry(ToggleStroke, {
            Color = 'OutlineColor';
        });

        local ToggleInner = Library:Create('Frame', {
            AnchorPoint = Vector2.new(0.5, 0.5);
            Position = UDim2.fromScale(0.5, 0.5);
            BackgroundColor3 = Library.AccentColor;
            BorderSizePixel = 0;
            Size = UDim2.fromScale(0, 0);
            ZIndex = 6;
            Parent = ToggleOuter;
        });

        Library:AddToRegistry(ToggleInner, {
            BackgroundColor3 = 'AccentColor';
        });

        Library:Create('UICorner', {
            CornerRadius = UDim.new(0, 2);
            Parent = ToggleInner;
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
            ToggleStroke.Color = Accent and Library.AccentColor or Library.OutlineColor;

            local Reg = Library.RegistryMap[ToggleStroke];
            if Reg then
                Reg.Properties.Color = Accent and 'AccentColor' or 'OutlineColor';
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
            local FillSize = On and UDim2.new(1, -4, 1, -4) or UDim2.fromScale(0, 0);
            local LabelFade = On and 0 or 0.35;

            UpdateStroke();
            Library:ApplyElementGlow(ToggleGlow, Instant);

            if Instant then
                ToggleInner.Size = FillSize;
                ToggleLabel.TextTransparency = LabelFade;
                if ToggleLabelStroke then
                    ToggleLabelStroke.Transparency = LabelFade;
                end;
            else
                Library:CreateTween(ToggleInner, FadeInfo, { Size = FillSize }):Play();
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
        end;

        ToggleRegion.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
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
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(1, -4, 0, 13);
            ZIndex = 5;
            Parent = Container;
        });

        Library:AddToRegistry(SliderOuter, {
            BorderColor3 = 'Black';
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

        Library:OnHighlight(SliderOuter, SliderOuter,
            { BorderColor3 = 'AccentColor' },
            { BorderColor3 = 'Black' }
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

            if Info.Compact then
                DisplayLabel.Text = Info.Text .. ': ' .. Slider.Value .. Suffix
            elseif Info.HideMax then
                DisplayLabel.Text = string.format('%s', Slider.Value .. Suffix)
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
        end;

        SliderInner.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
                while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
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

                    RenderStepped:Wait();
                end;

                Library:AttemptSave();
            end;
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
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(1, -4, 0, 8);
            ZIndex = 5;
            Parent = Container;
        });

        Library:AddToRegistry(BarOuter, {
            BorderColor3 = 'Black';
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
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(1, -4, 0, 20);
            ZIndex = 5;
            Parent = Container;
        });

        Library:AddToRegistry(DropdownOuter, {
            BorderColor3 = 'Black';
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

        Library:OnHighlight(DropdownOuter, DropdownOuter,
            { BorderColor3 = 'AccentColor' },
            { BorderColor3 = 'Black' }
        );

        if type(Info.Tooltip) == 'string' then
            Library:AddToolTip(Info.Tooltip, DropdownOuter)
        end

        local MAX_DROPDOWN_ITEMS = 8;

        local ListOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            ZIndex = 20;
            Visible = false;
            Parent = ScreenGui;
        });

        -- Below the dropdown, flipping above it when the list would run off the bottom of the screen.
        local function RecalculateListPosition()
            local Pos, Size = DropdownOuter.AbsolutePosition, DropdownOuter.AbsoluteSize;
            Library:PlacePopup(ListOuter, Pos.X, Pos.Y + Size.Y + 1, nil, Pos.Y - 1);
        end;

        local function RecalculateListSize(YSize)
            ListOuter.Size = UDim2.fromOffset(DropdownOuter.AbsoluteSize.X / (Library.UIScale or 1), YSize or (MAX_DROPDOWN_ITEMS * 20 + 2))
        end;

        RecalculateListPosition();
        RecalculateListSize();

        DropdownOuter:GetPropertyChangedSignal('AbsolutePosition'):Connect(RecalculateListPosition);

        Library:RegisterPopup(ListOuter);

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
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 21;
            Parent = ListOuter;
        });

        Library:AddToRegistry(ListInner, {
            BackgroundColor3 = 'MainColor';
            BorderColor3 = 'OutlineColor';
        });

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
            ScrollBarImageColor3 = Library.AccentColor,
        });

        Library:AddToRegistry(Scrolling, {
            ScrollBarImageColor3 = 'AccentColor'
        })

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
            local First = math.max(1, math.floor(Scrolling.CanvasPosition.Y / Scale / 20) + 1);
            if not Force and FirstRendered == First then return end;
            FirstRendered = First;
            local Count = math.min(#Dropdown.Values, MAX_DROPDOWN_ITEMS + 2);
            for Index = #Rows + 1, Count do
                local Row = {};
                local Button = Library:Create('Frame', {
                    BackgroundColor3 = Library.MainColor;
                    BorderColor3 = Library.OutlineColor;
                    BorderMode = Enum.BorderMode.Middle;
                    Size = UDim2.new(1, -1, 0, 20);
                    ZIndex = 23;
                    Active = true,
                    Parent = Scrolling;
                });
                Row.Button = Button;

                Library:AddToRegistry(Button, {
                    BackgroundColor3 = 'MainColor';
                    BorderColor3 = 'OutlineColor';
                });

                local ButtonClip = Library:Create('Frame', {
                    BackgroundTransparency = 1;
                    BorderSizePixel = 0;
                    ClipsDescendants = true;
                    Position = UDim2.new(0, 6, 0, 0);
                    Size = UDim2.new(1, -12, 1, 0);
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

                Library:OnHighlight(Button, Button,
                    { BorderColor3 = 'AccentColor', ZIndex = 24 },
                    { BorderColor3 = 'OutlineColor', ZIndex = 23 }
                );

                function Row:UpdateButton()
                    local Selected = Info.Multi and Dropdown.Value[self.Value] or Dropdown.Value == self.Value;
                    ButtonLabel.TextColor3 = Selected and Library.AccentColor or Library.FontColor;
                    Library.RegistryMap[ButtonLabel].Properties.TextColor3 = Selected and 'AccentColor' or 'FontColor';
                end;

                ButtonLabel.InputBegan:Connect(function(Input)
                    if Input.UserInputType == Enum.UserInputType.MouseButton1 then
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
                local Value = Dropdown.Values[ValueIndex];
                Row.Button.Visible = Value ~= nil;
                if Row.Value ~= Value then
                    Row.Scroller:Stop();
                    Row.Value = Value;
                    Row.Label.Text = Value or '';
                end;
                Row.Button.Position = UDim2.fromOffset(0, (ValueIndex - 1) * 20);
                if Value == nil then
                    Row.Scroller.Wanted = false;
                    Row.Scroller:Stop();
                end;
                Row:UpdateButton();
            end;
        end;

        function Dropdown:BuildDropdownList()
            local Count = #Dropdown.Values;
            Scrolling.CanvasSize = UDim2.fromOffset(0, (Count * 20) + 1);
            local Y = math.clamp(Count * 20, 0, MAX_DROPDOWN_ITEMS * 20) + 1;
            RecalculateListSize(Y);
            Dropdown:Display();
            Dropdown:RenderRows(true);
        end;

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
            RecalculateListPosition();
            ListOuter.Visible = true;
            Dropdown:RenderRows(true);
            Library.OpenedFrames[ListOuter] = true;
            -- the list's contents drop in a few px and the arrow turns (Library.Animations)
            ListInner.Position = UDim2.fromOffset(0, Library.Animations and -6 or 0);
            Library:Animate(ListInner, 0.12, { Position = UDim2.new() });
            Library:Animate(DropdownArrow, 0.15, { Rotation = 180 });
        end;

        function Dropdown:CloseDropdown()
            ListOuter.Visible = false;
            Library.OpenedFrames[ListOuter] = nil;
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
        end;

        DropdownOuter.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
                if ListOuter.Visible then
                    Dropdown:CloseDropdown();
                else
                    Dropdown:OpenDropdown();
                end;
            end;
        end);

        Library:GiveSignal(InputService.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                local AbsPos, AbsSize = ListOuter.AbsolutePosition, ListOuter.AbsoluteSize;

                if Mouse.X < AbsPos.X or Mouse.X > AbsPos.X + AbsSize.X
                    or Mouse.Y < (AbsPos.Y - 20 - 1) or Mouse.Y > AbsPos.Y + AbsSize.Y then

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

                if Elem.Type == 'Toggle' and Elem.Value ~= Value then
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

    Library:Animate(NotifyOuter, 0.4, { Size = UDim2.new(0, XSize + 8 + 4, 0, YSize) });

    task.spawn(function()
        task.wait(Time or 5);

        Library:Animate(NotifyOuter, 0.4, { Size = UDim2.new(0, 0, 0, YSize) });

        task.wait(Library.Animations and 0.4 or 0);

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

        Section.Holder.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                RaiseSection(Section);
            end;
        end);
    end;

    return Section.Holder;
end;

function Library:UpdateSectionButtons(Section)
    Section.FoldButton.Text = Section.Folded and '+' or '-';
    Section.PinButton.Visible = Section.Floating;
    Section.PinButton.BackgroundColor3 = Section.Stay and Library.AccentColor or Library.MainColor;

    if Section.Holder then
        Section.Holder.Visible = Section.Floating and (Section.Stay or Library.Toggled);
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
    if not (Library.LayoutFile and isfile and isfile(Library.LayoutFile)) then
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
    for _, Section in next, Library.Sections do
        Section.Stay = true;
        Library:DockSection(Section, Section.DefaultSide, Section.DefaultOrder);
        Library:SetSectionFolded(Section, false);
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

local function DragSection(Section)
    local Start = MousePoint();

    while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
        if (MousePoint() - Start).Magnitude >= SectionDragThreshold then
            break;
        end;

        RenderStepped:Wait();
    end;

    if Library.DraggingSection or not InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
        return; -- a click, not a drag
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

    while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
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

    Section.FoldButton = Library:CreateLabel({
        Position = UDim2.new(1, -16, 0, 2);
        Size = UDim2.fromOffset(14, 16);
        Text = '-';
        TextSize = 14;
        TextXAlignment = Enum.TextXAlignment.Center;
        ZIndex = 12;
        Parent = Info.Inner;
    });

    Section.PinButton = Library:Create('Frame', {
        BackgroundColor3 = Library.AccentColor;
        BorderColor3 = Library.OutlineColor;
        Position = UDim2.new(1, -28, 0, 7);
        Size = UDim2.fromOffset(7, 7);
        Visible = false;
        ZIndex = 12;
        Parent = Info.Inner;
    });

    Library:AddToRegistry(Section.PinButton, {
        BackgroundColor3 = function()
            return Section.Stay and Library.AccentColor or Library.MainColor;
        end;
        BorderColor3 = 'OutlineColor';
    });

    Library:AddToolTip('Stay on screen while the menu is hidden', Section.PinButton);

    Section.FoldButton.InputBegan:Connect(function(Input)
        if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
            Library:SetSectionFolded(Section, not Section.Folded);
            Library:SaveLayout();
        end;
    end);

    Section.PinButton.InputBegan:Connect(function(Input)
        if Input.UserInputType == Enum.UserInputType.MouseButton1 then
            Section.Stay = not Section.Stay;
            Library:UpdateSectionButtons(Section);
            Library:SaveLayout();
        end;
    end);

    Section.Outer.InputBegan:Connect(function(Input)
        if Input.UserInputType ~= Enum.UserInputType.MouseButton1 or Library:MouseIsOverOpenedFrame() then
            return;
        end;

        if (Mouse.Y - Section.Outer.AbsolutePosition.Y) / Library.UIScale <= Section.HeaderHeight then
            DragSection(Section);
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

-- Delay (optional): seconds before the tween starts; a tree being shown goes transparent at once and waits.
function Library:FadeTree(Root, Visible, Time, Rest, Delay)
    Rest = Rest or {};
    local Info = TweenInfo.new(Time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, Delay or 0);

    local List = Root:GetDescendants();
    table.insert(List, 1, Root); -- the root as well: a label row is itself the thing to fade

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
                TweenService:Create(Desc, Info, Goal):Play();
            end;
        end;
    end;

    return Rest;
end;

function Library:RestoreTree(Rest)
    for Desc, Saved in next, Rest or {} do
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

    if Config.Center then
        Config.AnchorPoint = Vector2.new(0.5, 0.5)
        Config.Position = UDim2.fromScale(0.5, 0.5)
    end

    local Window = {
        Tabs = {};
    };

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

    Library:MakeDraggable(Outer, 25);

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

    local WindowLabel = Library:CreateLabel({
        Position = UDim2.new(0.5, 0, 0, 0);
        Size = UDim2.new(0, 0, 0, 25);
        Text = Config.Title or '';
        TextXAlignment = Enum.TextXAlignment.Center;
        ZIndex = 1;
        Parent = Inner;
    });

    local MainSectionOuter = Library:Create('Frame', {
        BackgroundColor3 = Library.BackgroundColor;
        BorderColor3 = Library.OutlineColor;
        Position = UDim2.new(0, 8, 0, 25);
        Size = UDim2.new(1, -16, 1, -33);
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

    local TabArea = Library:Create('Frame', {
        BackgroundTransparency = 1;
        Position = UDim2.new(0, 8, 0, 8);
        Size = UDim2.new(1, -16, 0, 21);
        ZIndex = 1;
        Parent = MainSectionInner;
    });

    local TabListLayout = Library:Create('UIListLayout', {
        Padding = UDim.new(0, Config.TabPadding);
        FillDirection = Enum.FillDirection.Horizontal;
        SortOrder = Enum.SortOrder.LayoutOrder;
        Parent = TabArea;
    });

    local TabContainer = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderColor3 = Library.OutlineColor;
        Position = UDim2.new(0, 8, 0, 30);
        Size = UDim2.new(1, -16, 1, -38);
        ClipsDescendants = true; -- tab content slides in from the sides (Tab:ShowTab)
        ZIndex = 2;
        Parent = MainSectionInner;
    });
    

    Library:AddToRegistry(TabContainer, {
        BackgroundColor3 = 'MainColor';
        BorderColor3 = 'OutlineColor';
    });

    function Window:SetWindowTitle(Title)
        WindowLabel.Text = Title;
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

        -- Underline tab: the name (dimmed while inactive) over an accent bar that opens on the active tab.
        local TabButton = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Size = UDim2.new(0, TabButtonWidth + 8 + 4, 1, 0);
            ZIndex = 1;
            Parent = TabArea;
        });

        Library:AddToRegistry(TabButton, {
            BackgroundColor3 = 'BackgroundColor';
        });

        local TabButtonLabel = Library:CreateLabel({
            Position = UDim2.new(0, 0, 0, 0);
            Size = UDim2.new(1, 0, 1, -3);
            Text = Name;
            TextTransparency = 0.45;
            ZIndex = 1;
            Parent = TabButton;
        });

        local TabLabelStroke = TabButtonLabel:FindFirstChildOfClass('UIStroke');
        if TabLabelStroke then
            TabLabelStroke.Transparency = 0.45;
        end;

        local TabUnderline = Library:Create('Frame', {
            AnchorPoint = Vector2.new(0.5, 1);
            Position = UDim2.new(0.5, 0, 1, 0);
            BackgroundColor3 = Library.AccentColor;
            BorderSizePixel = 0;
            Size = UDim2.new(0, 0, 0, 2);
            ZIndex = 2;
            Parent = TabButton;
        });

        Library:AddToRegistry(TabUnderline, {
            BackgroundColor3 = 'AccentColor';
        });

        local TabTweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
        local TabActive = false;

        local function FadeTabLabel(Transparency)
            Library:CreateTween(TabButtonLabel, TabTweenInfo, { TextTransparency = Transparency }):Play();
            if TabLabelStroke then
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

        local Blocker = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderSizePixel = 0;
            Position = UDim2.new(0, 0, 1, 0);
            Size = UDim2.new(1, 0, 0, 1);
            BackgroundTransparency = 1;
            ZIndex = 3;
            Parent = TabButton;
        });

        Library:AddToRegistry(Blocker, {
            BackgroundColor3 = 'MainColor';
        });

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
            Position = UDim2.new(0, 8 - 1, 0, 8 - 1);
            Size = UDim2.new(0.5, -12 + 2, 1, -14);
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
            Position = UDim2.new(0.5, 4 + 1, 0, 8 - 1);
            Size = UDim2.new(0.5, -12 + 2, 1, -14);
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
            Side:WaitForChild('UIListLayout'):GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
                Side.CanvasSize = UDim2.fromOffset(0, Side.UIListLayout.AbsoluteContentSize.Y);
            end);
        end;

        -- what a section needs to find its way back (see Library:RegisterSection)
        local SectionTab = { Name = Name, LeftSide = LeftSide, RightSide = RightSide, Frame = TabFrame, WindowOuter = Outer };
        local SectionCount, TabboxCount = 0, 0;

        local function NextSectionOrder()
            SectionCount = SectionCount + 1;
            return SectionCount * 10;
        end;

        -- Switching tabs (Library.Animations): the new content slides in from the side of the tab that was clicked
        -- (a tab to the right comes in from the right) while fading in, and the old one slides out the other way
        -- fading out. Tab.FadeRest holds the old tab's real transparencies until it is out of sight.
        local SLIDE_PX, SLIDE_TIME = 40, 0.22;

        function Tab:ShowTab()
            local Previous = Window.ActiveTab;
            local Direction = (Previous and Previous ~= Tab) and (Tab.Index > Previous.Index and 1 or -1) or 0;
            Window.SlideDirection = Direction;

            for _, Other in next, Window.Tabs do
                if Other ~= Tab then
                    Other:HideTab();
                end;
            end;

            Window.ActiveTab = Tab;
            TabActive = true;
            FadeTabLabel(0);
            Library:CreateTween(TabUnderline, TabTweenInfo, { Size = UDim2.new(1, -6, 0, 2) }):Play();

            Tab.FadeToken = {}; -- cancels this tab's own unfinished hide
            TabFrame.Visible = true;

            if Library.Animations and Direction ~= 0 then
                TabFrame.Position = UDim2.fromOffset(Direction * SLIDE_PX, 0);
                Library:FadeTree(TabFrame, true, SLIDE_TIME, Tab.FadeRest);
                Library:Animate(TabFrame, SLIDE_TIME, { Position = UDim2.new() });
            else
                Library:RestoreTree(Tab.FadeRest);
                TabFrame.Position = UDim2.new();
            end;

            Tab.FadeRest = nil;
        end;

        function Tab:HideTab()
            local WasActive = TabActive;
            TabActive = false;
            FadeTabLabel(0.45);
            Library:CreateTween(TabUnderline, TabTweenInfo, { Size = UDim2.new(0, 0, 0, 2) }):Play();

            if not (WasActive and Library.Animations and (Window.SlideDirection or 0) ~= 0) then
                TabFrame.Visible = false;
                return;
            end;

            local Token = {};
            Tab.FadeToken = Token;
            Tab.FadeRest = Library:FadeTree(TabFrame, false, SLIDE_TIME, Tab.FadeRest);
            Library:Animate(TabFrame, SLIDE_TIME, { Position = UDim2.fromOffset(-Window.SlideDirection * SLIDE_PX, 0) });

            task.delay(SLIDE_TIME + 0.02, function()
                if Tab.FadeToken ~= Token then
                    return; -- shown again meanwhile
                end;

                TabFrame.Visible = false;
                TabFrame.Position = UDim2.new();
                Library:RestoreTree(Tab.FadeRest);
                Tab.FadeRest = nil;
            end);
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
                Position = UDim2.new(0, 4, 0, 20);
                Size = UDim2.new(1, -4, 1, -20);
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

            local Highlight = Library:Create('Frame', {
                BackgroundColor3 = Library.AccentColor;
                BorderSizePixel = 0;
                Size = UDim2.new(1, 0, 0, 2);
                ZIndex = 10;
                Parent = BoxInner;
            });

            Library:AddToRegistry(Highlight, {
                BackgroundColor3 = 'AccentColor';
            });

            -- Header geometry: 2 px accent line, tab strip, 1 px divider, then the content.
            local TabStripTop = 3;
            local TabStripHeight = 20;
            local DividerY = TabStripTop + TabStripHeight;
            local ContentTop = DividerY + 4;

            local TabboxButtons = Library:Create('Frame', {
                BackgroundTransparency = 1;
                Position = UDim2.new(0, 0, 0, TabStripTop);
                Size = UDim2.new(1, -18, 0, TabStripHeight); -- room for the fold button
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
            Section.FoldedHeight = ContentTop + 2;

            Library:Create('UIListLayout', {
                FillDirection = Enum.FillDirection.Horizontal;
                HorizontalAlignment = Enum.HorizontalAlignment.Left;
                SortOrder = Enum.SortOrder.LayoutOrder;
                Parent = TabboxButtons;
            });

            -- Thin divider under the tab strip; the active tab's accent underline sits on top of it.
            local TabboxDivider = Library:Create('Frame', {
                BackgroundColor3 = Library.OutlineColor;
                BorderSizePixel = 0;
                Position = UDim2.new(0, 4, 0, DividerY);
                Size = UDim2.new(1, -8, 0, 1);
                ZIndex = 5;
                Parent = BoxInner;
            });

            Library:AddToRegistry(TabboxDivider, {
                BackgroundColor3 = 'OutlineColor';
            });

            function Tabbox:AddTab(Name)
                local Tab = {};
                local TabInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
                local Active = false;

                -- Underline tabs: no boxes, just the name (dimmed while inactive) and an accent bar under the
                -- active one that slides open to the width of its text.
                local Button = Library:Create('Frame', {
                    BackgroundTransparency = 1;
                    BorderSizePixel = 0;
                    Size = UDim2.new(0.5, 0, 1, 0);
                    ZIndex = 6;
                    Parent = TabboxButtons;
                });

                local ButtonLabel = Library:CreateLabel({
                    Size = UDim2.new(1, 0, 1, -2);
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

                local UnderlineWidth = Library:GetTextBounds(Name, Library.Font, 14) + 10;

                -- sits on the divider line, directly under the tab name
                local Underline = Library:Create('Frame', {
                    AnchorPoint = Vector2.new(0.5, 1);
                    Position = UDim2.new(0.5, 0, 1, 0);
                    BackgroundColor3 = Library.AccentColor;
                    BorderSizePixel = 0;
                    Size = UDim2.new(0, 0, 0, 2);
                    ZIndex = 8;
                    Parent = Button;
                });

                Library:AddToRegistry(Underline, {
                    BackgroundColor3 = 'AccentColor';
                });

                local function FadeLabel(Transparency)
                    Library:CreateTween(ButtonLabel, TabInfo, { TextTransparency = Transparency }):Play();
                    if ButtonLabelStroke then
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
                    Position = UDim2.new(0, 4, 0, ContentTop);
                    Size = UDim2.new(1, -4, 1, -ContentTop);
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

                    Active = true;
                    Tabbox.ActiveTab = Tab;
                    Container.Visible = not Section.Folded;
                    FadeLabel(0);
                    local Width = math.min(UnderlineWidth, math.max(Button.AbsoluteSize.X - 6, 0));
                    Library:CreateTween(Underline, TabInfo, { Size = UDim2.new(0, Width > 0 and Width or UnderlineWidth, 0, 2) }):Play();

                    Tab:Resize();
                end;

                function Tab:Hide()
                    Active = false;
                    Container.Visible = false;
                    FadeLabel(0.45);
                    Library:CreateTween(Underline, TabInfo, { Size = UDim2.new(0, 0, 0, 2) }):Play();
                end;

                function Tab:Resize()
                    local TabCount = 0;

                    for _, Tab in next, Tabbox.Tabs do
                        TabCount = TabCount + 1;
                    end;

                    for _, Button in next, TabboxButtons:GetChildren() do
                        if not Button:IsA('UIListLayout') then
                            Button.Size = UDim2.new(1 / TabCount, 0, 1, 0);
                        end;
                    end;

                    if Section.Animating then
                        return; -- SetSectionFolded is easing the height and resizes once it is done
                    end;

                    if Section.Folded then
                        BoxOuter.Size = UDim2.new(1, 0, 0, ContentTop + 2);
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
                    if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
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
            if Input.UserInputType == Enum.UserInputType.MouseButton1 then
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
    local FadeComplete = true;
    local CursorRunning = false;

    -- Scales the whole window slightly while it fades, which reads a lot smoother than a flat alpha fade.
    local WindowScale = Library:Create('UIScale', {
        Scale = Library.UIScale;
        Parent = Outer;
    });

    local function GetFadeProperties(Desc)
        if Desc:IsA('ImageLabel') then
            return { 'ImageTransparency', 'BackgroundTransparency' };
        elseif Desc:IsA('TextLabel') or Desc:IsA('TextBox') then
            return { 'TextTransparency', 'BackgroundTransparency' };
        elseif Desc:IsA('Frame') or Desc:IsA('ScrollingFrame') then
            return { 'BackgroundTransparency' };
        elseif Desc:IsA('UIStroke') then
            return { 'Transparency' };
        end;
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

        -- Hiding from a fully shown menu: re-read every element's current transparency so values that
        -- changed while it was open (e.g. the tab underline) are what gets restored on the next show.
        local RefreshCache = (not Toggled) and FadeComplete and Outer.Visible;
        FadeComplete = false;

        if Toggled then
            Outer.Visible = true;

            if FromHidden then
                WindowScale.Scale = 0.95 * Library.UIScale;
            end;

            RunCursor();
        else
            -- Close any dropdown / color picker popups so they don't linger after the window is gone.
            for Frame in next, Library.OpenedFrames do
                Frame.Visible = false;
                Library.OpenedFrames[Frame] = nil;
            end;
        end;

        Play(WindowScale, { Scale = (Toggled and 1 or 0.95) * Library.UIScale });

        local Targets = Outer:GetDescendants();
        table.insert(Targets, Outer);

        for _, Desc in next, Targets do
            local Properties = GetFadeProperties(Desc);

            if not Properties then
                continue;
            end;

            local Cache = TransparencyCache[Desc];

            if (not Cache) then
                Cache = {};
                TransparencyCache[Desc] = Cache;
            end;

            local Goal = {};

            for _, Prop in next, Properties do
                if Cache[Prop] == nil or RefreshCache then
                    Cache[Prop] = Desc[Prop];
                end;

                if Cache[Prop] == 1 then
                    continue;
                end;

                if Toggled and FromHidden then
                    Desc[Prop] = 1;
                end;

                Goal[Prop] = Toggled and Cache[Prop] or 1;
            end;

            if next(Goal) then
                Play(Desc, Goal);
            end;
        end;

        task.delay(FadeTime, function()
            if Generation ~= ToggleGeneration then
                return;
            end;

            Outer.Visible = Toggled;
            FadeComplete = true;
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
		local theme = 'Default'
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

	function ThemeManager:CreateThemeManager(groupbox)
		groupbox:AddLabel('Background color'):AddColorPicker('BackgroundColor', { Default = self.Library.BackgroundColor });
		groupbox:AddLabel('Main color')	:AddColorPicker('MainColor', { Default = self.Library.MainColor });
		groupbox:AddLabel('Accent color'):AddColorPicker('AccentColor', { Default = self.Library.AccentColor });
		groupbox:AddLabel('Outline color'):AddColorPicker('OutlineColor', { Default = self.Library.OutlineColor });
		groupbox:AddLabel('Font color')	:AddColorPicker('FontColor', { Default = self.Library.FontColor });

		-- built-in accent animation; a client that made its own toggles (kenya_client) keeps them
		if not Toggles.RainbowAccent and not Toggles.GradientAccent then
			groupbox:AddDivider()
			groupbox:AddToggle('RainbowAccent', { Text = 'Animate accent', Default = true })
			groupbox:AddToggle('GradientAccent', { Text = 'Gradient accent', Default = true, Tooltip = 'Spread the accent across the window instead of one flat color' })
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

		groupbox:AddDivider()
		groupbox:AddDropdown('ThemeManager_ThemeList', { Text = 'Theme list', Values = ThemesArray, Default = 1 })

		groupbox:AddButton('Set as default', function()
			self:SaveDefault(Options.ThemeManager_ThemeList.Value)
			self.Library:Notify(string.format('Set default theme to %q', Options.ThemeManager_ThemeList.Value))
		end)

		Options.ThemeManager_ThemeList:OnChanged(function()
			self:ApplyTheme(Options.ThemeManager_ThemeList.Value)
		end)

		groupbox:AddDivider()
		groupbox:AddInput('ThemeManager_CustomThemeName', { Text = 'Custom theme name' })
		groupbox:AddDropdown('ThemeManager_CustomThemeList', { Text = 'Custom themes', Values = self:ReloadCustomThemes(), AllowNull = true, Default = 1 })
		groupbox:AddDivider()
		
		groupbox:AddButton('Save theme', function() 
			self:SaveCustomTheme(Options.ThemeManager_CustomThemeName.Value)

			Options.ThemeManager_CustomThemeList:SetValues(self:ReloadCustomThemes())
			Options.ThemeManager_CustomThemeList:SetValue(nil)
		end):AddButton('Load theme', function() 
			self:ApplyTheme(Options.ThemeManager_CustomThemeList.Value) 
		end)

		groupbox:AddButton('Refresh list', function()
			Options.ThemeManager_CustomThemeList:SetValues(self:ReloadCustomThemes())
			Options.ThemeManager_CustomThemeList:SetValue(nil)
		end)

		groupbox:AddButton('Set as default', function()
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

	function ThemeManager:ApplyToTab(tab)
		assert(self.Library, 'Must set ThemeManager.Library first!')
		local groupbox = self:CreateGroupBox(tab)
		self:CreateThemeManager(groupbox)
	end

	function ThemeManager:ApplyToGroupbox(groupbox)
		assert(self.Library, 'Must set ThemeManager.Library first!')
		self:CreateThemeManager(groupbox)
	end

	-- Kenya Client style Settings: Menu groupbox (keybind, scale, fade, watermark / keybind HUD, unload)
	-- and Accent groupbox (animate, gradient, direction, custom colors). Call before ApplyToTab so the
	-- built-in accent toggles there are skipped. Returns the Menu and Accent groupboxes.
	function ThemeManager:BuildMenuSection(tab)
		local MenuGroup = tab:AddLeftGroupbox('Menu')

		MenuGroup:AddLabel('Menu bind'):AddKeyPicker('MenuKeybind', { Default = 'End', NoUI = true, Text = 'Menu keybind' })
		MenuGroup:AddSlider('UIScale', { Text = 'UI scale', Default = 1, Min = 0.5, Max = 2, Rounding = 2, Suffix = 'x', HideMax = true, Tooltip = 'Size of the menu and its popups' })
		MenuGroup:AddToggle('UIAnimations', { Text = 'Animations', Default = true, Tooltip = 'Eased fades, slides and hovers. Off: everything changes instantly', Callback = function(Value) Library.Animations = Value end })
		MenuGroup:AddSlider('MenuFadeTime', { Text = 'Open / close fade time', Default = 0.25, Min = 0, Max = 1, Rounding = 2, Suffix = 's', HideMax = true })
		MenuGroup:AddToggle('ShowWatermark', { Text = 'Show watermark', Default = true, Tooltip = 'FPS / ping bar at the top of the screen' })
		MenuGroup:AddToggle('ShowKeybinds', { Text = 'Show keybind list', Default = true, Tooltip = 'HUD listing active keybinds (hidden while empty)' })
		MenuGroup:AddToggle('WindowGlow', { Text = 'Window glow', Default = false, Tooltip = 'Soft accent-colored glow around the menu' })
		local GlowBox = MenuGroup:AddDependencyBox()
		GlowBox:AddSlider('GlowSize', { Text = 'Glow size', Default = 30, Min = 5, Max = 100, Rounding = 0, Suffix = 'px', HideMax = true })
		GlowBox:AddSlider('GlowStrength', { Text = 'Glow strength', Default = 50, Min = 5, Max = 100, Rounding = 0, Suffix = '%', HideMax = true })
		GlowBox:SetupDependencies({ { Toggles.WindowGlow, true } })
		MenuGroup:AddToggle('ElementGlow', { Text = 'Element glow', Default = false, Tooltip = 'Glow under switched-on toggles, slider fills and color swatches' })
		local ElementGlowBox = MenuGroup:AddDependencyBox()
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
		MenuGroup:AddButton({ Text = 'Reset layout', Func = function() Library:ResetLayout() end, Tooltip = 'Drag a section by its title to move it, or drop it outside the menu to keep it on screen. This puts every section back' })
		MenuGroup:AddButton('Unload', function() Library:Unload() end)

		local AccentGroup = tab:AddRightGroupbox('Accent')

		AccentGroup:AddToggle('RainbowAccent', { Text = 'Animate accent', Default = true, Tooltip = 'Rainbow: cycle the hue. Custom colors: flow them across the menu' })
		AccentGroup:AddToggle('GradientAccent', { Text = 'Gradient accent', Default = true, Tooltip = 'Spread the accent across the window instead of one flat color' })
		AccentGroup:AddSlider('RainbowSpeed', { Text = 'Animation speed', Default = 1, Min = 0.1, Max = 5, Rounding = 1, Suffix = 'x', HideMax = true })

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
