

do  local ui =  game:GetService("CoreGui"):FindFirstChild("MakiLib")  if ui then ui:Destroy() end end
local logo = 12484979282
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local LocalPlayer = game:GetService("Players").LocalPlayer
local Mouse = LocalPlayer:GetMouse()

_G.Color = Color3.fromRGB(255, 0, 98)

local function Tween(instance, properties,style,wa)
	if style == nil or "" then
		return Back
	end
	tween:Create(instance,TweenInfo.new(wa,Enum.EasingStyle[style]),{properties}):Play()
end

local ActualTypes = {
	RoundFrame = "ImageLabel",
	Shadow = "ImageLabel",
	Circle = "ImageLabel",
	CircleButton = "ImageButton",
	Frame = "Frame",
	Label = "TextLabel",
	Button = "TextButton",
	SmoothButton = "ImageButton",
	Box = "TextBox",
	ScrollingFrame = "ScrollingFrame",
	Menu = "ImageButton",
	NavBar = "ImageButton"
}

local Properties = {
	RoundFrame = {
		BackgroundTransparency = 1,
		Image = "http://www.roblox.com/asset/?id=5554237731",
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(3,3,297,297)
	},
	SmoothButton = {
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Image = "http://www.roblox.com/asset/?id=5554237731",
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(3,3,297,297)
	},
	Shadow = {
		Name = "Shadow",
		BackgroundTransparency = 1,
		Image = "http://www.roblox.com/asset/?id=5554236805",
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(23,23,277,277),
		Size = UDim2.fromScale(1,1) + UDim2.fromOffset(30,30),
		Position = UDim2.fromOffset(-15,-15)
	},
	Circle = {
		BackgroundTransparency = 1,
		Image = "http://www.roblox.com/asset/?id=5554831670"
	},
	CircleButton = {
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Image = "http://www.roblox.com/asset/?id=5554831670"
	},
	Frame = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1,1)
	},
	Label = {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(5,0),
		Size = UDim2.fromScale(1,1) - UDim2.fromOffset(5,0),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left
	},
	Button = {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(5,0),
		Size = UDim2.fromScale(1,1) - UDim2.fromOffset(5,0),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left
	},
	Box = {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(5,0),
		Size = UDim2.fromScale(1,1) - UDim2.fromOffset(5,0),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left
	},
	ScrollingFrame = {
		BackgroundTransparency = 1,
		ScrollBarThickness = 0,
		CanvasSize = UDim2.fromScale(0,0),
		Size = UDim2.fromScale(1,1)
	},
	Menu = {
		Name = "More",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Image = "http://www.roblox.com/asset/?id=5555108481",
		Size = UDim2.fromOffset(20,20),
		Position = UDim2.fromScale(1,0.5) - UDim2.fromOffset(25,10)
	},
	NavBar = {
		Name = "SheetToggle",
		Image = "http://www.roblox.com/asset/?id=5576439039",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(20,20),
		Position = UDim2.fromOffset(5,5),
		AutoButtonColor = false
	}
}

local Types = {
	"RoundFrame",
	"Shadow",
	"Circle",
	"CircleButton",
	"Frame",
	"Label",
	"Button",
	"SmoothButton",
	"Box",
	"ScrollingFrame",
	"Menu",
	"NavBar"
}

function FindType(String)
	for _, Type in next, Types do
		if Type:sub(1, #String):lower() == String:lower() then
			return Type
		end
	end
	return false
end

local Objects = {}

function Objects.new(Type)
	local TargetType = FindType(Type)
	if TargetType then
		local NewImage = Instance.new(ActualTypes[TargetType])
		if Properties[TargetType] then
			for Property, Value in next, Properties[TargetType] do
				NewImage[Property] = Value
			end
		end
		return NewImage
	else
		return Instance.new(Type)
	end
end

local function GetXY(GuiObject)
	local Max, May = GuiObject.AbsoluteSize.X, GuiObject.AbsoluteSize.Y
	local Px, Py = math.clamp(Mouse.X - GuiObject.AbsolutePosition.X, 0, Max), math.clamp(Mouse.Y - GuiObject.AbsolutePosition.Y, 0, May)
	return Px/Max, Py/May
end

local function CircleAnim(GuiObject, EndColour, StartColour)
	local PX, PY = GetXY(GuiObject)
	local Circle = Objects.new("Circle")
	Circle.Size = UDim2.fromScale(0,0)
	Circle.Position = UDim2.fromScale(PX,PY)
	Circle.ImageColor3 = StartColour or GuiObject.ImageColor3
	Circle.ZIndex = 200
	Circle.Parent = GuiObject
	local Size = GuiObject.AbsoluteSize.X
	TweenService:Create(Circle, TweenInfo.new(0.4), {Position = UDim2.fromScale(PX,PY) - UDim2.fromOffset(Size/2,Size/2), ImageTransparency = 1, ImageColor3 = EndColour, Size = UDim2.fromOffset(Size,Size)}):Play()
	spawn(function()
		wait(0.4)
		Circle:Destroy()
	end)
end


local function MakeDraggable(topbarobject, object)
    local Dragging = nil
    local DragInput = nil	
    local DragStart = nil
    local StartPosition = nil

    local function Update(input)
        local Delta = input.Position - DragStart
        local pos =
            UDim2.new(
                StartPosition.X.Scale,
                StartPosition.X.Offset + Delta.X,
                StartPosition.Y.Scale,
                StartPosition.Y.Offset + Delta.Y
            )
        local Tween = TweenService:Create(object, TweenInfo.new(0.2), {Position = pos})
        Tween:Play()
    end

    topbarobject.InputBegan:Connect(
        function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                Dragging = true
                DragStart = input.Position
                StartPosition = object.Position

                input.Changed:Connect(
                    function()
                        if input.UserInputState == Enum.UserInputState.End then
                            Dragging = false
                        end
                    end
                )
            end
        end
    )

    topbarobject.InputChanged:Connect(
        function(input)
            if
                input.UserInputType == Enum.UserInputType.MouseMovement or
                input.UserInputType == Enum.UserInputType.Touch
            then
                DragInput = input
            end
        end
    )

    UserInputService.InputChanged:Connect(
        function(input)
            if input == DragInput and Dragging then
                Update(input)
            end
        end
    )
end


local Lib = {}

function Lib:Window(text)
    local MakiLib = Instance.new("ScreenGui")
    local Main = Instance.new("Frame")
    local UICornerMain = Instance.new("UICorner")
    local Top = Instance.new("Frame")
    local UICornerTop = Instance.new("UICorner")
    local logo = Instance.new("ImageLabel")
    local Tab = Instance.new("Frame")
    local ScrollingTab = Instance.new("ScrollingFrame")
    local TabList = Instance.new("UIListLayout")
    local UIPadding = Instance.new("UIPadding")
    local NameReal = Instance.new("TextLabel")
    local ImageTab = Instance.new("ImageLabel")
    local MainPage = Instance.new("Frame")
    local UICornerPage = Instance.new("UICorner")
    local PageFolder = Instance.new("Folder")
    local UIPageLayout = Instance.new("UIPageLayout")
    local Tabtoggle = false
    local abc = false

    MakiLib.Name = "MakiLib"
    MakiLib.Parent = game.CoreGui
    MakiLib.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    
    Main.Name = "Main"
    Main.Parent = MakiLib
    Main.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    Main.BorderSizePixel = 0
    Main.ClipsDescendants = true
    Main.Position = UDim2.new(0.240740746, 0, 0.286585361, 0)
    Main.Size = UDim2.new(0, 0, 0, 0)

    pcall(Main:TweenSize(UDim2.new(0, 700, 0, 380),"Out","Back",0.7,true))

    UICornerMain.CornerRadius = UDim.new(0, 4)
    UICornerMain.Name = "UICornerMain"
    UICornerMain.Parent = Main
    
    Top.Name = "Top"
    Top.Parent = Main
    Top.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    Top.BorderSizePixel = 0
    Top.Size = UDim2.new(0, 700, 0, 38)
    
    UICornerTop.CornerRadius = UDim.new(0, 4)
    UICornerTop.Name = "UICornerTop"
    UICornerTop.Parent = Top
    
    NameReal.Name = "NameReal"
    NameReal.Parent = Top
    NameReal.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    NameReal.BackgroundTransparency = 1.000
    NameReal.Position = UDim2.new(0.0900000036, 0, 0, 0)
    NameReal.Size = UDim2.new(0, 170, 0, 38)
    NameReal.Font = Enum.Font.GothamBold
    NameReal.Text = text
    NameReal.TextColor3 = Color3.fromRGB(255,255,255)
    NameReal.TextSize = 16.000
    NameReal.TextXAlignment = Enum.TextXAlignment.Left
    
    ImageTab.Name = "ImageTab"
    ImageTab.Parent = Top
    ImageTab.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    ImageTab.BackgroundTransparency = 1.000
    ImageTab.Position = UDim2.new(0.0157142859, 0, 0.105263151, 0)
    ImageTab.Size = UDim2.new(0, 30, 0, 30)
    ImageTab.Image = "http://www.roblox.com/asset/?id=11271966220"
    
    local TabButtonnnn = Instance.new("TextButton")
    TabButtonnnn.Parent = ImageTab
    TabButtonnnn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    TabButtonnnn.BackgroundTransparency = 1.000
    TabButtonnnn.Size = UDim2.new(0, 30, 0, 30)
    TabButtonnnn.Font = Enum.Font.SourceSans
    TabButtonnnn.Text = ""
    TabButtonnnn.TextColor3 = Color3.fromRGB(0, 0, 0)
    TabButtonnnn.TextSize = 14.000
    
    Tab.Name = "Tab"
    Tab.Parent = Main
    Tab.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    Tab.BorderSizePixel = 0
    Tab.ClipsDescendants = true
    Tab.Position = UDim2.new(0, 0, 0.100000001, 0)
    Tab.Size = UDim2.new(0, 0, 0, 342)
    Tab.ZIndex = 2

    ScrollingTab.Name = "ScrollingTab"
    ScrollingTab.Parent = Tab
    ScrollingTab.Active = true
    ScrollingTab.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    ScrollingTab.BackgroundTransparency = 1.000
    ScrollingTab.BorderSizePixel = 0
    ScrollingTab.Size = UDim2.new(0, 247, 0, 342)
    ScrollingTab.ScrollBarThickness = 4
    ScrollingTab.CanvasSize = UDim2.new(0, 0, 0, 0)
    ScrollingTab.ClipsDescendants = true

    TabList.Name = "TabList"
    TabList.Parent = ScrollingTab
    TabList.SortOrder = Enum.SortOrder.LayoutOrder
    TabList.Padding = UDim.new(0, 3)

    UIPadding.Parent = ScrollingTab
    UIPadding.PaddingTop = UDim.new(0, 5)
    
    MainPage.Name = "MainPage"
    MainPage.Parent = Main
    MainPage.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    MainPage.BorderSizePixel = 0
    MainPage.Position = UDim2.new(0.0157142859, 0, 0.126315787, 0)
    MainPage.Size = UDim2.new(0, 677, 0, 318)
    MainPage.ClipsDescendants = true
    
    UICornerPage.CornerRadius = UDim.new(0, 4)
    UICornerPage.Name = "UICornerPage"
    UICornerPage.Parent = MainPage
    
    PageFolder.Name = "PageFolder"
    PageFolder.Parent = MainPage
    
    UIPageLayout.Parent = PageFolder
    UIPageLayout.SortOrder = Enum.SortOrder.LayoutOrder
    UIPageLayout.EasingDirection = Enum.EasingDirection.InOut
    UIPageLayout.EasingStyle = Enum.EasingStyle.Quad
    UIPageLayout.GamepadInputEnabled = false
    UIPageLayout.ScrollWheelInputEnabled = false
    UIPageLayout.TouchInputEnabled = false
    UIPageLayout.TweenTime = 0.300

    local Black = Instance.new("Frame")
    Black.Name = "Black"
    Black.Parent = Main
    Black.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    Black.BackgroundTransparency = .3
    Black.BorderSizePixel = 0
    Black.Position = UDim2.new(0, 0, 0.086585361, 0)
    Black.Size = UDim2.new(0, 0, 0, 342)
    
    UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.RightControl then
			if uihide == false then
				uihide = true
                pcall(Main:TweenSize(UDim2.new(0, 0, 0, 0),"In","Quad",0.7,true))
			else
				uihide = false
				pcall(Main:TweenSize(UDim2.new(0, 700, 0, 380),"Out","Back",0.7,true))
			end
		end
	end)
    
    TabButtonnnn.MouseButton1Click:Connect(function()
        if Tabtoggle == false then
            Tabtoggle = true
            TweenService:Create(
                Tab,
                TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                {Size = UDim2.new(0, 247, 0, 342)}
            ):Play()
            TweenService:Create(
                Black,
                TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                {Size = UDim2.new(0, 700, 0, 342)}
            ):Play()
            TweenService:Create(
                ImageTab,
                TweenInfo.new(0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
                {ImageColor3 = _G.Color}
            ):Play()
        else
            Tabtoggle = false
            TweenService:Create(
                Tab,
                TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                {Size = UDim2.new(0, 0, 0, 342)}
            ):Play()
            TweenService:Create(
                Black,
                TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                {Size = UDim2.new(0, 0, 0, 342)}
            ):Play()
            TweenService:Create(
                ImageTab,
                TweenInfo.new(0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
                {ImageColor3 = Color3.fromRGB(255, 255, 255)}
            ):Play()
        end
    end)

    local Ui = {}

    function Ui:Tab(text)
        local TabFrame = Instance.new("Frame")
        local Tabb = Instance.new("Frame")
        local UICornerTabb = Instance.new("UICorner")
        local UIGradientTabb = Instance.new("UIGradient")
        local TextTab = Instance.new("TextLabel")
        local TextButton = Instance.new("TextButton")
        local MainFramePage = Instance.new("Frame")
        local UICornerMainFramePage = Instance.new("UICorner")

        TabFrame.Name = "TabFrame"
        TabFrame.Parent = ScrollingTab
        TabFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        TabFrame.BackgroundTransparency = 1.000
        TabFrame.Size = UDim2.new(0, 247, 0, 40)
        
        Tabb.Name = "Tabb"
        Tabb.Parent = TabFrame
        Tabb.BackgroundColor3 = _G.Color
        Tabb.ClipsDescendants = true
        Tabb.Position = UDim2.new(0.0445344113, 0, 0.125, 0)
        Tabb.Size = UDim2.new(0, 222, 0, 30)
        
        UICornerTabb.CornerRadius = UDim.new(0, 4)
        UICornerTabb.Name = "UICornerTabb"
        UICornerTabb.Parent = Tabb
        
        TextTab.Name = "TextTab"
        TextTab.Parent = Tabb
        TextTab.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        TextTab.BackgroundTransparency = 1.000
        TextTab.Size = UDim2.new(0, 222, 0, 30)
        TextTab.Font = Enum.Font.GothamBold
        TextTab.Text = text
        TextTab.TextColor3 = Color3.fromRGB(255, 255, 255)
        TextTab.TextSize = 15.000
        
        TextButton.Parent = TabFrame
        TextButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        TextButton.BackgroundTransparency = 1.000
        TextButton.Size = UDim2.new(0, 247, 0, 40)
        TextButton.Font = Enum.Font.SourceSans
        TextButton.Text = ""
        TextButton.TextColor3 = Color3.fromRGB(0, 0, 0)
        TextButton.TextSize = 14.000
        
        MainFramePage.Name = "MainFramePage"
        MainFramePage.Parent = PageFolder
        MainFramePage.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
        MainFramePage.BorderSizePixel = 0
        MainFramePage.Position = UDim2.new(0.0925237387, 0, 0.132605091, 0)
        MainFramePage.Size = UDim2.new(0, 677, 0, 318)
        MainFramePage.ClipsDescendants = true
        
        UICornerMainFramePage.CornerRadius = UDim.new(0, 4)
        UICornerMainFramePage.Name = "UICornerMainFramePage"
        UICornerMainFramePage.Parent = MainFramePage

        local ScrollMainPage = Instance.new("ScrollingFrame")
        local UIListLayoutPage = Instance.new("UIListLayout")
        
        ScrollMainPage.Name = "ScrollMainPage"
        ScrollMainPage.Parent = MainFramePage
        ScrollMainPage.Active = true
        ScrollMainPage.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        ScrollMainPage.BackgroundTransparency = 1.000
        ScrollMainPage.BorderSizePixel = 0
        ScrollMainPage.Size = UDim2.new(0, 677, 0, 318)
        ScrollMainPage.CanvasSize = UDim2.new(0, 0, 0, 0)
        ScrollMainPage.ScrollBarThickness = 0
        
        UIListLayoutPage.Name = "UIListLayoutPage"
        UIListLayoutPage.Parent = ScrollMainPage
        UIListLayoutPage.FillDirection = Enum.FillDirection.Horizontal
        UIListLayoutPage.SortOrder = Enum.SortOrder.LayoutOrder
        UIListLayoutPage.Padding = UDim.new(0, 7)

        local UIPaddingPage = Instance.new("UIPadding")
        
        UIPaddingPage.Name = "UIPaddingPage"
        UIPaddingPage.Parent = ScrollMainPage
        UIPaddingPage.PaddingLeft = UDim.new(0, 7)
        UIPaddingPage.PaddingTop = UDim.new(0, 12)

        MakeDraggable(Top,Main)


        TextButton.MouseButton1Click:Connect(function()
            CircleAnim(Tabb, Color3.fromRGB(255,255,255), Color3.fromRGB(255,255,255))
            TextTab.TextSize = 0

            TweenService:Create(
                TextTab,
                TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                {TextSize = 15}
            ):Play()
            for i,v in next, PageFolder:GetChildren() do 
                if v.Name == "MainFramePage" then
                    currenttab = v.Name
                end
                UIPageLayout:JumpTo(MainFramePage)
            end task.wait(.2)
            Tabtoggle = false
            TweenService:Create(
                Tab,
                TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                {Size = UDim2.new(0, 0, 0, 342)}
            ):Play()
            TweenService:Create(
                Black,
                TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                {Size = UDim2.new(0, 0, 0, 342)}
            ):Play()
            TweenService:Create(
                ImageTab,
                TweenInfo.new(0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
                {ImageColor3 = Color3.fromRGB(255, 255, 255)}
            ):Play()
		end)

		if abc == false then
            UIPageLayout:JumpToIndex(1)
			abc = true
		end

        local Tab = {}

        function Tab:Page()
            local MainFramePage_2 = Instance.new("Frame")
            local UICornerMainFramePage_2 = Instance.new("UICorner")
            local UiToggle_UiStroke1 = Instance.new("UIStroke")
            local ScrollingMainFramePage = Instance.new("ScrollingFrame")
            local UIListLayoutMainFramePage = Instance.new("UIListLayout")

            MainFramePage_2.Name = "MainFramePage"
            MainFramePage_2.Parent = ScrollMainPage
            MainFramePage_2.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
            MainFramePage_2.BorderSizePixel = 0
            MainFramePage_2.ClipsDescendants = true
            MainFramePage_2.Position = UDim2.new(-0.010447761, 0, -0.00326797389, 0)
            MainFramePage_2.Size = UDim2.new(0, 328, 0, 296)

            UICornerMainFramePage_2.CornerRadius = UDim.new(0, 4)
            UICornerMainFramePage_2.Name = "UICornerMainFramePage"
            UICornerMainFramePage_2.Parent = MainFramePage_2

            UiToggle_UiStroke1.Color = _G.Color
            UiToggle_UiStroke1.Thickness = 1
            UiToggle_UiStroke1.Name = "UiToggle_UiStroke1"
            UiToggle_UiStroke1.Parent = MainFramePage_2

            ScrollingMainFramePage.Name = "ScrollingMainFramePage"
            ScrollingMainFramePage.Parent = MainFramePage_2
            ScrollingMainFramePage.Active = true
            ScrollingMainFramePage.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            ScrollingMainFramePage.BackgroundTransparency = 1.000
            ScrollingMainFramePage.BorderSizePixel = 0
            ScrollingMainFramePage.Size = UDim2.new(0, 328, 0, 296)
            ScrollingMainFramePage.CanvasSize = UDim2.new(0, 0, 0, 0)
            ScrollingMainFramePage.ScrollBarThickness = 0

            UIListLayoutMainFramePage.Name = "UIListLayoutMainFramePage"
            UIListLayoutMainFramePage.Parent = ScrollingMainFramePage
            UIListLayoutMainFramePage.SortOrder = Enum.SortOrder.LayoutOrder
            UIListLayoutMainFramePage.Padding = UDim.new(0, 8)


            local UIPaddingMainFramePage = Instance.new("UIPadding")

            UIPaddingMainFramePage.Name = "UIPaddingMainFramePage"
            UIPaddingMainFramePage.Parent = ScrollingMainFramePage
            UIPaddingMainFramePage.PaddingTop = UDim.new(0, 9)
            
            
            game:GetService("RunService").Stepped:Connect(function()
                pcall(function()
                    ScrollingMainFramePage.CanvasSize = UDim2.new(0,0,0,UIListLayoutMainFramePage.AbsoluteContentSize.Y + 26)
                    ScrollingTab.CanvasSize = UDim2.new(0,0,0,TabList.AbsoluteContentSize.Y + 10)
                end)
            end)

            local main = {}
            function main:Toggle2(text,default,callback)
                local ToggleFrame2 = Instance.new("Frame")
                local TextToggle2 = Instance.new("TextLabel")
                local Toggle_2 = Instance.new("Frame")
                local UICornerToggle2 = Instance.new("UICorner")
                local Tgle2 = Instance.new("ImageLabel")
                local ButtonTgle2 = Instance.new("TextButton")
                local toggle2 = false
                local lock2 = false

                ToggleFrame2.Name = "ToggleFrame2"
                ToggleFrame2.Parent = ScrollingMainFramePage
                ToggleFrame2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                ToggleFrame2.BackgroundTransparency = 1.000
                ToggleFrame2.ClipsDescendants = true
                ToggleFrame2.Size = UDim2.new(0, 328, 0, 32)

                TextToggle2.Name = "TextToggle2"
                TextToggle2.Parent = ToggleFrame2
                TextToggle2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                TextToggle2.BackgroundTransparency = 1.000
                TextToggle2.Position = UDim2.new(0.23780489, 0, 0, 0)
                TextToggle2.Size = UDim2.new(0, 192, 0, 32)
                TextToggle2.Font = Enum.Font.GothamBold
                TextToggle2.Text = "Auto Farm Level"
                TextToggle2.TextColor3 = Color3.fromRGB(255, 255, 255)
                TextToggle2.TextSize = 14.000
                TextToggle2.TextXAlignment = Enum.TextXAlignment.Left

                Toggle_2.Name = "Toggle"
                Toggle_2.Parent = ToggleFrame2
                Toggle_2.BackgroundColor3 = Color3.fromRGB(39, 39, 39)
                Toggle_2.BorderSizePixel = 0
                Toggle_2.Position = UDim2.new(0.103658535, 0, 0.0625, 0)
                Toggle_2.Size = UDim2.new(0, 28, 0, 28)

                UICornerToggle2.CornerRadius = UDim.new(0, 4)
                UICornerToggle2.Name = "UICornerToggle2"
                UICornerToggle2.Parent = Toggle_2

                Tgle2.Name = "Tgle2"
                Tgle2.Parent = Toggle_2
                Tgle2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                Tgle2.BackgroundTransparency = 1.000
                Tgle2.Position = UDim2.new(0.0357142873, 0, 0.0357142873, 0)
                Tgle2.Size = UDim2.new(0, 26, 0, 26)
                Tgle2.Image = "rbxassetid://6031068421"
                Tgle2.ImageColor3 = Color3.fromRGB(32,143,252)

                ButtonTgle2.Name = "ButtonTgle2"
                ButtonTgle2.Parent = ToggleFrame2
                ButtonTgle2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                ButtonTgle2.BackgroundTransparency = 1.000
                ButtonTgle2.Size = UDim2.new(0, 328, 0, 32)
                ButtonTgle2.Font = Enum.Font.SourceSans
                ButtonTgle2.Text = ""
                ButtonTgle2.TextColor3 = Color3.fromRGB(0, 0, 0)
                ButtonTgle2.TextSize = 14.000

                
                if default == false then
                    toggle_lol = false
                    TweenService:Create(
                        Tgle2,
                        TweenInfo.new(0.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                        {ImageTransparency = 1}
                    ):Play()
                    callback(toggle_lol)
                end
                if default == true then
                    toggle_lol = true
                    TweenService:Create(
                        Tgle2,
                        TweenInfo.new(0.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                        {ImageTransparency = 0}
                    ):Play()
                    callback(toggle_lol)
                end
                ButtonTgle2.MouseButton1Click:Connect(function()
                    if Tabtoggle == false then
                        if toggle_lol == false and lock2 == false then
                            toggle_lol = true
                            TweenService:Create(
                                Tgle2,
                                TweenInfo.new(0.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                                {ImageTransparency = 0}
                            ):Play()
                            callback(toggle_lol)
                        elseif toggle_lol == true and lock2 == false then
                            toggle_lol = false
                            TweenService:Create(
                                Tgle2,
                                TweenInfo.new(0.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                                {ImageTransparency = 1}
                            ):Play()
                            callback(toggle_lol)
                        end
                    end
                end
                )
            end

            function main:Button(text,callback)
                local FrameButton = Instance.new("Frame")
                local Btn = Instance.new("Frame")
                local UICornerBtn = Instance.new("UICorner")
                local TextLabelBtn = Instance.new("TextLabel")
                local ButtonBtn = Instance.new("TextButton")

                FrameButton.Name = "FrameButton"
                FrameButton.Parent = ScrollingMainFramePage
                FrameButton.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                FrameButton.BackgroundTransparency = 1.000
                FrameButton.Size = UDim2.new(0, 328, 0, 32)
                
                Btn.Name = "Btn"
                Btn.Parent = FrameButton
                Btn.BackgroundColor3 = Color3.fromRGB(255,255,255)
                Btn.BorderColor3 = Color3.fromRGB(255,255,255)
                Btn.BorderSizePixel = 2
                Btn.Position = UDim2.new(0.0487804897, 0, 0.03125, 0)
                Btn.Size = UDim2.new(0, 296, 0, 30)
                Btn.ClipsDescendants = true

                UICornerBtn.CornerRadius = UDim.new(0, 4)
                UICornerBtn.Name = "UICornerBtn"
                UICornerBtn.Parent = Btn

                TextLabelBtn.Name = "TextLabelBtn"
                TextLabelBtn.Parent = Btn
                TextLabelBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                TextLabelBtn.BackgroundTransparency = 1.000
                TextLabelBtn.Size = UDim2.new(0, 296, 0, 30)
                TextLabelBtn.Font = Enum.Font.GothamBold
                TextLabelBtn.Text = text
                TextLabelBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
                TextLabelBtn.TextSize = 14.000
                
                ButtonBtn.Name = "ButtonBtn"
                ButtonBtn.Parent = FrameButton
                ButtonBtn.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                ButtonBtn.BackgroundTransparency = 1.000
                ButtonBtn.Size = UDim2.new(0, 328, 0, 31)
                ButtonBtn.Font = Enum.Font.SourceSans
                ButtonBtn.Text = ""
                ButtonBtn.TextColor3 = Color3.fromRGB(0, 0, 0)
                ButtonBtn.TextSize = 14.000
                
                ButtonBtn.MouseButton1Click:Connect(function()
                    if Tabtoggle == false then
                        CircleAnim(Btn, Color3.fromRGB(255,255,255), Color3.fromRGB(255,255,255))
                        TextLabelBtn.TextSize = 0
                        TweenService:Create(
                            TextLabelBtn,
                            TweenInfo.new(0.4,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
                            {TextSize = 14}
                        ):Play()
                        callback()
                    end
                end)
            end

            function main:Line()
                local LineFrame = Instance.new("Frame")
				local Line = Instance.new("Frame")

				LineFrame.Name = "LineFrame"
				LineFrame.Parent = ScrollingMainFramePage
				LineFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
				LineFrame.BackgroundTransparency = 1.000
				LineFrame.Size = UDim2.new(0, 328, 0, 21)

				Line.Name = "LineMain"
				Line.Parent = LineFrame
				Line.AnchorPoint = Vector2.new(0.5, 0.5)
				Line.BackgroundColor3 = _G.Color
				Line.BorderSizePixel = 0
				Line.Position = UDim2.new(0.5, 0, 0.428571433, 0)
				Line.Size = UDim2.new(0, 296, 0, 2)
            end

            function main:Label(text)
                local LabelFrame = Instance.new("Frame")
                local textlabel = Instance.new("TextLabel")
                local labelfunc = {}


                LabelFrame.Name = "LabelFrame"
                LabelFrame.Parent = ScrollingMainFramePage
                LabelFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                LabelFrame.BackgroundTransparency = 1.000
                LabelFrame.ClipsDescendants = true
                LabelFrame.Size = UDim2.new(0, 328, 0, 32)

                textlabel.Name = "TextToggle"
                textlabel.Parent = LabelFrame
                textlabel.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                textlabel.BackgroundTransparency = 1.000
                textlabel.Position = UDim2.new(0, 0, 0, 0)
                textlabel.Size = UDim2.new(0, 328, 0, 32)
                textlabel.Font = Enum.Font.GothamBold
                textlabel.Text = text
                textlabel.TextColor3 = Color3.fromRGB(255, 255, 255)
                textlabel.TextSize = 14.000
                textlabel.TextXAlignment = Enum.TextXAlignment.Center

                function labelfunc:ChangeText(newtext)
                    textlabel.Text = newtext
                end
                return labelfunc
            end

            function main:Toggle(text,default,callback)
                local ToggleFrame = Instance.new("Frame")
                local TextToggle = Instance.new("TextLabel")
                local Toggle = Instance.new("Frame")
                local UICornerToggle = Instance.new("UICorner")
                local Tgle = Instance.new("Frame")
                local UICornerTgle = Instance.new("UICorner")
                local ButtonToggle = Instance.new("TextButton")
                local toggle = default or false
                local RetrunStatsToggle = {}
                local lock = false

                ToggleFrame.Name = "ToggleFrame"
                ToggleFrame.Parent = ScrollingMainFramePage
                ToggleFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                ToggleFrame.BackgroundTransparency = 1.000
                ToggleFrame.ClipsDescendants = true
                ToggleFrame.Size = UDim2.new(0, 328, 0, 32)

                TextToggle.Name = "TextToggle"
                TextToggle.Parent = ToggleFrame
                TextToggle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                TextToggle.BackgroundTransparency = 1.000
                TextToggle.Position = UDim2.new(0.104, 0, 0, 0)
                TextToggle.Size = UDim2.new(0, 192, 0, 32)
                TextToggle.Font = Enum.Font.GothamBold
                TextToggle.Text = text
                TextToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
                TextToggle.TextSize = 14.000
                TextToggle.TextXAlignment = Enum.TextXAlignment.Left

                Toggle.Name = "Toggle"
                Toggle.Parent = ToggleFrame
                Toggle.BackgroundColor3 = Color3.fromRGB(148, 148, 148)
                Toggle.BorderSizePixel = 0
                Toggle.Position = UDim2.new(0.713414609, 0, 0, 12)
                Toggle.Size = UDim2.new(0, 56, 0, 7)

                UICornerToggle.CornerRadius = UDim.new(0, 9999)
                UICornerToggle.Name = "UICornerToggle"
                UICornerToggle.Parent = Toggle

                Tgle.Name = "Tgle"
                Tgle.Parent = Toggle
                Tgle.BackgroundColor3 = Color3.fromRGB(255,255,255)
                Tgle.Position = UDim2.new(0, -1, 0, -7.5)
                Tgle.Size = UDim2.new(0, 22, 0, 22)

                UICornerTgle.CornerRadius = UDim.new(0, 9999)
                UICornerTgle.Name = "UICornerTgle"
                UICornerTgle.Parent = Tgle

                ButtonToggle.Name = "ButtonToggle"
                ButtonToggle.Parent = ToggleFrame
                ButtonToggle.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                ButtonToggle.BackgroundTransparency = 1.000
                ButtonToggle.Size = UDim2.new(0, 328, 0, 32)
                ButtonToggle.Font = Enum.Font.SourceSans
                ButtonToggle.Text = ""
                ButtonToggle.TextColor3 = Color3.fromRGB(0, 0, 0)
                ButtonToggle.TextSize = 14.000


                if default == false then
                    toggle = false
                    TweenService:Create(
                        Tgle,
                        TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                        {Position = UDim2.new(0, -1, 0, -7.5)}
                        ):Play()
                    TweenService:Create(
                        Toggle,
                        TweenInfo.new(0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
                        {BackgroundColor3 = Color3.fromRGB(150, 150, 150)}
                    ):Play()
                    TweenService:Create(
                        Tgle,
                        TweenInfo.new(0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
                        {BackgroundColor3 = Color3.fromRGB(255, 255, 255)}
                    ):Play()
                    TweenService:Create(
                        Tgle,
                        TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                        {Size = UDim2.new(0, 37, 0, 22)}
                    ):Play()
                    wait()
                    TweenService:Create(
                        Tgle,
                        TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                        {Size = UDim2.new(0, 22, 0, 22)}
                    ):Play()
                    wait()
                    TweenService:Create(
                        Tgle,
                        TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                        {Position = UDim2.new(0, -1, 0, -7.5)}
                    ):Play()
                    callback(toggle)
                end
                if default == true then
                    toggle = true
                    TweenService:Create(
                        Tgle,
                        TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                        {Size = UDim2.new(0, 35, 0, 22)}
                    ):Play()
                    TweenService:Create(
                        Toggle,
                        TweenInfo.new(0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
                        {BackgroundColor3 = Color3.fromRGB(200, 30, 30)}
                    ):Play()
                    TweenService:Create(
                        Tgle,
                        TweenInfo.new(0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
                        {BackgroundColor3 = _G.Color}
                    ):Play()
                    wait()
                    TweenService:Create(
                        Tgle,
                        TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                        {Position = UDim2.new(0, 30, 0, -7.5)}
                    ):Play()
                    wait()
                    TweenService:Create(
                        Tgle,
                        TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                        {Size = UDim2.new(0, 22, 0, 22)}
                    ):Play()
                    wait()
                    TweenService:Create(
                        Tgle,
                        TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                        {Position = UDim2.new(0, 35, 0, -7.5)}
                    ):Play()
                    callback(toggle)
                end

                ButtonToggle.MouseButton1Click:Connect(function()
                    if Tabtoggle == false then
                        if toggle == false and lock == false then
                            toggle = true
                            CircleAnim(ButtonToggle, Color3.fromRGB(255,255,255), Color3.fromRGB(255,255,255))
                            TweenService:Create(
                                Tgle,
                                TweenInfo.new(0.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                                {Size = UDim2.new(0, 35, 0, 22)}
                            ):Play()
                            TweenService:Create(
                                Tgle,
                                TweenInfo.new(0.35,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                                {Size = UDim2.new(0, 22, 0, 22)}
                            ):Play()
                            wait()
                            TweenService:Create(
                                Toggle,
                                TweenInfo.new(0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
                                {BackgroundColor3 = Color3.fromRGB(200, 30, 30)}
                            ):Play()
                            TweenService:Create(
                                Tgle,
                                TweenInfo.new(0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
                                {BackgroundColor3 = _G.Color}
                            ):Play()
                            wait()
                            TweenService:Create(
                                Tgle,
                                TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                                {Position = UDim2.new(0, 35, 0, -7.5)}
                            ):Play()
                            wait()
                            TweenService:Create(
                                Tgle,
                                TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                                {Position = UDim2.new(0, 35, 0, -7.5)}
                            ):Play()
                            callback(toggle)
                        elseif toggle == true and lock == false then
                            toggle = false
                            TweenService:Create(
                                Tgle,
                                TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                                {Position = UDim2.new(0, -1, 0, -7.5)}
                                ):Play()
                            TweenService:Create(
                                Toggle,
                                TweenInfo.new(0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
                                {BackgroundColor3 = Color3.fromRGB(150, 150, 150)}
                            ):Play()
                            TweenService:Create(
                                Tgle,
                                TweenInfo.new(0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
                                {BackgroundColor3 = Color3.fromRGB(255, 255, 255)}
                            ):Play()
                            TweenService:Create(
                                Tgle,
                                TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                                {Size = UDim2.new(0, 37, 0, 22)}
                            ):Play()
                            wait()
                            TweenService:Create(
                                Tgle,
                                TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                                {Size = UDim2.new(0, 22, 0, 22)}
                            ):Play()
                            wait()
                            TweenService:Create(
                                Tgle,
                                TweenInfo.new(0.3,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                                {Position = UDim2.new(0, -1, 0, -7.5)}
                            ):Play()
                            callback(toggle)
                        end
                    end
                end
                )

                local lockerframe = Instance.new("Frame")

                lockerframe.Name = "lockerframe"
                lockerframe.Parent = ToggleFrame
                lockerframe.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
                lockerframe.BackgroundTransparency = 1
                lockerframe.BorderSizePixel = 0
                lockerframe.Size = UDim2.new(0, 300, 0, 32)
                lockerframe.Position = UDim2.new(0.5, 0, 0.5, 0)
                lockerframe.AnchorPoint = Vector2.new(0.5, 0.5)
    
                local LockerImageLabel = Instance.new("ImageLabel")
    
                LockerImageLabel.Parent = lockerframe
                LockerImageLabel.BackgroundTransparency = 1.000
                LockerImageLabel.BorderSizePixel = 0
                LockerImageLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
                LockerImageLabel.AnchorPoint = Vector2.new(0.5, 0.5)
                LockerImageLabel.Size = UDim2.new(0, 0, 0, 0)
                LockerImageLabel.Image = "http://www.roblox.com/asset/?id=3926305904"
                LockerImageLabel.ImageRectOffset = Vector2.new(404, 364)
                LockerImageLabel.ImageRectSize = Vector2.new(36, 36)
                LockerImageLabel.ImageColor3 = Color3.fromRGB(255,25,25)

                function RetrunStatsToggle:Lock()
                    TweenService:Create(
                        lockerframe,
                        TweenInfo.new(.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out,0.1),
                        {BackgroundTransparency = 0.7}
                    ):Play()
                    TweenService:Create(
                        LockerImageLabel,
                        TweenInfo.new(.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out,0.1),
                        {Size = UDim2.new(0, 30, 0, 30)}
                    ):Play()
                    lock = true
                end

                function RetrunStatsToggle:ChangeStateTrue()
                    if toggle == false and lock == false then
                        toggle = true
                        TweenService:Create(
                            Tgle,
                            TweenInfo.new(0.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                            {Size = UDim2.new(0, 32, 0, 22)}
                        ):Play()
                        wait()
                        TweenService:Create(
                            Tgle,
                            TweenInfo.new(0.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                            {Position = UDim2.new(0, 30, 0, 2)}
                        ):Play()
                        wait()
                        TweenService:Create(
                            Tgle,
                            TweenInfo.new(0.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                            {Size = UDim2.new(0, 22, 0, 22)}
                        ):Play()
                        wait()
                        TweenService:Create(
                            Tgle,
                            TweenInfo.new(0.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                            {Position = UDim2.new(0, 33, 0, 2)}
                        ):Play()
                        callback(toggle)
                    end
                end

                function RetrunStatsToggle:ChangeStateFalse()
                    if toggle == true and lock == false then
                        toggle = false
                        TweenService:Create(
                            Tgle,
                            TweenInfo.new(0.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                            {Position = UDim2.new(0, 1.5, 0, 2)}
                        ):Play()
                        wait()
                        TweenService:Create(
                            Tgle,
                            TweenInfo.new(0.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                            {Size = UDim2.new(0, 32, 0, 22)}
                        ):Play()
                        wait()
                        TweenService:Create(
                            Tgle,
                            TweenInfo.new(0.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                            {Size = UDim2.new(0, 22, 0, 22)}
                        ):Play()
                        wait()
                        TweenService:Create(
                            Tgle,
                            TweenInfo.new(0.2,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                            {Position = UDim2.new(0, 1, 0, 2)}
                        ):Play()
                        callback(toggle)
                    end
                end
                function RetrunStatsToggle:Unlock()
                    TweenService:Create(
                        lockerframe,
                        TweenInfo.new(.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out,0.1),
                        {BackgroundTransparency = 1}
                    ):Play()
                    TweenService:Create(
                        LockerImageLabel,
                        TweenInfo.new(.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out,0.1),
                        {Size = UDim2.new(0, 0, 0, 0)}
                    ):Play()
                    lock = false
                end
                return RetrunStatsToggle
            end

            function main:Slider(text,min,max,set,callback)
                local sliderfunc = {}
                local SliderFrame = Instance.new("Frame")
                local ClickHere = Instance.new("TextButton")
                local Circle = Instance.new("TextButton")
                local Bar = Instance.new("Frame")
                local UICornerBar = Instance.new("UICorner")
                local BarValue = Instance.new("Frame")
                local UICornerBarValue = Instance.new("UICorner")
                local TextSlider = Instance.new("TextLabel")

                
                SliderFrame.Name = "SliderFrame"
                SliderFrame.Parent = ScrollingMainFramePage
                SliderFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                SliderFrame.BackgroundTransparency = 1.000
                SliderFrame.Position = UDim2.new(0, 0, 0.292682916, 0)
                SliderFrame.Size = UDim2.new(0, 328, 0, 56)

                ClickHere.Name = "ClickHere"
                ClickHere.Parent = SliderFrame
                ClickHere.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                ClickHere.BackgroundTransparency = 1
                ClickHere.ClipsDescendants = true
                ClickHere.Position = UDim2.new(0.0853658542, 0, 0.642857134, 0)
                ClickHere.Size = UDim2.new(0, 271, 0, 5)
                ClickHere.Font = Enum.Font.SourceSans
                ClickHere.Text = ""
                ClickHere.TextColor3 = Color3.fromRGB(0, 0, 0)
                ClickHere.TextSize = 14.000

                Circle.Name = "Circle"
                Circle.Parent = ClickHere
                Circle.BackgroundColor3 = _G.Color
                Circle.BackgroundTransparency = 0
                Circle.ClipsDescendants = true
                Circle.Position = UDim2.new(0, 0, 0, 0)
                Circle.Size = UDim2.new(0, 20, 0, 20)
                Circle.Font = Enum.Font.SourceSans
                Circle.Text = ""
                Circle.TextColor3 = Color3.fromRGB(0, 0, 0)
                Circle.TextSize = 14.000

                UICornerBar.CornerRadius = UDim.new(0, 99)
                UICornerBar.Name = "UICornerBar"
                UICornerBar.Parent = Circle

                Bar.Name = "Bar"
                Bar.Parent = ClickHere
                Bar.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                Bar.ClipsDescendants = true
                Bar.Size = UDim2.new(0, 271, 0, 5)

                UICornerBar.CornerRadius = UDim.new(0, 99)
                UICornerBar.Name = "UICornerBar"
                UICornerBar.Parent = Bar

                BarValue.Name = "BarValue"
                BarValue.Parent = ClickHere
                BarValue.BackgroundColor3 = _G.Color
                BarValue.Size = UDim2.new((set or 0) / max, 0, 0, 5)

                UICornerBarValue.CornerRadius = UDim.new(0, 99)
                UICornerBarValue.Name = "UICornerBarValue"
                UICornerBarValue.Parent = BarValue

                TextSlider.Name = "TextSlider"
                TextSlider.Parent = SliderFrame
                TextSlider.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                TextSlider.BackgroundTransparency = 1.000
                TextSlider.Position = UDim2.new(0.0792682916, 0, 0.196428567, 0)
                TextSlider.Size = UDim2.new(0, 200, 0, 21)
                TextSlider.Font = Enum.Font.GothamBold
                TextSlider.Text = text.." : "..tostring(set and math.floor( (set / max) * (max - min) + min) or 0)
                TextSlider.TextColor3 = Color3.fromRGB(255, 255, 255)
                TextSlider.TextSize = 14.000
                TextSlider.TextXAlignment = Enum.TextXAlignment.Left


                
                local mouse = game.Players.LocalPlayer:GetMouse()
                local uis = game:GetService("UserInputService")


                if Value == nil then
                    Value = set
                    pcall(function()
                        callback(Value)
                    end)
                end

                
                ClickHere.MouseButton1Down:Connect(function()
                    if Tabtoggle == false then
                        Value = math.floor((((tonumber(max) - tonumber(min)) / 271) * BarValue.AbsoluteSize.X) + tonumber(min)) or 0
                        TweenService:Create(
                            BarValue,
                            TweenInfo.new(0.1,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
                            {Size = UDim2.new(0, math.clamp(mouse.X - BarValue.AbsolutePosition.X, 0, 271), 0, 5)}
                        ):Play()
                        TweenService:Create(
                            Circle,
                            TweenInfo.new(0.1,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
                            {Size = UDim2.new(0, math.clamp(mouse.X - BarValue.AbsolutePosition.X, 0, 271), 0, 5)}
                        ):Play()
                        moveconnection = mouse.Move:Connect(function()
                            TextSlider.Text = text.." : "..Value
                            Value = math.floor((((tonumber(max) - tonumber(min)) / 271) * BarValue.AbsoluteSize.X) + tonumber(min))
                            TweenService:Create(
                                BarValue,
                                TweenInfo.new(0.1,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
                                {Size = UDim2.new(0, math.clamp(mouse.X - BarValue.AbsolutePosition.X, 0, 271), 0, 5)}
                            ):Play()
                            TweenService:Create(
                                Circle,
                                TweenInfo.new(0.1,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
                                {Size = UDim2.new(0, math.clamp(mouse.X - BarValue.AbsolutePosition.X, 0, 271), 0, 5)}
                            ):Play()
                        end)
                        releaseconnection = uis.InputEnded:Connect(function(Mouse)
                            if table.find({Enum.UserInputType.MouseButton1,Enum.UserInputType.Touch},Mouse.UserInputType) then
                                Value = math.floor((((tonumber(max) - tonumber(min)) / 271) * BarValue.AbsoluteSize.X) + tonumber(min))
                                pcall(function()
                                    callback(Value)
                                    TextSlider.Text = text.." : "..Value
                                end)
                                TweenService:Create(
                                    BarValue,
                                    TweenInfo.new(0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
                                    {Size = UDim2.new(0, math.clamp(mouse.X - BarValue.AbsolutePosition.X, 0, 271), 0, 5)}
                                ):Play()
                                TweenService:Create(
                                    Circle,
                                    TweenInfo.new(0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
                                    {Size = UDim2.new(0, math.clamp(mouse.X - BarValue.AbsolutePosition.X, 0, 271), 0, 5)}
                                ):Play()
                                moveconnection:Disconnect()
                                releaseconnection:Disconnect()
                            end
                        end)
                    end
                end)

                function sliderfunc:Update(value)
                    TextSlider.Text = text.." : "..value
                    BarValue:TweenSize(UDim2.new((value or 0) / max, 0, 0, 5), "Out", "Sine", 0.2, true)
                    Circle:TweenSize(UDim2.new((value or 0) / max, 0, 0, 5), "Out", "Sine", 0.2, true)
                    pcall(function()
                        callback(value)
                    end)
                end
                return sliderfunc
            end

            function main:Dropdown(text,option,set,callback)
                local DropFrame = Instance.new("Frame")
                local Text = Instance.new("TextLabel")
                local DropImage = Instance.new("ImageLabel")
                local DownFrame = Instance.new("Frame")
                local ScrollingDown = Instance.new("ScrollingFrame")
                local ItemList = Instance.new("UIListLayout")
                local Frame = Instance.new("Frame")
                local CornerFrae = Instance.new("UICorner")
                local ButtonDrop = Instance.new("TextButton")
                local DropToggle = false
                local RetrunDrop = {}
                local function GetValue()
                    if set then
                        if table.find(option, set) then
                            callback(set)
                            return text .. " : " .. set
                        else
                            return text .. " : "
                        end
                    else
                        return text .. " : "
                    end
                end
                DropFrame.Name = "DropFrame"
                DropFrame.Parent = ScrollingMainFramePage
                DropFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                DropFrame.BackgroundTransparency = 1.000
                DropFrame.Position = UDim2.new(0, 0, 0.522648096, 0)
                DropFrame.Size = UDim2.new(0, 328, 0, 35)
                
                Frame.Parent = DropFrame
                Frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
                Frame.BorderSizePixel = 0
                Frame.Position = UDim2.new(0.0457317084, 0, 0.0285714287, 0)
                Frame.Size = UDim2.new(0, 296, 0, 32)
                Frame.ClipsDescendants = true

                DropImage.Name = "DropImage"
                DropImage.Parent = Frame
                DropImage.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                DropImage.BackgroundTransparency = 1.000
                DropImage.Position = UDim2.new(0.871374369, 0, -0.012, 0)
                DropImage.Rotation = 180.000
                DropImage.Size = UDim2.new(0, 32, 0, 32)
                DropImage.Image = "rbxassetid://6031094670"
                
                Text.Name = "Text"
                Text.Parent = Frame
                Text.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                Text.BackgroundTransparency = 1.000
                Text.Position = UDim2.new(0.0354317725, 0, -0.012, 0)
                Text.Size = UDim2.new(0, 221, 0, 32)
                Text.Font = Enum.Font.GothamBold
                Text.Text = GetValue()
                Text.TextColor3 = Color3.fromRGB(255, 255, 255)
                Text.TextSize = 14.000
                Text.TextXAlignment = Enum.TextXAlignment.Left
                
                CornerFrae.CornerRadius = UDim.new(0, 4)
                CornerFrae.Name = "CornerFrae"
                CornerFrae.Parent = Frame

                ButtonDrop.Name = "ButtonToggle"
                ButtonDrop.Parent = DropFrame
                ButtonDrop.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                ButtonDrop.BackgroundTransparency = 1.000
                ButtonDrop.Size = UDim2.new(0, 328, 0, 40)
                ButtonDrop.Font = Enum.Font.SourceSans
                ButtonDrop.Text = ""
                ButtonDrop.TextColor3 = Color3.fromRGB(0, 0, 0)
                ButtonDrop.TextSize = 14.000


                DownFrame.Name = "DownFrame"
                DownFrame.Parent = ScrollingMainFramePage
                DownFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                DownFrame.BackgroundTransparency = 1.000
                DownFrame.BorderColor3 = Color3.fromRGB(27, 42, 53)
                DownFrame.ClipsDescendants = true
                DownFrame.Position = UDim2.new(0, 0, 0.1, 0)
                DownFrame.Size = UDim2.new(0, 328, 0, 0)

                ScrollingDown.Name = "ScrollingDown"
                ScrollingDown.Parent = DownFrame
                ScrollingDown.Active = true
                ScrollingDown.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                ScrollingDown.BackgroundTransparency = 1.000
                ScrollingDown.BorderSizePixel = 0
                ScrollingDown.Size = UDim2.new(0, 328, 0, 98)
                ScrollingDown.CanvasSize = UDim2.new(0, 0, 0, 0)
                ScrollingDown.ScrollBarThickness = 0
                ScrollingDown.BottomImage = ""
                ScrollingDown.TopImage = ""

                ItemList.Name = "ItemList"
                ItemList.Parent = ScrollingDown
                ItemList.SortOrder = Enum.SortOrder.LayoutOrder
                ItemList.Padding = UDim.new(0, 3)

                local SelectionScrollingUIPadding = Instance.new("UIPadding")
                SelectionScrollingUIPadding.Name = "SelectionScrollingUIPadding"
                SelectionScrollingUIPadding.Parent = ScrollingDown

                if set ~= nil then
                    callback(set)
                end

                for i,v in pairs(option) do
                    local ItemFrame = Instance.new("Frame")
                    local ItemButton = Instance.new("TextButton")
                    local UICorner = Instance.new("UICorner")


                    ItemFrame.Name = "ItemFrame"
                    ItemFrame.Parent = ScrollingDown
                    ItemFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                    ItemFrame.BackgroundTransparency = 1.000
                    ItemFrame.Size = UDim2.new(0, 328, 0, 24)
    
                    ItemButton.Name = "ItemButton"
                    ItemButton.Parent = ItemFrame
                    ItemButton.BackgroundColor3 = _G.Color
                    ItemButton.BorderSizePixel = 0
                    ItemButton.Position = UDim2.new(0.0701219514, 0, 0, 0)
                    ItemButton.Size = UDim2.new(0, 282, 0, 24)
                    ItemButton.AutoButtonColor = false
                    ItemButton.Font = Enum.Font.GothamBold
                    ItemButton.Text = tostring(v)
                    ItemButton.ClipsDescendants = true
                    ItemButton.TextColor3 = Color3.fromRGB(255, 255, 255)
                    ItemButton.TextSize = 14.000
    
                    UICorner.CornerRadius = UDim.new(0, 4)
                    UICorner.Parent = ItemButton

                    ItemButton.MouseButton1Down:Connect(function()
                        if Tabtoggle == false then
                            ItemButton.TextSize = 0
                            TweenService:Create(
                                ItemButton,
                                TweenInfo.new(.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out,0.1),
                                {TextSize = 12}
                            ):Play()
                            Text.Text = tostring(text.." : "..v)
                            CircleAnim(ItemButton,Color3.fromRGB(255,255,255),Color3.fromRGB(255,255,255))
                            
                            callback(v)
                            DropToggle = false
                            TweenService:Create(
                                DownFrame,
                                TweenInfo.new(0.4,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                                {Size = UDim2.new(0, 328, 0, 0)}
                            ):Play()
                            TweenService:Create(
                                DropImage,
                                TweenInfo.new(0.4,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                                {Rotation = 180}
                            ):Play()
                            TweenService:Create(
                                DropImage,
                                TweenInfo.new(0.4,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
                                {ImageColor3 = _G.Color}
                            ):Play()
                        end         
                    end)
                end 


                ScrollingDown.CanvasSize = UDim2.new(0,0,0,ItemList.AbsoluteContentSize.Y + 10)
                ButtonDrop.MouseButton1Click:Connect(function()
                    if Tabtoggle == false then
                        if DropToggle == false then
                            DropToggle = true
                            CircleAnim(ButtonDrop, Color3.fromRGB(255,255,255), Color3.fromRGB(255,255,255))
                            TweenService:Create(
                                DownFrame,
                                TweenInfo.new(0.4,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                                {Size = UDim2.new(0, 328, 0, 98)}
                            ):Play()
                            TweenService:Create(
                                DropImage,
                                TweenInfo.new(0.4,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                                {Rotation = 270}
                            ):Play()
                            TweenService:Create(
                                DropImage,
                                TweenInfo.new(0.4,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                                {ImageColor3 = Color3.fromRGB(255,255,255)}
                            ):Play()
                            CircleAnim(Frame,Color3.fromRGB(255,255,255),Color3.fromRGB(255,255,255))
                        elseif DropToggle == true then
                            DropToggle = false
                            TweenService:Create(
                                DownFrame,
                                TweenInfo.new(0.4,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                                {Size = UDim2.new(0, 328, 0, 0)}
                            ):Play()
                            TweenService:Create(
                                DropImage,
                                TweenInfo.new(0.4,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                                {Rotation = 180}
                            ):Play()
                            TweenService:Create(
                                DropImage,
                                TweenInfo.new(0.4,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                                {ImageColor3 = Color3.fromRGB(255,255,255)}
                            ):Play()
                            CircleAnim(Frame,Color3.fromRGB(255,255,255),Color3.fromRGB(255,255,255))
                        end
                    end
                end
                )

                function RetrunDrop:Add(newtext)
                    local ItemFrame = Instance.new("Frame")
                    local ItemButton = Instance.new("TextButton")
                    local UICorner = Instance.new("UICorner")


                    ItemFrame.Name = "ItemFrame"
                    ItemFrame.Parent = ScrollingDown
                    ItemFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                    ItemFrame.BackgroundTransparency = 1.000
                    ItemFrame.Size = UDim2.new(0, 328, 0, 24)
    
                    ItemButton.Name = "ItemButton"
                    ItemButton.Parent = ItemFrame
                    ItemButton.BackgroundColor3 = Color3.fromRGB(32,143,252)
                    ItemButton.BorderSizePixel = 0
                    ItemButton.Position = UDim2.new(0.0701219514, 0, 0, 0)
                    ItemButton.Size = UDim2.new(0, 282, 0, 24)
                    ItemButton.AutoButtonColor = false
                    ItemButton.Font = Enum.Font.GothamBold
                    ItemButton.Text = tostring(newtext)
                    ItemButton.ClipsDescendants = true
                    ItemButton.TextColor3 = Color3.fromRGB(255, 255, 255)
                    ItemButton.TextSize = 14.000
    
                    UICorner.CornerRadius = UDim.new(0, 4)
                    UICorner.Parent = ItemButton

                    ItemButton.MouseButton1Down:Connect(function()
                        if Tabtoggle == false then
                            ItemButton.TextSize = 0
                            TweenService:Create(
                                ItemButton,
                                TweenInfo.new(.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out,0.1),
                                {TextSize = 12}
                            ):Play()
                            Text.Text = tostring(text.." : "..newtext)
                            CircleAnim(ItemButton,Color3.fromRGB(255,255,255),Color3.fromRGB(255,255,255))
                            
                            callback(newtext)
                            DropToggle = false
                            TweenService:Create(
                                DownFrame,
                                TweenInfo.new(0.2,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
                                {Size = UDim2.new(0, 328, 0, 0)}
                            ):Play()
                            TweenService:Create(
                                DropImage,
                                TweenInfo.new(0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
                                {Rotation = 180}
                            ):Play()
                        end
                    end)

                    ScrollingDown.CanvasSize = UDim2.new(0,0,0,ItemList.AbsoluteContentSize.Y + 10)
                end

                function RetrunDrop:Clear()
                    Text.Text = tostring(text).." : "
                    DropToggle = false
                    TweenService:Create(
                        DownFrame,
                        TweenInfo.new(0.2,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
                        {Size = UDim2.new(0, 328, 0, 0)}
                    ):Play()
                    TweenService:Create(
                        DropImage,
                        TweenInfo.new(0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
                        {Rotation = 180}
                    ):Play()
                    for i, v in next, ScrollingDown:GetChildren() do
                        if v:IsA("Frame") then
                            v:Destroy()
                        end
                    end
                    ScrollingDown.CanvasSize = UDim2.new(0,0,0,ItemList.AbsoluteContentSize.Y + 10)
                end
                return RetrunDrop
            end

            function main:MultiDropdown(text,option,set,callback)
                local DropFrame = Instance.new("Frame")
                local Text = Instance.new("TextLabel")
                local DropImage = Instance.new("ImageLabel")
                local DownFrame = Instance.new("Frame")
                local ScrollingDown = Instance.new("ScrollingFrame")
                local ItemList = Instance.new("UIListLayout")
                local Frame = Instance.new("Frame")
                local CornerFrae = Instance.new("UICorner")
                local ButtonDrop = Instance.new("TextButton")
                local DropToggle = false
                local RetrunDrop = {}
                local StoredTableItems = {}
                local function GetValue()
                    if set then
                        for i, v in next, set do
                            if table.find(option, v) then
                                callback(set)
                                return text .. " : " .. table.concat(set, ", ")
                            else
                                return text
                            end
                        end
                    else
                        return text .. " : "
                    end
                end

                DropFrame.Name = "DropFrame"
                DropFrame.Parent = ScrollingMainFramePage
                DropFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                DropFrame.BackgroundTransparency = 1.000
                DropFrame.Position = UDim2.nZew(0, 0, 0.522648096, 0)
                DropFrame.Size = UDim2.new(0, 328, 0, 35)
                
                Frame.Parent = DropFrame
                Frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
                Frame.BorderSizePixel = 0
                Frame.Position = UDim2.new(0.0457317084, 0, 0.0285714287, 0)
                Frame.Size = UDim2.new(0, 296, 0, 32)
                Frame.ClipsDescendants = true

                DropImage.Name = "DropImage"
                DropImage.Parent = Frame
                DropImage.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                DropImage.BackgroundTransparency = 1.000
                DropImage.Position = UDim2.new(0.871374369, 0, -0.012, 0)
                DropImage.Rotation = 180.000
                DropImage.Size = UDim2.new(0, 32, 0, 32)
                DropImage.Image = "rbxassetid://6031094670"
                
                Text.Name = "Text"
                Text.Parent = Frame
                Text.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                Text.BackgroundTransparency = 1.000
                Text.Position = UDim2.new(0.0354317725, 0, -0.012, 0)
                Text.Size = UDim2.new(0, 221, 0, 32)
                Text.Font = Enum.Font.GothamBold
                Text.Text = GetValue()
                Text.TextColor3 = Color3.fromRGB(255, 255, 255)
                Text.TextSize = 14.000
                Text.TextXAlignment = Enum.TextXAlignment.Left
                
                CornerFrae.CornerRadius = UDim.new(0, 4)
                CornerFrae.Name = "CornerFrae"
                CornerFrae.Parent = Frame

                ButtonDrop.Name = "ButtonToggle"
                ButtonDrop.Parent = DropFrame
                ButtonDrop.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                ButtonDrop.BackgroundTransparency = 1.000
                ButtonDrop.Size = UDim2.new(0, 328, 0, 40)
                ButtonDrop.Font = Enum.Font.SourceSans
                ButtonDrop.Text = ""
                ButtonDrop.TextColor3 = Color3.fromRGB(0, 0, 0)
                ButtonDrop.TextSize = 14.000


                DownFrame.Name = "DownFrame"
                DownFrame.Parent = ScrollingMainFramePage
                DownFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                DownFrame.BackgroundTransparency = 1.000
                DownFrame.BorderColor3 = Color3.fromRGB(27, 42, 53)
                DownFrame.ClipsDescendants = true
                DownFrame.Position = UDim2.new(0, 0, 0.1, 0)
                DownFrame.Size = UDim2.new(0, 328, 0, 0)

                ScrollingDown.Name = "ScrollingDown"
                ScrollingDown.Parent = DownFrame
                ScrollingDown.Active = true
                ScrollingDown.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                ScrollingDown.BackgroundTransparency = 1.000
                ScrollingDown.BorderSizePixel = 0
                ScrollingDown.Size = UDim2.new(0, 328, 0, 98)
                ScrollingDown.CanvasSize = UDim2.new(0, 0, 0, 0)
                ScrollingDown.ScrollBarThickness = 0
                ScrollingDown.BottomImage = ""
                ScrollingDown.TopImage = ""

                ItemList.Name = "ItemList"
                ItemList.Parent = ScrollingDown
                ItemList.SortOrder = Enum.SortOrder.LayoutOrder
                ItemList.Padding = UDim.new(0, 3)

                local SelectionScrollingUIPadding = Instance.new("UIPadding")
                SelectionScrollingUIPadding.Name = "SelectionScrollingUIPadding"
                SelectionScrollingUIPadding.Parent = ScrollingDown

                for i,v in pairs(option) do
                    local ItemFrame = Instance.new("Frame")
                    local ItemButton = Instance.new("TextButton")
                    local UICorner = Instance.new("UICorner")


                    ItemFrame.Name = "ItemFrame"
                    ItemFrame.Parent = ScrollingDown
                    ItemFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                    ItemFrame.BackgroundTransparency = 1.000
                    ItemFrame.Size = UDim2.new(0, 328, 0, 24)
    
                    ItemButton.Name = "ItemButton"
                    ItemButton.Parent = ItemFrame
                    ItemButton.BackgroundColor3 = _G.Color
                    ItemButton.BorderSizePixel = 0
                    ItemButton.Position = UDim2.new(0.0701219514, 0, 0, 0)
                    ItemButton.Size = UDim2.new(0, 282, 0, 24)
                    ItemButton.AutoButtonColor = false
                    ItemButton.Font = Enum.Font.GothamBold
                    ItemButton.Text = tostring(v)
                    ItemButton.ClipsDescendants = true
                    ItemButton.TextColor3 = Color3.fromRGB(255, 255, 255)
                    ItemButton.TextSize = 14.000
    
                    UICorner.CornerRadius = UDim.new(0, 4)
                    UICorner.Parent = ItemButton

                    ItemButton.MouseButton1Click:Connect(function()
                        if not table.find(StoredTableItems, Text) then
                            table.insert(StoredTableItems, Text)
                            callback(StoredTableItems, Text)
                            Text.Text = text .. " : " .. table.concat(StoredTableItems, ", ")
                            TweenService:Create(
                            ItemButton,
                            TweenInfo.new(.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                                {TextColor3 = Color3.fromRGB(255, 0, 0)}
                            ):Play()
                        else
                            TweenService:Create(
                            ItemButton,
                            TweenInfo.new(.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                                {TextColor3 = Color3.fromRGB(255,255,255)}
                            ):Play()
                            for i2, v2 in pairs(StoredTableItems) do
                                if v2 == Text then
                                    table.remove(StoredTableItems, i2)
                                    Text.Text = text .. " : " .. table.concat(StoredTableItems, ", ")
                                end
                                callback(StoredTableItems, Text)
                            end
                        end
                    end)
                end

                ScrollingDown.CanvasSize = UDim2.new(0,0,0,ItemList.AbsoluteContentSize.Y + 10)
                ButtonDrop.MouseButton1Click:Connect(function()
                    if Tabtoggle == false then
                        if DropToggle == false then
                            DropToggle = true
                            --CircleAnim(ButtonDrop, Color3.fromRGB(255,255,255), Color3.fromRGB(255,255,255))
                            TweenService:Create(
                                DownFrame,
                                TweenInfo.new(0.4,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                                {Size = UDim2.new(0, 328, 0, 98)}
                            ):Play()
                            TweenService:Create(
                                DropImage,
                                TweenInfo.new(0.4,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                                {Rotation = 270}
                            ):Play()
                            TweenService:Create(
                                DropImage,
                                TweenInfo.new(0.4,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                                {ImageColor3 = Color3.fromRGB(255,255,255)}
                            ):Play()
                            CircleAnim(Frame,Color3.fromRGB(255,255,255),Color3.fromRGB(255,255,255))
                        elseif DropToggle == true then
                            DropToggle = false
                            TweenService:Create(
                                DownFrame,
                                TweenInfo.new(0.4,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                                {Size = UDim2.new(0, 328, 0, 0)}
                            ):Play()
                            TweenService:Create(
                                DropImage,
                                TweenInfo.new(0.4,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                                {Rotation = 180}
                            ):Play()
                            TweenService:Create(
                                DropImage,
                                TweenInfo.new(0.4,Enum.EasingStyle.Back,Enum.EasingDirection.Out),
                                {ImageColor3 = Color3.fromRGB(255,255,255)}
                            ):Play()
                            CircleAnim(Frame,Color3.fromRGB(255,255,255),Color3.fromRGB(255,255,255))
                        end
                    end
                end
                )

                function RetrunDrop:Add(newtext)
                    local ItemFrame = Instance.new("Frame")
                    local ItemButton = Instance.new("TextButton")
                    local UICorner = Instance.new("UICorner")


                    ItemFrame.Name = "ItemFrame"
                    ItemFrame.Parent = ScrollingDown
                    ItemFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                    ItemFrame.BackgroundTransparency = 1.000
                    ItemFrame.Size = UDim2.new(0, 328, 0, 24)
    
                    ItemButton.Name = "ItemButton"
                    ItemButton.Parent = ItemFrame
                    ItemButton.BackgroundColor3 = Color3.fromRGB(32,143,252)
                    ItemButton.BorderSizePixel = 0
                    ItemButton.Position = UDim2.new(0.0701219514, 0, 0, 0)
                    ItemButton.Size = UDim2.new(0, 282, 0, 24)
                    ItemButton.AutoButtonColor = false
                    ItemButton.Font = Enum.Font.GothamBold
                    ItemButton.Text = tostring(newtext)
                    ItemButton.ClipsDescendants = true
                    ItemButton.TextColor3 = Color3.fromRGB(255, 255, 255)
                    ItemButton.TextSize = 14.000
    
                    UICorner.CornerRadius = UDim.new(0, 4)
                    UICorner.Parent = ItemButton

                    ItemButton.MouseButton1Down:Connect(function()
                        if Tabtoggle == false then
                            ItemButton.TextSize = 0
                            TweenService:Create(
                                ItemButton,
                                TweenInfo.new(.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out,0.1),
                                {TextSize = 12}
                            ):Play()
                            Text.Text = tostring(text.." : "..newtext)
                            CircleAnim(ItemButton,Color3.fromRGB(255,255,255),Color3.fromRGB(255,255,255))
                            
                            callback(newtext)
                            DropToggle = false
                            TweenService:Create(
                                DownFrame,
                                TweenInfo.new(0.2,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
                                {Size = UDim2.new(0, 328, 0, 0)}
                            ):Play()
                            TweenService:Create(
                                DropImage,
                                TweenInfo.new(0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
                                {Rotation = 180}
                            ):Play()
                        end
                    end)

                    ScrollingDown.CanvasSize = UDim2.new(0,0,0,ItemList.AbsoluteContentSize.Y + 10)
                end

                function RetrunDrop:Clear()
                    Text.Text = tostring(text).." : "
                    DropToggle = false
                    TweenService:Create(
                        DownFrame,
                        TweenInfo.new(0.2,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
                        {Size = UDim2.new(0, 328, 0, 0)}
                    ):Play()
                    TweenService:Create(
                        DropImage,
                        TweenInfo.new(0.3,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),
                        {Rotation = 180}
                    ):Play()
                    for i, v in next, ScrollingDown:GetChildren() do
                        if v:IsA("Frame") then
                            v:Destroy()
                        end
                    end
                    ScrollingDown.CanvasSize = UDim2.new(0,0,0,ItemList.AbsoluteContentSize.Y + 10)
                end
                return RetrunDrop
            end

            function main:Textbox(text,placeholder,def,callback)

            end
            return main
        end
        return Tab
    end
    return Ui
end
return Lib
