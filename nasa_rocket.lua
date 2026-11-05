--// NASA ROCKET  -  client-side LocalScript (Delta / mobile friendly)
--// Item "Nasa rocket": carry with 2 arms -> tap ground to place -> climb stairs
--// -> "Enter Rocket?" -> flight console (Release Arm / Gn R5 / Launch S5 / Throttle lever)
--// Everything is built on YOUR client only (other players won't see it).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

----------------------------------------------------------------
-- CONFIG (tweak these)
----------------------------------------------------------------
local CFG = {
	CARRY_SCALE = 1,          -- size of the rocket in your arms
	PLACED_SCALE = 2,         -- size of the placed rocket (2 = ~48 studs tall)
	CARRY_OFFSET = CFrame.new(0, 9.5, -4.8), -- where the carried rocket sits relative to your root part
	ARM_UP = 100,             -- how high the arms are raised (degrees)
	ARM_IN = 12,              -- how much arms squeeze inward (degrees)
	SPACE_ALT = 4000,         -- night sky + space starts here (also needed for Release Arm)
	MAX_SPEED_BOOST = 500,    -- studs/sec at full throttle with boosters
	MAX_SPEED_NO_BOOST = 320, -- studs/sec at full throttle after Release Arm
	PLAT_H = 14,              -- height of the stair platform / door
	STEP_H = 1.4,
	STEP_RUN = 1.6,
	ENTER_DISTANCE = 14,      -- how close to the door the "Enter Rocket?" button appears
	STEER_RATE = 0.7,         -- thumbstick steering speed (rad/s)
	MAX_TILT = 80,            -- max tilt in degrees
	CAM_DIST = 78,
}

----------------------------------------------------------------
-- cleanup of a previous run
----------------------------------------------------------------
local genv = (getgenv and getgenv()) or _G
if genv.NASA_ROCKET_CLEANUP then pcall(genv.NASA_ROCKET_CLEANUP) end

local conns = {}
local function track(c) conns[#conns + 1] = c return c end

local WHITE = Color3.fromRGB(238, 240, 245)
local BLACK = Color3.fromRGB(25, 25, 30)
local REDC = Color3.fromRGB(205, 35, 40)
local METAL = Color3.fromRGB(70, 74, 82)

local CYAN = Color3.fromRGB(0, 230, 255)
local AMBER = Color3.fromRGB(255, 176, 0)
local RED = Color3.fromRGB(255, 70, 70)
local GREEN = Color3.fromRGB(70, 255, 160)
local BG = Color3.fromRGB(7, 12, 22)
local PANEL = Color3.fromRGB(10, 20, 32)

----------------------------------------------------------------
-- state
----------------------------------------------------------------
local tool, carryModel, poseConn
local equipped = false
local inside = false
local rocket = nil
local throttle = 0
local loc, spaceMode = "EARTH", false
local openTablet, closeTablet, SpaceCleanup, travel, openBook, bookTool, onInvChanged
local worldFolder = Instance.new("Folder")
worldFolder.Name = "NasaRocketWorld"
worldFolder.Parent = workspace

local function getChar()
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	local r = c and c:FindFirstChild("HumanoidRootPart")
	return c, h, r
end

----------------------------------------------------------------
-- part builders
----------------------------------------------------------------
local function mkPart(parent, name, size, cf, color, mat)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function mkCyl(parent, name, h, d, cf, color, mat)
	local p = mkPart(parent, name, Vector3.new(h, d, d), cf * CFrame.Angles(0, 0, math.pi / 2), color, mat)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function mkEllipse(parent, name, size, cf, color)
	local p = mkPart(parent, name, size, cf, color)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

local function weldTo(root, parent)
	for _, p in ipairs(parent:GetDescendants()) do
		if p:IsA("BasePart") and p ~= root then
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = p
			w.Parent = root
		end
	end
end

local function makeEngine(parent, worldCF, scale, isBooster)
	local n = Instance.new("Part")
	n.Name = "Nozzle"
	n.Size = Vector3.new(1, 1, 1)
	n.Transparency = 1
	n.Anchored = true
	n.CanCollide = false
	n.CanTouch = false
	n.CFrame = worldCF
	n.Parent = parent
	local att = Instance.new("Attachment")
	att.Parent = n

	local fire = Instance.new("ParticleEmitter")
	fire.Texture = "rbxasset://textures/particles/fire_main.dds"
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 210, 90), Color3.fromRGB(255, 70, 20))
	fire.LightEmission = 1
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.4 * scale), NumberSequenceKeypoint.new(1, 0.3 * scale) })
	fire.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	fire.Lifetime = NumberRange.new(0.35, 0.7)
	fire.Speed = NumberRange.new(40, 70)
	fire.EmissionDirection = Enum.NormalId.Bottom
	fire.SpreadAngle = Vector2.new(6, 6)
	fire.Rate = 0
	fire.Parent = att

	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(190, 190, 195), Color3.fromRGB(90, 90, 95))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3 * scale), NumberSequenceKeypoint.new(1, 9 * scale) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(1.5, 2.6)
	smoke.Speed = NumberRange.new(15, 30)
	smoke.EmissionDirection = Enum.NormalId.Bottom
	smoke.SpreadAngle = Vector2.new(14, 14)
	smoke.Rate = 0
	smoke.Parent = att

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 150, 60)
	light.Range = 35
	light.Brightness = 0
	light.Parent = n

	return { part = n, fire = fire, smoke = smoke, light = light, booster = isBooster }
end

-- origin = CFrame at the ground under the rocket (up = +Y, stairs/hatch on +Z)
local function buildRocket(S, origin, placed)
	local m = Instance.new("Model")
	m.Name = "NasaRocket"
	local function at(x, y, z) return origin * CFrame.new(x * S, y * S, z * S) end
	local R = 3 * S

	local root = mkPart(m, "Root", Vector3.new(1, 1, 1), at(0, 12, 0), WHITE)
	root.Transparency = 1
	m.PrimaryPart = root

	mkCyl(m, "Body", 15 * S, 6 * S, at(0, 9.5, 0), WHITE)
	mkCyl(m, "StripeLow", 1.4 * S, 6.12 * S, at(0, 5, 0), BLACK)
	mkCyl(m, "StripeRed", 1 * S, 6.12 * S, at(0, 15, 0), REDC)
	mkEllipse(m, "Nose", Vector3.new(6 * S, 14 * S, 6 * S), at(0, 17, 0), REDC)
	mkCyl(m, "Bell", 2 * S, 3.8 * S, at(0, 1, 0), METAL, Enum.Material.Metal)

	-- fins (diagonal so they don't clash with boosters / stairs)
	for k = 0, 3 do
		local w = Instance.new("WedgePart")
		w.Name = "Fin"
		w.Size = Vector3.new(0.4 * S, 6 * S, 3 * S)
		w.Anchored = true
		w.CanCollide = false
		w.Color = REDC
		w.Material = Enum.Material.SmoothPlastic
		w.CFrame = origin * CFrame.Angles(0, math.rad(45 + k * 90), 0)
			* CFrame.new(0, 5 * S, 4.3 * S) * CFrame.Angles(0, math.pi, 0)
		w.Parent = m
	end

	-- "NASA" lettering (front above hatch + back)
	for _, sz in ipairs({ 1, -1 }) do
		local pos = at(0, 12.4, sz * 3.02).Position
		local dir = origin:VectorToWorldSpace(Vector3.new(0, 0, sz))
		local plate = mkPart(m, "NasaPlate", Vector3.new(5 * S, 2.2 * S, 0.1), CFrame.lookAt(pos, pos + dir), WHITE)
		plate.Transparency = 1
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front
		sg.CanvasSize = Vector2.new(500, 220)
		sg.Parent = plate
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Text = "NASA"
		t.TextScaled = true
		t.Font = Enum.Font.GothamBlack
		t.TextColor3 = REDC
		t.Parent = sg
	end

	-- boosters ("arms")
	local boosters = Instance.new("Model")
	boosters.Name = "Boosters"
	boosters.Parent = m
	local boosterModels, engines = {}, {}
	for _, side in ipairs({ -1, 1 }) do
		local bm = Instance.new("Model")
		bm.Name = side < 0 and "BoosterL" or "BoosterR"
		bm:SetAttribute("Side", side)
		bm.Parent = boosters
		local bx = 4.4 * side
		local bb = mkCyl(bm, "BoosterBody", 10.5 * S, 2.2 * S, at(bx, 6.75, 0), WHITE)
		bm.PrimaryPart = bb
		mkEllipse(bm, "BoosterNose", Vector3.new(2.2 * S, 4 * S, 2.2 * S), at(bx, 12, 0), REDC)
		mkCyl(bm, "BoosterBell", 1.2 * S, 1.6 * S, at(bx, 1, 0), METAL, Enum.Material.Metal)
		mkCyl(bm, "BoosterStripe", 1 * S, 2.3 * S, at(bx, 8, 0), BLACK)
		mkPart(bm, "Strut1", Vector3.new(1.6 * S, 0.6 * S, 0.6 * S), at(side * 3.15, 4, 0), METAL)
		mkPart(bm, "Strut2", Vector3.new(1.6 * S, 0.6 * S, 0.6 * S), at(side * 3.15, 10, 0), METAL)
		if placed then
			engines[#engines + 1] = makeEngine(bm, at(bx, 0.2, 0), S * 0.6, true)
			weldTo(bb, bm)
			boosterModels[#boosterModels + 1] = bm
		end
	end

	if placed then
		engines[#engines + 1] = makeEngine(m, at(0, 0.4, 0), S, false)
		-- hatch
		mkPart(m, "HatchFrame", Vector3.new(4.8, 7.8, 0.2), origin * CFrame.new(0, CFG.PLAT_H + 3.9, R + 0.02), CYAN, Enum.Material.Neon)
		mkPart(m, "Hatch", Vector3.new(4, 7, 0.3), origin * CFrame.new(0, CFG.PLAT_H + 3.5, R + 0.1), Color3.fromRGB(20, 24, 34), Enum.Material.Metal)
		for _, p in ipairs(m:GetDescendants()) do
			if p:IsA("BasePart") and not (p.Parent and p.Parent.Parent == boosters) then
				if p.Name == "Body" or p.Name == "Bell" then p.CanCollide = true end
			end
		end
	else
		-- carry version: weld everything to Root and make it loose/massless
		weldTo(root, m)
		for _, p in ipairs(m:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = false
				p.Massless = true
				p.CanCollide = false
				p.CanQuery = false
			end
		end
	end

	return m, boosterModels, engines
end

local function buildPad(origin, S, noDisc)
	local m = Instance.new("Model")
	m.Name = "NasaPad"
	local R = 3 * S
	local conc = Color3.fromRGB(62, 66, 74)
	if not noDisc then
		local pad = mkCyl(m, "Pad", 0.6, 64, origin * CFrame.new(0, 0.3, 0), conc, Enum.Material.Concrete)
		pad.CanCollide = true
	end
	local H = CFG.PLAT_H
	local plat = mkPart(m, "Platform", Vector3.new(10, 1, 8), origin * CFrame.new(0, H - 0.5, R + 4), Color3.fromRGB(90, 96, 108), Enum.Material.DiamondPlate)
	plat.CanCollide = true
	mkPart(m, "PlatformEdge", Vector3.new(10.2, 0.2, 0.2), origin * CFrame.new(0, H + 0.05, R + 8), CYAN, Enum.Material.Neon)
	local n = math.floor(H / CFG.STEP_H + 0.5)
	for i = 1, n - 1 do
		local top = H - i * CFG.STEP_H
		local s = mkPart(m, "Step", Vector3.new(10, top, CFG.STEP_RUN), origin * CFrame.new(0, top / 2, R + 8 + (i - 0.5) * CFG.STEP_RUN), Color3.fromRGB(90, 96, 108), Enum.Material.DiamondPlate)
		s.CanCollide = true
	end
	return m
end

----------------------------------------------------------------
-- GUI
----------------------------------------------------------------
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end
local function corner(o, r) return new("UICorner", { CornerRadius = UDim.new(0, r) }, o) end
local function stroke(o, c, t) return new("UIStroke", { Color = c, Thickness = t or 1.5 }, o) end

local gui = Instance.new("ScreenGui")
gui.Name = "NasaRocketGui"
gui.ResetOnSpawn = false
gui.DisplayOrder = 50
local okHui, hui = pcall(function() return gethui and gethui() end)
gui.Parent = (okHui and hui) or player:WaitForChild("PlayerGui")

-- tap-to-place hint
local hint = new("TextLabel", {
	Text = "TAP FLAT GROUND TO PLACE THE ROCKET", Font = Enum.Font.SciFi, TextScaled = true,
	TextColor3 = CYAN, BackgroundColor3 = BG, BackgroundTransparency = 0.25,
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.16), Size = UDim2.fromScale(0.5, 0.07),
	Visible = false,
}, gui)
corner(hint, 8) stroke(hint, CYAN, 1.5)
new("UITextSizeConstraint", { MaxTextSize = 20, MinTextSize = 8 }, hint)

-- Enter button
local enterBtn = new("TextButton", {
	Text = "Enter Rocket?", Font = Enum.Font.GothamBold, TextScaled = true, TextColor3 = BG,
	BackgroundColor3 = CYAN, AutoButtonColor = true,
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.82), Size = UDim2.fromScale(0.3, 0.12),
	Visible = false,
}, gui)
corner(enterBtn, 10) stroke(enterBtn, Color3.new(1, 1, 1), 2)
new("UITextSizeConstraint", { MaxTextSize = 26, MinTextSize = 10 }, enterBtn)

-- countdown
local cdLabel = new("TextLabel", {
	Text = "T-5", Font = Enum.Font.SciFi, TextScaled = true, TextColor3 = AMBER, BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.28, 0.08), Size = UDim2.fromScale(0.35, 0.22),
	Visible = false,
}, gui)
stroke(cdLabel, Color3.new(0, 0, 0), 3)

-- console
local console = new("Frame", {
	Name = "Console", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(0.99, 0.5),
	Size = UDim2.fromScale(0.44, 0.9), BackgroundColor3 = BG, BackgroundTransparency = 0.1, Visible = false,
}, gui)
new("UISizeConstraint", { MaxSize = Vector2.new(480, 420), MinSize = Vector2.new(290, 220) }, console)
corner(console, 10) stroke(console, CYAN, 2)

new("TextLabel", {
	Text = "NSV-1 // FLIGHT CONSOLE", Font = Enum.Font.SciFi, TextScaled = true, TextColor3 = CYAN,
	TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
	Position = UDim2.fromScale(0.03, 0.015), Size = UDim2.fromScale(0.75, 0.07),
}, console)
local led = new("Frame", { Position = UDim2.new(0.93, 0, 0.03, 0), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = GREEN }, console)
corner(led, 6)
new("Frame", { Position = UDim2.fromScale(0.03, 0.095), Size = UDim2.new(0.94, 0, 0, 1), BackgroundColor3 = CYAN, BackgroundTransparency = 0.5, BorderSizePixel = 0 }, console)

local function mkCell(label, x)
	local f = new("Frame", { Position = UDim2.fromScale(x, 0.11), Size = UDim2.fromScale(0.3, 0.19), BackgroundColor3 = PANEL }, console)
	corner(f, 5)
	stroke(f, CYAN, 1).Transparency = 0.5
	new("TextLabel", {
		Text = label, Font = Enum.Font.SciFi, TextScaled = true, TextColor3 = Color3.fromRGB(120, 170, 190),
		BackgroundTransparency = 1, Position = UDim2.fromScale(0.05, 0.04), Size = UDim2.fromScale(0.9, 0.28),
	}, f)
	local v = new("TextLabel", {
		Text = "0", Font = Enum.Font.Code, TextScaled = true, TextColor3 = CYAN, BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.05, 0.32), Size = UDim2.fromScale(0.9, 0.4),
	}, f)
	return f, v
end
local _, altV = mkCell("ALT (ST)", 0.03)
local _, velV = mkCell("VEL (ST/S)", 0.35)
local fuelCell, fuelV = mkCell("FUEL", 0.67)
local fuelBack = new("Frame", { Position = UDim2.fromScale(0.08, 0.8), Size = UDim2.fromScale(0.84, 0.12), BackgroundColor3 = Color3.fromRGB(25, 35, 50), BorderSizePixel = 0 }, fuelCell)
local fuelFill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = GREEN, BorderSizePixel = 0 }, fuelBack)

local function mkButton(text, y, h, color)
	local b = new("TextButton", {
		Name = text, Text = text, Font = Enum.Font.GothamBold, TextScaled = true, TextColor3 = color,
		AutoButtonColor = false, BackgroundColor3 = PANEL,
		Position = UDim2.fromScale(0.03, y), Size = UDim2.fromScale(0.61, h),
	}, console)
	corner(b, 6)
	stroke(b, color, 1.5)
	new("UITextSizeConstraint", { MaxTextSize = 20, MinTextSize = 8 }, b)
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3) }, b)
	return b
end
local relBtn = mkButton("RELEASE ARM", 0.30, 0.12, AMBER)
local gnBtn = mkButton("GN R5", 0.43, 0.10, CYAN)
local launchBtn = mkButton("LAUNCH S5", 0.54, 0.13, GREEN)
local navBtn = mkButton("NAV TABLET", 0.68, 0.11, CYAN)
local exitBtn = mkButton("EXIT", 0.80, 0.10, RED)

local statusLbl = new("TextLabel", {
	Text = "STATUS: STANDBY", Font = Enum.Font.Code, TextScaled = true, TextColor3 = GREEN,
	TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
	Position = UDim2.fromScale(0.03, 0.915), Size = UDim2.fromScale(0.94, 0.07),
}, console)
new("UITextSizeConstraint", { MaxTextSize = 15, MinTextSize = 7 }, statusLbl)
local function setStatus(msg, col)
	statusLbl.Text = "STATUS: " .. msg
	statusLbl.TextColor3 = col or GREEN
end

local function press(btn)
	local orig = btn.BackgroundColor3
	btn.BackgroundColor3 = Color3.fromRGB(0, 90, 110)
	TweenService:Create(btn, TweenInfo.new(0.25), { BackgroundColor3 = orig }):Play()
end

-- throttle lever
local lever = new("TextButton", {
	Text = "", AutoButtonColor = false, BackgroundColor3 = PANEL,
	Position = UDim2.fromScale(0.67, 0.32), Size = UDim2.fromScale(0.3, 0.58),
}, console)
corner(lever, 6) stroke(lever, CYAN, 1.5)
new("TextLabel", {
	Text = "THROTTLE", Font = Enum.Font.SciFi, TextScaled = true, TextColor3 = CYAN, BackgroundTransparency = 1,
	Position = UDim2.fromScale(0.05, 0.01), Size = UDim2.fromScale(0.9, 0.09),
}, lever)
local TR_TOP, TR_H = 0.13, 0.7
local trackBar = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, TR_TOP), Size = UDim2.new(0, 8, TR_H, 0),
	BackgroundColor3 = Color3.fromRGB(25, 35, 50), BorderSizePixel = 0,
}, lever)
corner(trackBar, 4)
for i = 0, 10 do
	local major = (i % 5 == 0)
	new("Frame", {
		Position = UDim2.new(major and 0.12 or 0.2, 0, TR_TOP + (i / 10) * TR_H, -1),
		Size = UDim2.new(major and 0.26 or 0.18, 0, 0, 2),
		BackgroundColor3 = major and AMBER or CYAN, BackgroundTransparency = major and 0 or 0.4, BorderSizePixel = 0,
	}, lever)
end
local fill = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, TR_TOP + TR_H), Size = UDim2.new(0, 8, 0, 0),
	BackgroundColor3 = GREEN, BorderSizePixel = 0,
}, lever)
corner(fill, 4)
local handle = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, TR_TOP + TR_H), Size = UDim2.fromScale(0.78, 0.13),
	BackgroundColor3 = Color3.fromRGB(45, 52, 66), ZIndex = 3,
}, lever)
corner(handle, 5) stroke(handle, AMBER, 2)
for i = 1, 3 do
	new("Frame", { Position = UDim2.fromScale(0.12, 0.2 + i * 0.17), Size = UDim2.fromScale(0.76, 0.07), BackgroundColor3 = AMBER, BorderSizePixel = 0, ZIndex = 4 }, handle)
end
local pctLbl = new("TextLabel", {
	Text = "000%", Font = Enum.Font.Code, TextScaled = true, TextColor3 = GREEN, BackgroundTransparency = 1,
	Position = UDim2.fromScale(0.1, 0.86), Size = UDim2.fromScale(0.8, 0.12),
}, lever)

local dragging, dragInput = false, nil
local function setFromY(y)
	local top, h = trackBar.AbsolutePosition.Y, trackBar.AbsoluteSize.Y
	if h <= 0 then return end
	throttle = 1 - math.clamp((y - top) / h, 0, 1)
end
track(lever.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging, dragInput = true, i
		setFromY(i.Position.Y)
	end
end))
track(UIS.InputChanged:Connect(function(i)
	if dragging and (i == dragInput or (i.UserInputType == Enum.UserInputType.MouseMovement and dragInput.UserInputType == Enum.UserInputType.MouseButton1)) then
		setFromY(i.Position.Y)
	end
end))
track(UIS.InputEnded:Connect(function(i)
	if i == dragInput then dragging = false end
end))

----------------------------------------------------------------
-- rocket logic
----------------------------------------------------------------
local function setCharHidden(hidden)
	local c = player.Character
	if not c then return end
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("BasePart") then d.LocalTransparencyModifier = hidden and 1 or 0 end
	end
end

local function destroyRocket()
	if rocket then
		rocket.dead = true
		if rocket.model then rocket.model:Destroy() end
		if rocket.pad then rocket.pad:Destroy() end
		if rocket.moonPad then rocket.moonPad:Destroy() end
		for _, bm in ipairs(rocket.boosterModels or {}) do pcall(function() bm:Destroy() end) end
		rocket = nil
	end
end

local function placeRocket(pos)
	destroyRocket()
	local _, _, hrp = getChar()
	local S = CFG.PLACED_SCALE
	local origin = CFrame.new(pos)
	if hrp then
		local d = Vector3.new(hrp.Position.X - pos.X, 0, hrp.Position.Z - pos.Z)
		if d.Magnitude > 0.1 then origin = CFrame.lookAt(pos, pos - d.Unit) end -- stairs face the player
	end
	local pad = buildPad(origin, S)
	pad.Parent = worldFolder
	local model, boosterModels, engines = buildRocket(S, origin, true)
	model.Parent = worldFolder
	local pivot = model:GetPivot()
	rocket = {
		model = model, pad = pad, origin = origin, boosterModels = boosterModels, engines = engines,
		state = "IDLE", speed = 0, fuel = 100, boosters = true, ignite = false,
		pitch = 0, roll = 0, pos = pivot.Position, startY = pivot.Position.Y, baseRot = origin.Rotation,
		S = S, alt = 0, busy = false, docked = false, moonPad = nil, entering = false, dead = false,
	}
	throttle = 0
	loc = "EARTH"
end

local function standPos(r)
	return (r.model:GetPivot() * CFrame.new(0, CFG.PLAT_H + 3 - 12 * r.S, 3 * r.S + 4)).Position
end

local function enterRocket()
	if inside or not rocket or rocket.busy or (rocket.state ~= "IDLE" and rocket.state ~= "PARKED") then return end
	local c, hum, hrp = getChar()
	if not hrp then return end
	inside = true
	if hum then hum:UnequipTools() end
	hrp.Anchored = true
	setCharHidden(true)
	camera.CameraType = Enum.CameraType.Scriptable
	console.Visible = true
	enterBtn.Visible = false
	if rocket.state == "IDLE" then
		setStatus("SYSTEMS NOMINAL - AWAITING LAUNCH", GREEN)
	else
		setStatus("BACK ABOARD - OPEN NAV TO TRAVEL", GREEN)
		if openTablet then openTablet() end
	end
end

local function exitRocket()
	if not inside then return end
	if rocket and (rocket.state == "COUNT" or rocket.state == "TRAVEL") then setStatus("EXIT LOCKED - SEQUENCE ACTIVE", RED) return end
	if rocket and rocket.state == "FLY" and rocket.speed > 5 then setStatus("EXIT LOCKED - SET THROTTLE TO 0", RED) return end
	local _, hum, hrp = getChar()
	inside = false
	console.Visible = false
	if closeTablet then closeTablet() end
	cdLabel.Visible = false
	camera.CameraType = Enum.CameraType.Custom
	if hum then camera.CameraSubject = hum end
	setCharHidden(false)
	if hrp then
		hrp.Anchored = false
		if rocket then hrp.CFrame = CFrame.new(standPos(rocket)) end
		hrp.AssemblyLinearVelocity = Vector3.zero
	end
end

local function launch()
	local rec = rocket
	if not rec or rec.state ~= "IDLE" then return end
	if rec.fuel <= 0 then setStatus("NO FUEL", RED) return end
	rec.state = "COUNT"
	task.spawn(function()
		for i = 5, 1, -1 do
			if rec.dead then return end
			cdLabel.Text = "T-" .. i
			cdLabel.TextColor3 = (i <= 2) and RED or AMBER
			cdLabel.Visible = true
			setStatus("IGNITION SEQUENCE T-" .. i, AMBER)
			if i <= 2 then rec.ignite = true end
			task.wait(1)
		end
		if rec.dead then return end
		rec.state = "FLY"
		throttle = math.max(throttle, 0.35)
		cdLabel.Text = "LIFTOFF!"
		cdLabel.TextColor3 = GREEN
		setStatus("LIFTOFF! STEER WITH THUMBSTICK", GREEN)
		task.delay(2, function() cdLabel.Visible = false end)
	end)
end

local function releaseArms()
	local rec = rocket
	if not rec or not inside then return end
	if rec.busy then return end
	if not rec.boosters then setStatus("BOOSTERS ALREADY JETTISONED", AMBER) return end
	local alt = rec.alt
	if alt < CFG.SPACE_ALT then
		setStatus(("ARM RELEASE LOCKED - ALT %d/%d"):format(math.floor(alt), CFG.SPACE_ALT), RED)
		return
	end
	rec.boosters = false
	local pivot = rec.model:GetPivot()
	for _, bm in ipairs(rec.boosterModels) do
		local side = bm:GetAttribute("Side") or 1
		bm.Parent = workspace
		for _, p in ipairs(bm:GetDescendants()) do
			if p:IsA("BasePart") then p.Anchored = false p.CanCollide = false end
			if p:IsA("ParticleEmitter") then p.Rate = 0 end
		end
		if bm.PrimaryPart then
			bm.PrimaryPart.AssemblyLinearVelocity = pivot.UpVector * rec.speed * 0.7 + pivot.RightVector * side * 45
			bm.PrimaryPart.AssemblyAngularVelocity = Vector3.new(0, 0, side * 2)
		end
		Debris:AddItem(bm, 12)
	end
	local keep = {}
	for _, e in ipairs(rec.engines) do if not e.booster then keep[#keep + 1] = e end end
	rec.engines = keep
	setStatus("ARMS RELEASED - BOOSTERS JETTISONED", GREEN)
end

track(enterBtn.Activated:Connect(enterRocket))
track(relBtn.Activated:Connect(function() press(relBtn) releaseArms() end))
track(gnBtn.Activated:Connect(function() press(gnBtn) end)) -- does nothing, lol
track(launchBtn.Activated:Connect(function() press(launchBtn) launch() end))
track(exitBtn.Activated:Connect(function() press(exitBtn) exitRocket() end))

-- (wrapped in a function so the main chunk stays under Luau's 200-locals limit)
local function initSpaceSystems()
----------------------------------------------------------------
-- SPACE SYSTEMS: night sky, Earth, Moon, Sun, ISS, warp, landings
----------------------------------------------------------------
local Lighting = game:GetService("Lighting")
local SPACE_ORIGIN = Vector3.new(150000, 5000, 0)       -- far-away "void" where space is built
local MOON_ORIGIN = Vector3.new(150000, 5000, -150000)  -- lunar landing site
local EARTH_R = 1000
local MOON_DIST, MOON_D = 5200, 540
local ISS_R = 1450
local ISS_DOCK = CFrame.new(0, 75, 40)
local baseFOV = camera.FieldOfView
local scene = nil
local SP = { spin = 0, moonAng = 1, issAng = 0, accum = 0, starT = 0 }
local envSnap = nil
local origGravity = workspace.Gravity
local sunDir = Vector3.new(0.6, 0.5, -0.6).Unit
local warpM = nil
local rng = Random.new(7)

local flash = new("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1,
	BorderSizePixel = 0, ZIndex = 100, Active = false,
}, gui)

-- ===== lighting / sky =====
local function snapEnv()
	if envSnap then return end
	envSnap = { props = {}, skies = {}, atmos = {} }
	for _, k in ipairs({ "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "ExposureCompensation", "FogEnd", "FogStart", "FogColor",
		"EnvironmentDiffuseScale", "EnvironmentSpecularScale", "GlobalShadows", "ColorShift_Top", "ColorShift_Bottom" }) do
		pcall(function() envSnap.props[k] = Lighting[k] end)
	end
	for _, o in ipairs(Lighting:GetChildren()) do
		if o:IsA("Atmosphere") then envSnap.atmos[o] = { o.Density, o.Haze } end
	end
end

local function rampEnv(t) -- 0..1 : daylight -> dark while leaving the atmosphere
	snapEnv()
	local cc = Lighting:FindFirstChild("NasaSpaceCC")
	if t <= 0 then
		if cc then cc:Destroy() end
		return
	end
	if not cc then
		cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "NasaSpaceCC"
		cc.Parent = Lighting
	end
	cc.Brightness = -0.85 * t ^ 1.4
	cc.Saturation = -0.4 * t
	cc.TintColor = Color3.new(1 - 0.35 * t, 1 - 0.25 * t, 1)
	for a, v in pairs(envSnap.atmos) do a.Density = v[1] * (1 - t) a.Haze = v[2] * (1 - t) end
end

local function applySpaceEnv()
	snapEnv()
	local cc = Lighting:FindFirstChild("NasaSpaceCC")
	if cc then cc:Destroy() end
	for a in pairs(envSnap.atmos) do a.Density = 0 a.Haze = 0 end
	for _, o in ipairs(Lighting:GetChildren()) do
		if o:IsA("Sky") and o.Name ~= "NasaSpaceSky" then
			o.Parent = nil
			envSnap.skies[#envSnap.skies + 1] = o
		end
	end
	if not Lighting:FindFirstChild("NasaSpaceSky") then
		local sky = Instance.new("Sky")
		sky.Name = "NasaSpaceSky"
		for _, f in ipairs({ "SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp" }) do sky[f] = "" end
		sky.CelestialBodiesShown = false
		sky.StarCount = 5000
		sky.Parent = Lighting
	end
	Lighting.ClockTime = 16.5
	Lighting.Brightness = 3
	Lighting.Ambient = Color3.fromRGB(22, 24, 38)
	Lighting.OutdoorAmbient = Color3.fromRGB(14, 16, 28)
	Lighting.ExposureCompensation = 0
	Lighting.FogEnd = 1e7
	Lighting.FogStart = 1e6
	Lighting.EnvironmentDiffuseScale = 0.15
	Lighting.EnvironmentSpecularScale = 0.2
	Lighting.GlobalShadows = true
	Lighting.ColorShift_Top = Color3.new(0, 0, 0)
	Lighting.ColorShift_Bottom = Color3.new(0, 0, 0)
	sunDir = Lighting:GetSunDirection()
	workspace.Gravity = 0
end

local function restoreEnv()
	if not envSnap then return end
	local cc = Lighting:FindFirstChild("NasaSpaceCC")
	if cc then cc:Destroy() end
	local sky = Lighting:FindFirstChild("NasaSpaceSky")
	if sky then sky:Destroy() end
	for _, n in ipairs({ "NasaPlanetAtmo", "NasaPlanetCC" }) do
		local o = Lighting:FindFirstChild(n)
		if o then o:Destroy() end
	end
	for _, s in ipairs(envSnap.skies) do s.Parent = Lighting end
	for a, v in pairs(envSnap.atmos) do a.Density = v[1] a.Haze = v[2] end
	for k, v in pairs(envSnap.props) do pcall(function() Lighting[k] = v end) end
	envSnap = nil
	workspace.Gravity = origGravity
end

-- ===== space object builders =====
local function rdir()
	local v = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1))
	if v.Magnitude < 0.1 then return Vector3.yAxis end
	return v.Unit
end

local function mkBall(parent, name, d, color, mat, transp)
	local p = mkPart(parent, name, Vector3.new(d, d, d), CFrame.new(), color, mat)
	p.Shape = Enum.PartType.Ball
	p.Transparency = transp or 0
	p.CastShadow = false
	return p
end

local function blob(parent, dir, radius, w, thick, color, mat, transp)
	local pos = dir * radius
	local up = math.abs(dir.Y) > 0.99 and Vector3.xAxis or Vector3.yAxis
	local p = mkEllipse(parent, "Blob", Vector3.new(w, w * rng:NextNumber(0.6, 1), thick), CFrame.lookAt(pos, pos + dir, up), color)
	p.Material = mat or Enum.Material.SmoothPlastic
	p.Transparency = transp or 0
	p.CastShadow = false
	return p
end

local function rootPart(m)
	local r = mkPart(m, "Root", Vector3.new(1, 1, 1), CFrame.new(), WHITE)
	r.Transparency = 1
	r.CanQuery = false
	m.PrimaryPart = r
	return r
end

-- ===== survival gear (needed for the dangerous planets) =====
local ITEMS = {
	O2 = { name = "Oxygen Tank", where = "ISS - floating above the station core", color = Color3.fromRGB(120, 200, 255) },
	SHIELD = { name = "Heat Shield Plating", where = "ISS - floating above the station core", color = Color3.fromRGB(255, 200, 70) },
	SAMPLE = { name = "Lunar Sample", where = "Moon - near your landing site", color = Color3.fromRGB(170, 255, 190) },
	RADSUIT = { name = "Radiation Suit Module", where = "Moon - near your landing site", color = Color3.fromRGB(255, 140, 50) },
	HULL = { name = "Pressure Hull Plate", where = "Mars - near your landing site", color = Color3.fromRGB(150, 170, 255) },
	COATING = { name = "Acid Coating Canister", where = "Mercury - near your landing site", color = Color3.fromRGB(200, 120, 255) },
	CRYO = { name = "Cryo Insulation Pack", where = "Mars - near your landing site", color = Color3.fromRGB(150, 235, 255) },
	SULFUR = { name = "Sulfur Filter Unit", where = "Venus - near your landing site", color = Color3.fromRGB(240, 235, 90) },
	DRILL = { name = "Ice Drill Bit", where = "Europa - near your landing site", color = Color3.fromRGB(255, 255, 255) },
	GRAV = { name = "Gravity Stabilizer", where = "Asteroid Belt - big asteroid near your landing site", color = Color3.fromRGB(255, 120, 200) },
	JOVE = { name = "Jovian Pressure Seal", where = "Jupiter - near your landing platform", color = Color3.fromRGB(255, 170, 90) },
	RING = { name = "Ring Debris Shield", where = "Saturn - near your landing platform", color = Color3.fromRGB(255, 230, 160) },
	METH = { name = "Methane Filter", where = "Uranus - near your landing platform", color = Color3.fromRGB(120, 255, 230) },
}
local REQS = {
	MARS = { "O2", "SAMPLE" },
	MERCURY = { "SHIELD", "RADSUIT" },
	VENUS = { "SHIELD", "HULL", "COATING" },
	IO = { "SHIELD", "RADSUIT", "SULFUR" },
	EUROPA = { "CRYO", "RADSUIT", "HULL" },
	PLUTO = { "CRYO", "O2", "DRILL" },
	ASTEROID = { "HULL", "O2" },
	JUPITER = { "SHIELD", "RADSUIT", "HULL", "GRAV" },
	SATURN = { "GRAV", "JOVE", "CRYO" },
	URANUS = { "JOVE", "RING", "CRYO" },
	NEPTUNE = { "RING", "METH", "DRILL" },
}
local inv = genv.NASA_INV or {}
genv.NASA_INV = inv -- gear is kept if you re-run the script

local function missingFor(dest)
	local miss = {}
	for _, id in ipairs(REQS[dest] or {}) do
		if not inv[id] then miss[#miss + 1] = ITEMS[id].name end
	end
	return miss
end

local function reqLine(dest)
	local t = {}
	for _, id in ipairs(REQS[dest] or {}) do
		t[#t + 1] = (inv[id] and "[OK] " or "[--] ") .. ITEMS[id].name:upper()
	end
	return "REQ: " .. table.concat(t, "  ")
end

local toastLbl = new("TextLabel", {
	Text = "", Font = Enum.Font.GothamBold, TextScaled = true, TextColor3 = GREEN, BackgroundColor3 = BG,
	BackgroundTransparency = 0.2, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.04),
	Size = UDim2.fromScale(0.5, 0.075), Visible = false, ZIndex = 70,
}, gui)
corner(toastLbl, 8) stroke(toastLbl, CYAN, 1.5)
new("UITextSizeConstraint", { MaxTextSize = 20, MinTextSize = 8 }, toastLbl)
local function toast(msg, col)
	toastLbl.Text = msg
	toastLbl.TextColor3 = col or GREEN
	toastLbl.Visible = true
	local stamp = os.clock()
	toastLbl:SetAttribute("t", stamp)
	task.delay(3.2, function()
		if toastLbl:GetAttribute("t") == stamp then toastLbl.Visible = false end
	end)
end

local function makePickup(parent, id, cf)
	if inv[id] then return end
	local it = ITEMS[id]
	local p = mkPart(parent, "Pickup_" .. id, Vector3.new(4, 4, 4), cf * CFrame.Angles(0.3, 0.5, 0.2), it.color, Enum.Material.Neon)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(160, 26)
	bb.StudsOffset = Vector3.new(0, 5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 400
	bb.Parent = p
	new("TextLabel", {
		Text = it.name, Font = Enum.Font.GothamBold, TextScaled = true, TextColor3 = it.color,
		BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
	}, bb)
	local light = Instance.new("PointLight")
	light.Color = it.color
	light.Range = 20
	light.Brightness = 2
	light.Parent = p
	local pp = Instance.new("ProximityPrompt")
	pp.ActionText = "COLLECT"
	pp.ObjectText = it.name
	pp.HoldDuration = 0.4
	pp.MaxActivationDistance = 18
	pp.RequiresLineOfSight = false
	pp.Parent = p
	pp.Triggered:Connect(function()
		inv[id] = true
		p:Destroy()
		toast("COLLECTED: " .. it.name:upper(), GREEN)
		if onInvChanged then onInvChanged() end
	end)
end

local function addPickups(model, origin, list)
	for _, e in ipairs(list or {}) do
		makePickup(model, e[1], CFrame.new(origin + e[2]))
	end
end

local function buildEarth()
	local m = Instance.new("Model")
	m.Name = "NasaEarth"
	rootPart(m)
	mkBall(m, "Ocean", EARTH_R * 2, Color3.fromRGB(16, 58, 148))
	local land = {
		Color3.fromRGB(62, 118, 52), Color3.fromRGB(90, 134, 58),
		Color3.fromRGB(148, 124, 80), Color3.fromRGB(188, 172, 118),
	}
	for _ = 1, 8 do
		local cd = rdir()
		for _ = 1, rng:NextInteger(6, 10) do
			local d = (cd + rdir() * 0.28).Unit
			blob(m, d, EARTH_R - 10, rng:NextNumber(170, 400), 40, land[rng:NextInteger(1, #land)])
		end
	end
	blob(m, Vector3.yAxis, EARTH_R - 10, 520, 40, WHITE)
	blob(m, -Vector3.yAxis, EARTH_R - 10, 560, 40, WHITE)
	mkBall(m, "Atmosphere", EARTH_R * 2 + 46, Color3.fromRGB(90, 150, 255), Enum.Material.Neon, 0.88)

	local cm = Instance.new("Model")
	cm.Name = "NasaClouds"
	rootPart(cm)
	for _ = 1, 70 do
		blob(cm, rdir(), EARTH_R + 16, rng:NextNumber(150, 380), 14, WHITE, Enum.Material.SmoothPlastic, 0.3)
	end
	mkBall(cm, "Haze", EARTH_R * 2 + 22, WHITE, Enum.Material.SmoothPlastic, 0.92)
	return m, cm
end

local function buildMoon()
	local m = Instance.new("Model")
	m.Name = "NasaMoon"
	rootPart(m)
	mkBall(m, "MoonBall", MOON_D, Color3.fromRGB(172, 172, 178))
	for _ = 1, 34 do
		blob(m, rdir(), MOON_D / 2 - 2, rng:NextNumber(30, 100), 10, Color3.fromRGB(115, 115, 122))
	end
	return m
end

local function buildISS()
	local s = 2
	local m = Instance.new("Model")
	m.Name = "NasaISS"
	rootPart(m)
	local function P(name, size, pos, color, mat)
		return mkPart(m, name, size * s, CFrame.new(pos * s), color, mat)
	end
	local function zcyl(name, len, d, pos, col)
		return mkCyl(m, name, len * s, d * s, CFrame.new(pos * s) * CFrame.Angles(math.pi / 2, 0, 0), col, Enum.Material.SmoothPlastic)
	end
	P("Truss", Vector3.new(130, 3, 3), Vector3.zero, Color3.fromRGB(170, 172, 180), Enum.Material.Metal)
	zcyl("Core", 60, 10, Vector3.zero, WHITE)
	zcyl("LabL", 30, 8, Vector3.new(-14, 0, 0), Color3.fromRGB(225, 225, 230))
	zcyl("LabR", 30, 8, Vector3.new(14, 0, 0), Color3.fromRGB(225, 225, 230))
	mkEllipse(m, "Node", Vector3.new(12, 12, 12) * s, CFrame.new(0, 0, 0), Color3.fromRGB(200, 200, 205))
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			P("Panel", Vector3.new(30, 0.5, 14), Vector3.new(sx * 62, 0, sz * 10), Color3.fromRGB(28, 55, 135))
			P("PanelFrame", Vector3.new(30.4, 0.3, 0.8), Vector3.new(sx * 62, 0.1, sz * 10), Color3.fromRGB(200, 170, 60), Enum.Material.Metal)
		end
		P("Radiator", Vector3.new(0.5, 16, 30), Vector3.new(sx * 26, 0, 0), Color3.fromRGB(235, 235, 240))
	end
	makePickup(m, "O2", CFrame.new(-34, 22, 0))
	makePickup(m, "SHIELD", CFrame.new(34, 22, 0))
	return m
end

local function buildStars()
	local m = Instance.new("Model")
	m.Name = "NasaStars"
	rootPart(m)
	for i = 1, 420 do
		local sz = rng:NextNumber(18, 60)
		local col = (i % 7 == 0 and Color3.fromRGB(170, 200, 255)) or (i % 11 == 0 and Color3.fromRGB(255, 225, 170)) or Color3.new(1, 1, 1)
		local p = mkPart(m, "Star", Vector3.new(sz, sz, sz), CFrame.new(rdir() * 16000), col, Enum.Material.Neon)
		p.CanQuery = false
		p.CastShadow = false
	end
	return m
end

local function buildJupiter()
	local m = Instance.new("Model")
	m.Name = "NasaJupiter"
	rootPart(m)
	mkBall(m, "JupBall", 2000, Color3.fromRGB(214, 176, 138))
	local belt = { Color3.fromRGB(160, 108, 76), Color3.fromRGB(235, 215, 190), Color3.fromRGB(140, 92, 66) }
	local rj = Random.new(5)
	for _, lat in ipairs({ -50, -30, -12, 8, 25, 45 }) do
		local y, rad = math.sin(math.rad(lat)), math.cos(math.rad(lat))
		for i = 1, 14 do
			local lon = (i / 14) * math.pi * 2 + rj:NextNumber(-0.1, 0.1)
			local dir = Vector3.new(math.cos(lon) * rad, y, math.sin(lon) * rad).Unit
			blob(m, dir, 996, 430, 14, belt[rj:NextInteger(1, #belt)])
		end
	end
	blob(m, Vector3.new(0.9, -0.25, 0.35).Unit, 996, 300, 16, Color3.fromRGB(190, 70, 45))
	return m
end

local function buildSurface(o, cfg)
	local rr = Random.new(cfg.seed or 1)
	local m = Instance.new("Model")
	m.Name = "NasaSurface"
	for ix = -1, 1 do
		for iz = -1, 1 do
			if cfg.deck then -- gas giant: a solid, banded cloud deck
				for k = 0, 3 do
					local p = mkPart(m, "Deck", Vector3.new(2040, 40, 510), CFrame.new(o.X + ix * 2040, o.Y - 20, o.Z + iz * 2040 - 765 + k * 510),
						cfg.deck[((iz + 1) * 4 + k) % #cfg.deck + 1], Enum.Material.SmoothPlastic)
					p.CanCollide = true
				end
			else
				local p = mkPart(m, "Ground", Vector3.new(2040, 40, 2040), CFrame.new(o.X + ix * 2040, o.Y - 20, o.Z + iz * 2040), cfg.ground, cfg.mat or Enum.Material.Concrete)
				p.CanCollide = true
			end
		end
	end
	local function far(x, z, minR) return math.sqrt((x - o.X) ^ 2 + (z - o.Z) ^ 2) > minR end
	for _ = 1, cfg.craters do
		local x, z = o.X + rr:NextNumber(-3000, 3000), o.Z + rr:NextNumber(-3000, 3000)
		if far(x, z, 260) then
			local d = rr:NextNumber(90, 380)
			mkCyl(m, "CraterRim", 0.8, d * 1.12, CFrame.new(x, o.Y + 0.15, z), cfg.rim, Enum.Material.Concrete)
			mkCyl(m, "Crater", 0.5, d, CFrame.new(x, o.Y + 0.3, z), cfg.crater, Enum.Material.Concrete)
		end
	end
	for _ = 1, cfg.rocks do
		local x, z = o.X + rr:NextNumber(-3000, 3000), o.Z + rr:NextNumber(-3000, 3000)
		if far(x, z, 120) then
			local sz = rr:NextNumber(3, 26)
			local p = mkPart(m, "Rock", Vector3.new(sz, sz * rr:NextNumber(0.5, 1), sz * rr:NextNumber(0.7, 1.2)),
				CFrame.new(x, o.Y + sz * 0.2, z) * CFrame.Angles(rr:NextNumber(0, 6), rr:NextNumber(0, 6), rr:NextNumber(0, 6)),
				cfg.rockA:Lerp(cfg.rockB, rr:NextNumber()), cfg.rockMat or Enum.Material.Slate)
			p.CanCollide = true
		end
	end
	for _ = 1, cfg.hills do
		local x, z = o.X + rr:NextNumber(-2800, 2800), o.Z + rr:NextNumber(-2800, 2800)
		if far(x, z, 600) then
			local w = rr:NextNumber(300, 800)
			mkEllipse(m, "Hill", Vector3.new(w, rr:NextNumber(80, 200), w), CFrame.new(x, o.Y, z), cfg.hill)
		end
	end
	for i = 1, 28 do -- horizon ridge
		local a = i / 28 * math.pi * 2
		mkEllipse(m, "Ridge", Vector3.new(1400, 600, 1400), CFrame.new(o.X + math.cos(a) * 3200, o.Y, o.Z + math.sin(a) * 3200), cfg.ridge)
	end
	if cfg.lava then
		for _ = 1, 40 do
			local x, z = o.X + rr:NextNumber(-3000, 3000), o.Z + rr:NextNumber(-3000, 3000)
			if far(x, z, 200) then
				local p = mkPart(m, "LavaRiver", Vector3.new(rr:NextNumber(5, 12), 0.4, rr:NextNumber(120, 420)),
					CFrame.new(x, o.Y + 0.25, z) * CFrame.Angles(0, rr:NextNumber(0, 6), 0), Color3.fromRGB(255, 110, 30), Enum.Material.Neon)
				p.CastShadow = false
			end
		end
		for _ = 1, 7 do
			local x, z = o.X + rr:NextNumber(-2800, 2800), o.Z + rr:NextNumber(-2800, 2800)
			if far(x, z, 400) then
				local p = mkCyl(m, "LavaLake", 0.5, rr:NextNumber(150, 320), CFrame.new(x, o.Y + 0.3, z), Color3.fromRGB(255, 90, 20), Enum.Material.Neon)
				p.CastShadow = false
			end
		end
	end
	for _, sb in ipairs(cfg.sky or {}) do
		local b = mkBall(m, "SkyMoon", sb[2], sb[3] or Color3.fromRGB(150, 140, 130))
		b.Position = o + sb[1]
		b.CanQuery = false
	end
	if cfg.cracks then -- Europa's dark ice cracks
		for _ = 1, 45 do
			local x, z = o.X + rr:NextNumber(-3000, 3000), o.Z + rr:NextNumber(-3000, 3000)
			if far(x, z, 200) then
				mkPart(m, "IceCrack", Vector3.new(rr:NextNumber(3, 7), 0.3, rr:NextNumber(150, 500)),
					CFrame.new(x, o.Y + 0.2, z) * CFrame.Angles(0, rr:NextNumber(0, 6), 0), Color3.fromRGB(150, 85, 62), Enum.Material.SmoothPlastic)
			end
		end
	end
	if cfg.heart then -- Pluto's bright heart-shaped plain
		local hc = Color3.fromRGB(238, 228, 218)
		local c0 = o + Vector3.new(0, 0.35, -1100)
		mkCyl(m, "HeartL", 0.4, 720, CFrame.new(c0 + Vector3.new(-290, 0, 0)), hc, Enum.Material.Snow)
		mkCyl(m, "HeartR", 0.4, 720, CFrame.new(c0 + Vector3.new(290, 0, 0)), hc, Enum.Material.Snow)
		mkPart(m, "HeartV", Vector3.new(620, 0.4, 620), CFrame.new(c0 + Vector3.new(0, 0, -330)) * CFrame.Angles(0, math.rad(45), 0), hc, Enum.Material.Snow)
	end
	if cfg.jupiter then -- giant Jupiter filling the sky
		local ed = (sunDir:Cross(Vector3.yAxis).Unit * 0.9 + Vector3.new(0, 0.35, 0)).Unit
		local j = buildJupiter()
		j.Parent = m
		j:PivotTo(CFrame.new(o + ed * cfg.jupiter) * CFrame.Angles(0, 0, math.rad(3)))
	end
	if cfg.storms then -- swirling storms on the cloud deck
		for _ = 1, cfg.storms do
			local x, z = o.X + rr:NextNumber(-3000, 3000), o.Z + rr:NextNumber(-3000, 3000)
			if far(x, z, 250) then
				local d = rr:NextNumber(150, 520)
				local c = cfg.stormCols[rr:NextInteger(1, #cfg.stormCols)]
				mkCyl(m, "Storm", 0.5, d, CFrame.new(x, o.Y + 0.25, z), c, Enum.Material.SmoothPlastic)
				mkCyl(m, "StormEye", 0.6, d * 0.45, CFrame.new(x, o.Y + 0.35, z), cfg.stormEye, Enum.Material.SmoothPlastic)
			end
		end
	end
	if cfg.floating then -- tumbling asteroids all around
		for _ = 1, cfg.floating do
			local w = rr:NextNumber(20, 200)
			local g = rr:NextInteger(80, 140)
			local fr = mkEllipse(m, "FloatRock", Vector3.new(w, w * rr:NextNumber(0.6, 0.9), w * rr:NextNumber(0.7, 1)),
				CFrame.new(o.X + rr:NextNumber(-3500, 3500), o.Y + rr:NextNumber(120, 2500), o.Z + rr:NextNumber(-3500, 3500))
					* CFrame.Angles(rr:NextNumber(0, 6), rr:NextNumber(0, 6), rr:NextNumber(0, 6)), Color3.fromRGB(g, g - 6, g - 14))
			fr.CanQuery = false
		end
	end
	if cfg.rings then -- ring arcs across the sky
		local rm = Instance.new("Model")
		rm.Name = "NasaRings"
		rootPart(rm)
		for _, rg in ipairs(cfg.rings) do
			local N = 70
			for i = 1, N do
				local a = i / N * math.pi * 2
				local pos = Vector3.new(math.cos(a) * rg[1], 0, math.sin(a) * rg[1])
				local seg = mkPart(rm, "Ring", Vector3.new(rg[2], 2, rg[1] * 2 * math.pi / N * 1.15),
					CFrame.lookAt(pos, pos + Vector3.new(-math.sin(a), 0, math.cos(a))), rg[3], Enum.Material.SmoothPlastic)
				seg.Transparency = rg[4]
				seg.CanQuery = false
				seg.CastShadow = false
			end
		end
		rm.Parent = m
		rm:PivotTo(CFrame.new(o + cfg.ringCenter) * CFrame.Angles(math.rad(cfg.ringTilt), 0, 0))
	end
	return m
end

local MARS_ORIGIN = Vector3.new(150000, 5000, 150000)
local MERCURY_ORIGIN = Vector3.new(-150000, 5000, -150000)
local VENUS_ORIGIN = Vector3.new(-150000, 5000, 150000)
local IO_ORIGIN = Vector3.new(-150000, 5000, 0)
local EUROPA_ORIGIN = Vector3.new(0, 5000, -150000)
local PLUTO_ORIGIN = Vector3.new(0, 5000, 150000)
local ASTEROID_ORIGIN = Vector3.new(-300000, 5000, 300000)
local JUPITER_ORIGIN = Vector3.new(-300000, 5000, 0)
local SATURN_ORIGIN = Vector3.new(300000, 5000, 0)
local URANUS_ORIGIN = Vector3.new(0, 5000, 300000)
local NEPTUNE_ORIGIN = Vector3.new(0, 5000, -300000)
local G = 196.2

local PLANETS = {
	MOON = {
		name = "THE MOON", origin = MOON_ORIGIN, grav = 0, dust = Color3.fromRGB(165, 165, 170), startH = 900, landT = 9,
		sunDist = 30000, sunSize = 2000, earth = true,
		cfg = { seed = 3, ground = Color3.fromRGB(150, 150, 156), crater = Color3.fromRGB(108, 108, 114), rim = Color3.fromRGB(172, 172, 178),
			rockA = Color3.fromRGB(95, 95, 101), rockB = Color3.fromRGB(150, 150, 156), hill = Color3.fromRGB(150, 150, 156),
			ridge = Color3.fromRGB(138, 138, 144), craters = 45, rocks = 160, hills = 16 },
		pickups = { { "SAMPLE", Vector3.new(90, 3, 70) }, { "RADSUIT", Vector3.new(-80, 3, 110) } },
	},
	MARS = {
		name = "MARS", origin = MARS_ORIGIN, grav = G * 0.38, dust = Color3.fromRGB(190, 120, 85), startH = 800, landT = 9,
		sunDist = 30000, sunSize = 1300, earth = false,
		cfg = { seed = 11, mat = Enum.Material.Sand, ground = Color3.fromRGB(172, 90, 58), crater = Color3.fromRGB(128, 64, 42), rim = Color3.fromRGB(190, 112, 78),
			rockA = Color3.fromRGB(110, 55, 38), rockB = Color3.fromRGB(170, 95, 65), hill = Color3.fromRGB(160, 82, 52),
			ridge = Color3.fromRGB(150, 78, 50), craters = 35, rocks = 190, hills = 20,
			sky = { { Vector3.new(2500, 2200, -1800), 110 }, { Vector3.new(-3000, 3000, 1500), 70 } } },
		env = { bright = 2.6, amb = Color3.fromRGB(95, 58, 42), out = Color3.fromRGB(85, 52, 38),
			atmo = { Color = Color3.fromRGB(224, 160, 120), Decay = Color3.fromRGB(170, 100, 70), Density = 0.32, Haze = 1.6 },
			tint = Color3.fromRGB(255, 210, 185), fog = { Color3.fromRGB(190, 120, 90), 400, 6000 } },
		pickups = { { "HULL", Vector3.new(100, 3, -80) }, { "CRYO", Vector3.new(-110, 3, -60) } },
		arrive = "MARS: THIN AIR + DUST - OXYGEN TANK AND FILTERS ONLINE",
	},
	MERCURY = {
		name = "MERCURY", origin = MERCURY_ORIGIN, grav = G * 0.38, dust = Color3.fromRGB(130, 120, 112), startH = 900, landT = 9,
		sunDist = 12000, sunSize = 2000, earth = false,
		cfg = { seed = 21, ground = Color3.fromRGB(122, 112, 104), crater = Color3.fromRGB(84, 78, 74), rim = Color3.fromRGB(150, 140, 132),
			rockA = Color3.fromRGB(80, 74, 70), rockB = Color3.fromRGB(130, 120, 112), hill = Color3.fromRGB(110, 102, 96),
			ridge = Color3.fromRGB(100, 94, 90), craters = 85, rocks = 170, hills = 14 },
		env = { bright = 4, amb = Color3.fromRGB(30, 30, 32), out = Color3.fromRGB(22, 22, 24) },
		pickups = { { "COATING", Vector3.new(-90, 3, 90) } },
		arrive = "MERCURY: HEAT SHIELD + RADIATION SUIT HOLDING",
	},
	VENUS = {
		name = "VENUS", origin = VENUS_ORIGIN, grav = G * 0.9, dust = Color3.fromRGB(190, 140, 70), startH = 600, landT = 9,
		sunDist = 30000, sunSize = 1400, earth = false,
		cfg = { seed = 31, mat = Enum.Material.Basalt, rockMat = Enum.Material.Basalt, ground = Color3.fromRGB(112, 64, 40),
			crater = Color3.fromRGB(80, 45, 30), rim = Color3.fromRGB(140, 85, 55),
			rockA = Color3.fromRGB(55, 35, 28), rockB = Color3.fromRGB(100, 62, 45), hill = Color3.fromRGB(96, 56, 36),
			ridge = Color3.fromRGB(85, 50, 32), craters = 15, rocks = 170, hills = 22, lava = true },
		env = { bright = 1.6, amb = Color3.fromRGB(140, 95, 40), out = Color3.fromRGB(120, 80, 35),
			atmo = { Color = Color3.fromRGB(255, 200, 110), Decay = Color3.fromRGB(230, 150, 60), Density = 0.7, Haze = 4 },
			tint = Color3.fromRGB(255, 215, 150), fog = { Color3.fromRGB(210, 150, 70), 0, 1100 } },
		pickups = { { "SULFUR", Vector3.new(95, 3, 85) } },
		arrive = "VENUS: HEAT SHIELD + PRESSURE HULL + ACID COATING HOLDING",
	},
	IO = {
		name = "IO", origin = IO_ORIGIN, grav = G * 0.183, dust = Color3.fromRGB(215, 190, 90), startH = 800, landT = 9,
		sunDist = 30000, sunSize = 700, earth = false,
		cfg = { seed = 41, mat = Enum.Material.Sand, ground = Color3.fromRGB(222, 198, 92), crater = Color3.fromRGB(150, 110, 50),
			rim = Color3.fromRGB(238, 220, 130), rockA = Color3.fromRGB(120, 90, 40), rockB = Color3.fromRGB(215, 190, 90),
			hill = Color3.fromRGB(205, 170, 75), ridge = Color3.fromRGB(170, 135, 60), craters = 18, rocks = 150, hills = 22,
			lava = true, jupiter = 7500 },
		env = { bright = 2.2, amb = Color3.fromRGB(110, 90, 40), out = Color3.fromRGB(95, 78, 36),
			atmo = { Color = Color3.fromRGB(255, 225, 130), Decay = Color3.fromRGB(230, 170, 70), Density = 0.12, Haze = 0.6 },
			tint = Color3.fromRGB(255, 235, 175) },
		pickups = {},
		arrive = "IO: SULFUR FILTER + HEAT SHIELD + RADIATION SUIT HOLDING",
	},
	EUROPA = {
		name = "EUROPA", origin = EUROPA_ORIGIN, grav = G * 0.134, dust = Color3.fromRGB(215, 230, 240), startH = 800, landT = 9,
		sunDist = 30000, sunSize = 500, earth = false,
		cfg = { seed = 51, mat = Enum.Material.Ice, rockMat = Enum.Material.Ice, ground = Color3.fromRGB(214, 232, 242),
			crater = Color3.fromRGB(160, 185, 205), rim = Color3.fromRGB(240, 248, 255), rockA = Color3.fromRGB(170, 200, 220),
			rockB = Color3.fromRGB(235, 245, 255), hill = Color3.fromRGB(225, 238, 248), ridge = Color3.fromRGB(210, 225, 240),
			craters = 12, rocks = 150, hills = 24, cracks = true, jupiter = 6500 },
		env = { bright = 2.2, amb = Color3.fromRGB(60, 78, 105), out = Color3.fromRGB(50, 68, 95), tint = Color3.fromRGB(225, 238, 255) },
		pickups = { { "DRILL", Vector3.new(85, 3, -95) } },
		arrive = "EUROPA: CRYO INSULATION + RADIATION SUIT + HULL HOLDING",
	},
	PLUTO = {
		name = "PLUTO", origin = PLUTO_ORIGIN, grav = G * 0.063, dust = Color3.fromRGB(215, 200, 185), startH = 800, landT = 9,
		sunDist = 30000, sunSize = 160, earth = false,
		cfg = { seed = 61, mat = Enum.Material.Snow, ground = Color3.fromRGB(206, 186, 166), crater = Color3.fromRGB(150, 130, 112),
			rim = Color3.fromRGB(225, 210, 192), rockA = Color3.fromRGB(150, 135, 120), rockB = Color3.fromRGB(210, 195, 180),
			hill = Color3.fromRGB(190, 200, 215), ridge = Color3.fromRGB(170, 160, 150), craters = 22, rocks = 150, hills = 18,
			heart = true, sky = { { Vector3.new(5500, 3500, -4000), 900, Color3.fromRGB(150, 140, 135) } } },
		env = { bright = 1.5, amb = Color3.fromRGB(34, 32, 42), out = Color3.fromRGB(26, 24, 34),
			atmo = { Color = Color3.fromRGB(140, 170, 235), Decay = Color3.fromRGB(100, 120, 190), Density = 0.06, Haze = 0.5 },
			tint = Color3.fromRGB(230, 236, 255) },
		pickups = {},
		arrive = "PLUTO: CRYO INSULATION + OXYGEN + ICE DRILL HOLDING",
	},
	ASTEROID = {
		name = "THE ASTEROID BELT", origin = ASTEROID_ORIGIN, grav = G * 0.03, dust = Color3.fromRGB(120, 110, 100), startH = 800, landT = 9,
		sunDist = 30000, sunSize = 700, earth = false,
		cfg = { seed = 71, ground = Color3.fromRGB(96, 88, 80), crater = Color3.fromRGB(66, 60, 55), rim = Color3.fromRGB(130, 120, 110),
			rockA = Color3.fromRGB(70, 64, 58), rockB = Color3.fromRGB(130, 118, 105), hill = Color3.fromRGB(100, 92, 84),
			ridge = Color3.fromRGB(86, 80, 72), craters = 40, rocks = 230, hills = 12, floating = 70 },
		env = { bright = 3.5, amb = Color3.fromRGB(28, 28, 32), out = Color3.fromRGB(20, 20, 24) },
		pickups = { { "GRAV", Vector3.new(90, 3, 60) } },
		arrive = "ASTEROID BELT: HULL PLATING + OXYGEN HOLDING",
	},
	JUPITER = {
		name = "JUPITER", origin = JUPITER_ORIGIN, grav = G * 2.5, dust = Color3.fromRGB(215, 175, 130), startH = 700, landT = 9,
		sunDist = 30000, sunSize = 380, earth = false,
		cfg = { seed = 81, hill = Color3.fromRGB(240, 225, 200), ridge = Color3.fromRGB(225, 200, 165), craters = 0, rocks = 0, hills = 18,
			deck = { Color3.fromRGB(220, 175, 130), Color3.fromRGB(240, 225, 200), Color3.fromRGB(180, 120, 85), Color3.fromRGB(230, 200, 160) },
			storms = 16, stormEye = Color3.fromRGB(190, 75, 50),
			stormCols = { Color3.fromRGB(235, 210, 180), Color3.fromRGB(200, 120, 85), Color3.fromRGB(245, 235, 220) },
			sky = { { Vector3.new(4500, 3000, -2500), 300, Color3.fromRGB(235, 215, 120) }, { Vector3.new(-5000, 3500, 2000), 250, Color3.fromRGB(225, 225, 215) } } },
		env = { bright = 2.0, amb = Color3.fromRGB(130, 100, 70), out = Color3.fromRGB(110, 85, 60),
			atmo = { Color = Color3.fromRGB(230, 190, 150), Decay = Color3.fromRGB(200, 140, 100), Density = 0.55, Haze = 3 },
			tint = Color3.fromRGB(255, 225, 195), fog = { Color3.fromRGB(215, 170, 125), 200, 3500 } },
		pickups = { { "JOVE", Vector3.new(80, 3, 75) } },
		arrive = "JUPITER: PRESSURE SEAL + RADIATION SUIT + STABILIZER HOLDING",
	},
	SATURN = {
		name = "SATURN", origin = SATURN_ORIGIN, grav = G * 1.07, dust = Color3.fromRGB(225, 205, 155), startH = 700, landT = 9,
		sunDist = 30000, sunSize = 260, earth = false,
		cfg = { seed = 91, hill = Color3.fromRGB(245, 235, 205), ridge = Color3.fromRGB(230, 212, 165), craters = 0, rocks = 0, hills = 16,
			deck = { Color3.fromRGB(230, 210, 160), Color3.fromRGB(240, 230, 190), Color3.fromRGB(205, 180, 125), Color3.fromRGB(220, 195, 140) },
			storms = 10, stormEye = Color3.fromRGB(190, 160, 105),
			stormCols = { Color3.fromRGB(240, 228, 195), Color3.fromRGB(215, 190, 135) },
			rings = { { 10000, 1100, Color3.fromRGB(205, 180, 135), 0.25 }, { 11400, 1100, Color3.fromRGB(225, 205, 160), 0.2 },
				{ 12800, 900, Color3.fromRGB(190, 165, 120), 0.3 }, { 14000, 600, Color3.fromRGB(215, 195, 150), 0.35 } },
			ringCenter = Vector3.new(0, -8000, 0), ringTilt = 20,
			sky = { { Vector3.new(5000, 2500, -3500), 260, Color3.fromRGB(210, 150, 70) } } },
		env = { bright = 1.8, amb = Color3.fromRGB(125, 110, 80), out = Color3.fromRGB(105, 92, 68),
			atmo = { Color = Color3.fromRGB(235, 215, 165), Decay = Color3.fromRGB(200, 170, 110), Density = 0.5, Haze = 2.5 },
			tint = Color3.fromRGB(255, 240, 205), fog = { Color3.fromRGB(225, 205, 155), 300, 4500 } },
		pickups = { { "RING", Vector3.new(85, 3, 70) } },
		arrive = "SATURN: STABILIZER + PRESSURE SEAL + CRYO PACK HOLDING",
	},
	URANUS = {
		name = "URANUS", origin = URANUS_ORIGIN, grav = G * 0.89, dust = Color3.fromRGB(170, 225, 232), startH = 700, landT = 9,
		sunDist = 30000, sunSize = 150, earth = false,
		cfg = { seed = 101, hill = Color3.fromRGB(205, 245, 250), ridge = Color3.fromRGB(175, 232, 240), craters = 0, rocks = 0, hills = 14,
			deck = { Color3.fromRGB(170, 230, 235), Color3.fromRGB(190, 240, 245), Color3.fromRGB(150, 215, 225) },
			storms = 6, stormEye = Color3.fromRGB(130, 200, 215), stormCols = { Color3.fromRGB(205, 245, 250), Color3.fromRGB(150, 220, 232) },
			rings = { { 9000, 160, Color3.fromRGB(190, 230, 240), 0.4 }, { 9800, 120, Color3.fromRGB(170, 215, 230), 0.45 } },
			ringCenter = Vector3.new(0, -2000, -7000), ringTilt = 95 },
		env = { bright = 1.5, amb = Color3.fromRGB(70, 110, 120), out = Color3.fromRGB(58, 95, 105),
			atmo = { Color = Color3.fromRGB(160, 225, 235), Decay = Color3.fromRGB(110, 180, 195), Density = 0.45, Haze = 2 },
			tint = Color3.fromRGB(205, 245, 250), fog = { Color3.fromRGB(170, 230, 238), 300, 4500 } },
		pickups = { { "METH", Vector3.new(80, 3, 80) } },
		arrive = "URANUS: PRESSURE SEAL + RING SHIELD + CRYO PACK HOLDING",
	},
	NEPTUNE = {
		name = "NEPTUNE", origin = NEPTUNE_ORIGIN, grav = G * 1.14, dust = Color3.fromRGB(90, 125, 230), startH = 700, landT = 9,
		sunDist = 30000, sunSize = 100, earth = false,
		cfg = { seed = 111, hill = Color3.fromRGB(110, 140, 240), ridge = Color3.fromRGB(60, 90, 200), craters = 0, rocks = 0, hills = 14,
			deck = { Color3.fromRGB(60, 90, 200), Color3.fromRGB(80, 115, 225), Color3.fromRGB(45, 70, 170) },
			storms = 8, stormEye = Color3.fromRGB(20, 30, 90), stormCols = { Color3.fromRGB(30, 45, 130), Color3.fromRGB(200, 220, 255) },
			sky = { { Vector3.new(-4800, 3200, 3000), 280, Color3.fromRGB(210, 190, 200) } } },
		env = { bright = 1.3, amb = Color3.fromRGB(35, 55, 110), out = Color3.fromRGB(28, 45, 95),
			atmo = { Color = Color3.fromRGB(90, 130, 240), Decay = Color3.fromRGB(60, 90, 190), Density = 0.5, Haze = 2.2 },
			tint = Color3.fromRGB(190, 210, 255), fog = { Color3.fromRGB(70, 100, 210), 300, 4500 } },
		pickups = {},
		arrive = "NEPTUNE: RING SHIELD + METHANE FILTER + ICE DRILL HOLDING",
	},
}

local function buildSpaceObjects()
	if SP.earth then return end
	SP.earth, SP.clouds = buildEarth()
	SP.moon = buildMoon()
	SP.iss = buildISS()
	SP.stars = buildStars()
	SP.sun = mkBall(worldFolder, "NasaSun", 2000, Color3.fromRGB(255, 224, 130), Enum.Material.Neon)
	SP.sun.CanQuery = false
	SP.earth.Parent = worldFolder
	SP.clouds.Parent = worldFolder
	SP.moon.Parent = worldFolder
	SP.iss.Parent = worldFolder
	SP.stars.Parent = worldFolder
end

local function attachSpace()
	for _, k in ipairs({ "earth", "clouds", "sun", "stars" }) do
		if SP[k] then SP[k].Parent = worldFolder end
	end
end

local function detachSpace()
	for _, k in ipairs({ "earth", "clouds", "moon", "iss", "sun", "stars" }) do
		if SP[k] then SP[k].Parent = nil end
	end
	if SP.surface then SP.surface:Destroy() SP.surface = nil end
end

local function updateEarth(center)
	if not (SP.earth and center) then return end
	local tilt = CFrame.Angles(0, 0, math.rad(23))
	SP.earth:PivotTo(CFrame.new(center) * tilt * CFrame.Angles(0, SP.spin, 0))
	SP.clouds:PivotTo(CFrame.new(center) * tilt * CFrame.Angles(0, SP.spin * 1.25 + 1, 0))
end

local function updateISS(dt)
	if not (SP.iss and SP.earthCenter) then return end
	SP.issAng = SP.issAng + (dt or 0) * 0.12
	local a = SP.issAng
	local tilt = CFrame.Angles(math.rad(40), 0, 0)
	local pos = SP.earthCenter + (tilt * Vector3.new(math.cos(a), 0, math.sin(a))) * ISS_R
	local radial = (pos - SP.earthCenter).Unit
	local tangent = tilt * Vector3.new(-math.sin(a), 0, math.cos(a))
	SP.prevIssCF = SP.issCF
	SP.issCF = CFrame.lookAt(pos, pos + tangent, radial)
	SP.iss:PivotTo(SP.issCF)
end

local function clearPlanetEnv()
	for _, n in ipairs({ "NasaPlanetAtmo", "NasaPlanetCC" }) do
		local o = Lighting:FindFirstChild(n)
		if o then o:Destroy() end
	end
	Lighting.Brightness = 3
	Lighting.Ambient = Color3.fromRGB(22, 24, 38)
	Lighting.OutdoorAmbient = Color3.fromRGB(14, 16, 28)
	Lighting.FogEnd = 1e7
	Lighting.FogStart = 1e6
end

local function applyPlanetEnv(key)
	local e = PLANETS[key] and PLANETS[key].env
	if not e then return end
	Lighting.Brightness = e.bright
	Lighting.Ambient = e.amb
	Lighting.OutdoorAmbient = e.out
	if e.fog then
		Lighting.FogColor = e.fog[1]
		Lighting.FogStart = e.fog[2]
		Lighting.FogEnd = e.fog[3]
	end
	if e.atmo then
		local a = Instance.new("Atmosphere")
		a.Name = "NasaPlanetAtmo"
		for k, v in pairs(e.atmo) do a[k] = v end
		a.Parent = Lighting
	end
	if e.tint then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "NasaPlanetCC"
		cc.TintColor = e.tint
		cc.Saturation = 0.1
		cc.Parent = Lighting
	end
end

local function showScene(name)
	scene = name
	clearPlanetEnv()
	attachSpace()
	SP.sun.Size = Vector3.new(2000, 2000, 2000)
	local base, dist = SPACE_ORIGIN, 30000
	if name == "ORBIT" then
		SP.earthCenter = SPACE_ORIGIN + Vector3.new(0, -2800, 0)
		SP.moon.Parent = worldFolder
		SP.iss.Parent = worldFolder
		if SP.surface then SP.surface:Destroy() SP.surface = nil end
		workspace.Gravity = 0
		updateISS(0)
		SP.prevIssCF = SP.issCF
	else
		local P = PLANETS[name]
		base, dist = P.origin, P.sunDist
		SP.moon.Parent = nil
		SP.iss.Parent = nil
		if SP.surface then SP.surface:Destroy() end
		SP.surface = buildSurface(P.origin, P.cfg)
		SP.surface.Parent = worldFolder
		addPickups(SP.surface, P.origin, P.pickups)
		if P.earth then
			local ed = (sunDir:Cross(Vector3.yAxis).Unit + Vector3.new(0, 0.35, 0)).Unit
			SP.earthCenter = P.origin + ed * 9000
		else
			SP.earth.Parent = nil
			SP.clouds.Parent = nil
			SP.earthCenter = P.origin + Vector3.new(0, 90000, 0)
		end
		SP.sun.Size = Vector3.new(P.sunSize, P.sunSize, P.sunSize)
		workspace.Gravity = P.grav
		applyPlanetEnv(name)
	end
	SP.sun.Position = base + sunDir * dist
	SP.stars:PivotTo(CFrame.new(base))
	updateEarth(SP.earthCenter)
end

-- ===== helpers for cinematics =====
local function setPivot(r)
	r.model:PivotTo(CFrame.new(r.pos) * r.baseRot * CFrame.Angles(r.pitch, 0, r.roll))
end

local function frames(r, dur, fn)
	local t = 0
	while t < dur do
		local dt = RunService.RenderStepped:Wait()
		if r.dead then return false end
		t = t + dt
		fn(math.min(t / dur, 1), dt)
	end
	return true
end

local function startWarp()
	warpM = Instance.new("Model")
	warpM.Name = "NasaWarp"
	warpM.Parent = workspace
	local list = {}
	for i = 1, 110 do
		local x, z = rng:NextNumber(-800, 800), rng:NextNumber(-800, 800)
		if math.abs(x) < 60 and math.abs(z) < 60 then x = x + 140 end
		local p = mkPart(warpM, "Streak", Vector3.new(1.4, 260, 1.4), CFrame.new(), Color3.fromRGB(190, 225, 255), Enum.Material.Neon)
		p.CanQuery = false
		p.CastShadow = false
		list[i] = { p = p, x = x, y = rng:NextNumber(-1500, 1500), z = z }
	end
	return list
end

local function warpSeq(r, duration, swapFn)
	local list = startWarp()
	local t, swapped = 0, false
	while t < duration do
		local dt = RunService.RenderStepped:Wait()
		if r.dead then break end
		t = t + dt
		local a = math.min(t / duration, 1)
		local f
		if a < 0.25 then f = (a / 0.25) ^ 1.5 elseif a < 0.75 then f = 1 else f = ((1 - a) / 0.25) ^ 1.5 end
		r.dispSpeed = f * 299792
		camera.FieldOfView = baseFOV + 50 * f
		local fl = 1
		if a > 0.42 and a <= 0.5 then fl = 1 - (a - 0.42) / 0.08
		elseif a > 0.5 and a < 0.62 then fl = (a - 0.5) / 0.12 end
		flash.BackgroundColor3 = Color3.new(1, 1, 1)
		flash.BackgroundTransparency = fl
		if not swapped and a >= 0.5 then
			swapped = true
			swapFn()
		end
		local pv = r.model:GetPivot()
		for _, s in ipairs(list) do
			s.y = s.y - f * 9000 * dt
			if s.y < -1500 then s.y = s.y + 3000 end
			s.p.CFrame = pv * CFrame.new(s.x, s.y, s.z)
			s.p.Transparency = 1 - f * 0.85
		end
	end
	flash.BackgroundTransparency = 1
	camera.FieldOfView = baseFOV
	r.dispSpeed = nil
	if warpM then warpM:Destroy() warpM = nil end
end

local function landAt(r, ground, startH, dur, dustColor)
	local gy = ground.Y + 12 * r.S
	local dust = Instance.new("Part")
	dust.Anchored = true dust.CanCollide = false dust.CanQuery = false dust.Transparency = 1
	dust.Size = Vector3.new(1, 1, 1)
	dust.Position = ground + Vector3.new(0, 1, 0)
	dust.Parent = worldFolder
	local att = Instance.new("Attachment") att.Parent = dust
	local em = Instance.new("ParticleEmitter")
	em.Texture = "rbxasset://textures/particles/smoke_main.dds"
	em.Color = ColorSequence.new(dustColor)
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 14), NumberSequenceKeypoint.new(1, 70) })
	em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	em.Lifetime = NumberRange.new(2.5, 4)
	em.Speed = NumberRange.new(30, 80)
	em.EmissionDirection = Enum.NormalId.Top
	em.SpreadAngle = Vector2.new(85, 85)
	em.Rate = 0
	em.Parent = att
	frames(r, dur, function(a)
		local h = startH * (1 - a) ^ 2
		r.pos = Vector3.new(ground.X, gy + h, ground.Z)
		setPivot(r)
		r.forceThr = 0.35 + 0.55 * (1 - a)
		em.Rate = (h < 160) and (1 - h / 160) * 260 or 0
	end)
	r.pos = Vector3.new(ground.X, gy, ground.Z)
	setPivot(r)
	em:Emit(80)
	em.Rate = 0
	r.forceThr = nil
	Debris:AddItem(dust, 6)
end

local function refurbish(r)
	if r.model then r.model:Destroy() end
	local model, bms, eng = buildRocket(r.S, r.origin, true)
	model.Parent = worldFolder
	r.model, r.boosterModels, r.engines = model, bms, eng
	r.boosters, r.fuel, r.speed, r.alt = true, 100, 0, 0
	r.pitch, r.roll, r.ignite, r.entering = 0, 0, false, false
	r.baseRot = r.origin.Rotation
	r.pos = model:GetPivot().Position
end

-- ===== enter space (called when altitude passes the limit) =====
local function enterSpace(r)
	task.spawn(function()
		flash.BackgroundColor3 = Color3.new(0, 0, 0)
		TweenService:Create(flash, TweenInfo.new(0.4), { BackgroundTransparency = 0 }):Play()
		task.wait(0.45)
		if r.dead then return end
		applySpaceEnv()
		buildSpaceObjects()
		attachSpace()
		spaceMode = true
		loc = "ORBIT"
		showScene("ORBIT")
		r.pos = SPACE_ORIGIN
		setPivot(r)
		TweenService:Create(flash, TweenInfo.new(1.0), { BackgroundTransparency = 1 }):Play()
		setStatus("OUTSIDE EARTH - NAV TABLET ONLINE", GREEN)
		if inside and openTablet then openTablet(true) end
	end)
end

----------------------------------------------------------------
-- NAV TABLET (solar system chart)
----------------------------------------------------------------
local tabletOpen = false
local tablet = new("Frame", {
	Name = "Tablet", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.01, 0.5),
	Size = UDim2.fromScale(0.55, 0.92), BackgroundColor3 = Color3.fromRGB(28, 30, 38), Visible = false,
}, gui)
new("UISizeConstraint", { MaxSize = Vector2.new(680, 520), MinSize = Vector2.new(300, 220) }, tablet)
corner(tablet, 18) stroke(tablet, Color3.fromRGB(95, 100, 115), 3)
local screen = new("Frame", {
	Position = UDim2.fromScale(0.02, 0.03), Size = UDim2.fromScale(0.96, 0.94),
	BackgroundColor3 = Color3.fromRGB(4, 7, 14), ClipsDescendants = true,
}, tablet)
corner(screen, 10) stroke(screen, CYAN, 1)

new("TextLabel", {
	Text = "SOLAR NAV // ORBITAL CHART", Font = Enum.Font.SciFi, TextScaled = true, TextColor3 = CYAN,
	TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1,
	Position = UDim2.fromScale(0.02, 0.012), Size = UDim2.fromScale(0.52, 0.075),
}, screen)
local locLbl = new("TextLabel", {
	Text = "LOC: EARTH ORBIT", Font = Enum.Font.Code, TextScaled = true, TextColor3 = GREEN,
	TextXAlignment = Enum.TextXAlignment.Right, BackgroundTransparency = 1,
	Position = UDim2.fromScale(0.5, 0.02), Size = UDim2.fromScale(0.38, 0.06),
}, screen)
local closeBtn = new("TextButton", {
	Text = "X", Font = Enum.Font.GothamBold, TextScaled = true, TextColor3 = RED, BackgroundColor3 = PANEL,
	Position = UDim2.fromScale(0.91, 0.012), Size = UDim2.fromScale(0.07, 0.075), AutoButtonColor = false,
}, screen)
corner(closeBtn, 5) stroke(closeBtn, RED, 1)

local mapArea = new("Frame", {
	Position = UDim2.fromScale(0, 0.1), Size = UDim2.fromScale(1, 0.64), BackgroundColor3 = Color3.fromRGB(2, 4, 10),
	BorderSizePixel = 0, ClipsDescendants = true,
}, screen)
for _ = 1, 45 do
	new("Frame", {
		Position = UDim2.fromScale(rng:NextNumber(0, 1), rng:NextNumber(0, 1)), Size = UDim2.fromOffset(2, 2),
		BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = rng:NextNumber(0.3, 0.8), BorderSizePixel = 0,
	}, mapArea)
end
local mapBG = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1 }, mapArea)

local function roundOff(o) new("UICorner", { CornerRadius = UDim.new(1, 0) }, o) end
local function C(r, g, b) return Color3.fromRGB(r, g, b) end
local PH = " - PLACEHOLDER, NOT YET AVAILABLE"
local BODIES = {
	{ id = "Sun", name = "SUN", col = C(255, 200, 60), size = 38, info = "STAR // SOL" .. PH },
	{ id = "Mercury", parent = "Sun", r = 55, w = 0.8, name = "MERCURY", col = C(160, 155, 150), size = 7, info = "PLANET // LANDING AVAILABLE - SURVIVAL GEAR REQUIRED" },
	{ id = "Venus", parent = "Sun", r = 85, w = 0.55, name = "VENUS", col = C(230, 200, 140), size = 11, info = "PLANET // LANDING AVAILABLE - HARDEST TRIP, MOST GEAR" },
	{ id = "Earth", parent = "Sun", r = 120, w = 0.4, name = "EARTH", col = C(60, 120, 220), size = 13, info = "HOME WORLD // RETURN AND LAND AT YOUR LAUNCH PAD" },
	{ id = "Moon", parent = "Earth", r = 22, w = 1.1, name = "MOON (LUNA)", col = C(205, 205, 210), size = 5, info = "LUNA // LIGHT SPEED JUMP + LANDING AVAILABLE" },
	{ id = "ISS", parent = "Earth", r = 14, w = 2.6, name = "ISS", col = C(245, 245, 250), size = 3, info = "LOW EARTH ORBIT STATION // DOCKING AVAILABLE" },
	{ id = "Mars", parent = "Sun", r = 158, w = 0.3, name = "MARS", col = C(200, 90, 60), size = 9, info = "PLANET // LANDING AVAILABLE - SURVIVAL GEAR REQUIRED" },
	{ id = "Asteroids", parent = "Sun", r = 182, w = 0.22, name = "ASTEROID BELT", col = C(160, 150, 138), size = 5, info = "DWARF PLANET CERES // LANDING AVAILABLE - GEAR REQUIRED" },
	{ id = "Jupiter", parent = "Sun", r = 205, w = 0.18, name = "JUPITER", col = C(210, 160, 120), size = 26, info = "GAS GIANT // LAND ON A CLOUD-TOP PLATFORM - GEAR REQUIRED" },
	{ id = "Io", parent = "Jupiter", r = 25, w = 1.7, name = "IO", col = C(230, 210, 110), size = 4, info = "VOLCANIC MOON OF JUPITER // LANDING AVAILABLE - GEAR REQUIRED" },
	{ id = "Europa", parent = "Jupiter", r = 36, w = 1.1, name = "EUROPA", col = C(220, 215, 200), size = 4, info = "ICY MOON OF JUPITER // LANDING AVAILABLE - GEAR REQUIRED" },
	{ id = "Saturn", parent = "Sun", r = 255, w = 0.13, name = "SATURN", col = C(225, 200, 140), size = 22, info = "RINGED GIANT // LAND ON A CLOUD-TOP PLATFORM - GEAR REQUIRED" },
	{ id = "Titan", parent = "Saturn", r = 32, w = 0.9, name = "TITAN", col = C(210, 150, 70), size = 5, info = "MOON OF SATURN" .. PH },
	{ id = "Uranus", parent = "Sun", r = 300, w = 0.09, name = "URANUS", col = C(140, 220, 230), size = 16, info = "ICE GIANT // LAND ON A CLOUD-TOP PLATFORM - GEAR REQUIRED" },
	{ id = "Neptune", parent = "Sun", r = 340, w = 0.07, name = "NEPTUNE", col = C(60, 90, 220), size = 15, info = "ICE GIANT // LAND ON A CLOUD-TOP PLATFORM - GEAR REQUIRED" },
	{ id = "Pluto", parent = "Sun", r = 378, w = 0.05, name = "PLUTO", col = C(190, 170, 150), size = 6, info = "DWARF PLANET // LANDING AVAILABLE - EXTREME COLD, GEAR REQUIRED" },
}
local DEST = { Earth = "EARTH", Moon = "MOON", ISS = "ISS", Mars = "MARS", Mercury = "MERCURY", Venus = "VENUS", Io = "IO", Europa = "EUROPA", Pluto = "PLUTO",
	Asteroids = "ASTEROID", Jupiter = "JUPITER", Saturn = "SATURN", Uranus = "URANUS", Neptune = "NEPTUNE" }
local BODYMAP, ang, E = {}, {}, {}
local zoom, pan, sel = 0.3, Vector2.zero, nil
local lastPos = {}

local function nameOf(id) return BODYMAP[id] and BODYMAP[id].name or "" end

local nameLbl, infoLbl, goBtn
for _, b in ipairs(BODIES) do
	BODYMAP[b.id] = b
	ang[b.id] = rng:NextNumber(0, 6.28)
	local el = {}
	if b.parent then
		el.ring = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Size = UDim2.fromOffset(10, 10), ZIndex = 2 }, mapArea)
		roundOff(el.ring)
		stroke(el.ring, C(55, 90, 125), 1).Transparency = (b.parent == "Sun") and 0.45 or 0.6
	end
	if b.id == "Saturn" then
		el.sat = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Rotation = -20, ZIndex = 3 }, mapArea)
		roundOff(el.sat)
		stroke(el.sat, C(200, 175, 120), 2)
	end
	el.btn = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(28, 28), ZIndex = 4 }, mapArea)
	el.vis = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = b.col, ZIndex = 4 }, el.btn)
	roundOff(el.vis)
	el.sel = stroke(el.vis, Color3.new(1, 1, 1), 2)
	el.sel.Enabled = false
	el.lbl = new("TextLabel", {
		Text = b.name, Font = Enum.Font.Code, TextSize = 10, TextColor3 = C(160, 190, 205), BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(90, 12), ZIndex = 4,
	}, mapArea)
	E[b.id] = el
end
local hereRing = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Size = UDim2.fromOffset(20, 20), ZIndex = 5 }, mapArea)
roundOff(hereRing)
stroke(hereRing, GREEN, 2)
local BELT = {}
for i = 1, 80 do
	local f = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(2, 2), BackgroundColor3 = C(150, 140, 128),
		BackgroundTransparency = rng:NextNumber(0.1, 0.5), BorderSizePixel = 0, ZIndex = 2,
	}, mapArea)
	BELT[i] = { f = f, a = rng:NextNumber(0, 6.28), r = rng:NextNumber(172, 192), w = 0.22 + rng:NextNumber(-0.04, 0.04) }
end

-- map controls
local function mapBtn(text, i)
	local b = new("TextButton", {
		Text = text, Font = Enum.Font.GothamBold, TextScaled = true, TextColor3 = CYAN, BackgroundColor3 = PANEL,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6 + (i - 1) * 36), Size = UDim2.fromOffset(30, 30),
		AutoButtonColor = false, ZIndex = 6,
	}, mapArea)
	corner(b, 6) stroke(b, CYAN, 1)
	new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }, b)
	return b
end
local zoomIn, zoomOut, fitBtn, focusBtn, helpBtn = mapBtn("+", 1), mapBtn("-", 2), mapBtn("FIT", 3), mapBtn("O", 4), mapBtn("?", 5)

-- info panel
local info = new("Frame", { Position = UDim2.fromScale(0.02, 0.76), Size = UDim2.fromScale(0.96, 0.22), BackgroundColor3 = PANEL }, screen)
corner(info, 8) stroke(info, CYAN, 1).Transparency = 0.5
nameLbl = new("TextLabel", {
	Text = "NO TARGET", Font = Enum.Font.SciFi, TextScaled = true, TextColor3 = AMBER, TextXAlignment = Enum.TextXAlignment.Left,
	BackgroundTransparency = 1, Position = UDim2.fromScale(0.03, 0.06), Size = UDim2.fromScale(0.62, 0.3),
}, info)
infoLbl = new("TextLabel", {
	Text = "TAP A BODY ON THE CHART", Font = Enum.Font.Code, TextScaled = true, TextWrapped = true, TextColor3 = C(170, 200, 215),
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, BackgroundTransparency = 1,
	Position = UDim2.fromScale(0.03, 0.4), Size = UDim2.fromScale(0.64, 0.55),
}, info)
new("UITextSizeConstraint", { MaxTextSize = 14, MinTextSize = 7 }, infoLbl)
goBtn = new("TextButton", {
	Text = "--", Font = Enum.Font.GothamBold, TextScaled = true, TextColor3 = Color3.fromRGB(110, 120, 130), BackgroundColor3 = BG,
	Position = UDim2.fromScale(0.7, 0.14), Size = UDim2.fromScale(0.28, 0.72), AutoButtonColor = false,
}, info)
corner(goBtn, 8)
local goStroke = stroke(goBtn, Color3.fromRGB(110, 120, 130), 2)
new("UITextSizeConstraint", { MaxTextSize = 28, MinTextSize = 8 }, goBtn)

local function refreshInfo()
	if not sel then
		nameLbl.Text, infoLbl.Text, goBtn.Text = "NO TARGET", "TAP A BODY ON THE CHART", "--"
		goBtn.TextColor3, goStroke.Color = Color3.fromRGB(110, 120, 130), Color3.fromRGB(110, 120, 130)
		return
	end
	local b = BODYMAP[sel]
	local dest = DEST[sel]
	local txt = b.info
	local miss = dest and missingFor(dest) or {}
	if dest and REQS[dest] then txt = txt .. "  |  " .. reqLine(dest) end
	nameLbl.Text, infoLbl.Text = b.name, txt
	local col
	if dest and dest == loc then goBtn.Text, col = "HERE", AMBER
	elseif dest and #miss > 0 then goBtn.Text, col = "LOCKED", RED
	elseif dest then goBtn.Text, col = "GO", GREEN
	else goBtn.Text, col = "N/A", Color3.fromRGB(110, 120, 130) end
	goBtn.TextColor3, goStroke.Color = col, col
end

local function selectBody(id)
	sel = id
	for k, el in pairs(E) do el.sel.Enabled = (k == id) end
	refreshInfo()
end
for id, el in pairs(E) do
	track(el.btn.Activated:Connect(function() selectBody(id) end))
end

local function clampZoom(z) return math.clamp(z, 0.15, 8) end
track(zoomIn.Activated:Connect(function() zoom = clampZoom(zoom * 1.3) end))
track(zoomOut.Activated:Connect(function() zoom = clampZoom(zoom / 1.3) end))
track(fitBtn.Activated:Connect(function() zoom, pan = 0.3, Vector2.zero end))
track(focusBtn.Activated:Connect(function()
	local id = sel or "Sun"
	if lastPos[id] then pan = pan + (mapArea.AbsoluteSize / 2 - lastPos[id]) end
end))

-- drag to pan, wheel / pinch to zoom
local panning, panInput, lastP = false, nil, Vector2.zero
track(mapBG.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
		panning, panInput, lastP = true, i, Vector2.new(i.Position.X, i.Position.Y)
	end
end))
track(UIS.InputChanged:Connect(function(i)
	if panning and (i == panInput or (i.UserInputType == Enum.UserInputType.MouseMovement and panInput.UserInputType == Enum.UserInputType.MouseButton1)) then
		local p = Vector2.new(i.Position.X, i.Position.Y)
		pan = pan + (p - lastP)
		lastP = p
	end
end))
track(UIS.InputEnded:Connect(function(i) if i == panInput then panning = false end end))
track(mapBG.InputChanged:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseWheel then zoom = clampZoom(zoom * 1.15 ^ i.Position.Z) end
end))
local pinchStart = 0.3
track(UIS.TouchPinch:Connect(function(_, scale, _, state)
	if not tabletOpen then return end
	if state == Enum.UserInputState.Begin then pinchStart = zoom end
	zoom = clampZoom(pinchStart * scale)
end))

local function locBodyId()
	return ({ ISS = "ISS", MOON = "Moon", MARS = "Mars", MERCURY = "Mercury", VENUS = "Venus", IO = "Io", EUROPA = "Europa", PLUTO = "Pluto",
		ASTEROID = "Asteroids", JUPITER = "Jupiter", SATURN = "Saturn", URANUS = "Uranus", NEPTUNE = "Neptune" })[loc] or "Earth"
end
local LOCNAME = { EARTH = "EARTH PAD", ORBIT = "EARTH ORBIT", ISS = "ISS DOCKED", MOON = "LUNAR SURFACE",
	MARS = "MARS SURFACE", MERCURY = "MERCURY SURFACE", VENUS = "VENUS SURFACE",
	IO = "IO SURFACE", EUROPA = "EUROPA SURFACE", PLUTO = "PLUTO SURFACE",
	ASTEROID = "ASTEROID BELT", JUPITER = "JUPITER CLOUDS", SATURN = "SATURN CLOUDS", URANUS = "URANUS CLOUDS", NEPTUNE = "NEPTUNE CLOUDS" }
local function updateTablet(dt)
	local sz = mapArea.AbsoluteSize
	local cx, cy = sz.X / 2 + pan.X, sz.Y / 2 + pan.Y
	local pos = {}
	local dScale = math.clamp(zoom ^ 0.5, 0.8, 2.2)
	for _, b in ipairs(BODIES) do
		local el = E[b.id]
		ang[b.id] = ang[b.id] + (b.w or 0) * dt
		local p, rad
		if not b.parent then
			p = Vector2.new(cx, cy)
		else
			rad = b.r * ((b.parent == "Sun") and zoom or math.max(zoom, 0.8))
			p = pos[b.parent] + Vector2.new(math.cos(ang[b.id]), math.sin(ang[b.id])) * rad
			el.ring.Position = UDim2.fromOffset(pos[b.parent].X, pos[b.parent].Y)
			el.ring.Size = UDim2.fromOffset(rad * 2, rad * 2)
		end
		pos[b.id] = p
		lastPos[b.id] = p
		local d = math.max(b.size * dScale, 9)
		el.vis.Size = UDim2.fromOffset(d, d)
		el.btn.Position = UDim2.fromOffset(p.X, p.Y)
		el.btn.Size = UDim2.fromOffset(math.max(d + 8, 28), math.max(d + 8, 28))
		el.lbl.Position = UDim2.fromOffset(p.X, p.Y + d / 2 + 4)
		el.lbl.Visible = (b.parent == nil or b.parent == "Sun") or zoom > 1.4 or sel == b.id
		if el.sat then
			el.sat.Position = UDim2.fromOffset(p.X, p.Y)
			el.sat.Size = UDim2.fromOffset(d * 2.4, d * 0.8)
		end
	end
	for _, d in ipairs(BELT) do
		d.a = d.a + d.w * dt
		local bp = pos.Sun + Vector2.new(math.cos(d.a), math.sin(d.a)) * (d.r * zoom)
		d.f.Position = UDim2.fromOffset(bp.X, bp.Y)
	end
	local hid = locBodyId()
	local hp = pos[hid]
	if hp then
		local d = math.max(BODYMAP[hid].size * dScale, 9) + 12
		hereRing.Position = UDim2.fromOffset(hp.X, hp.Y)
		hereRing.Size = UDim2.fromOffset(d, d)
	end
	locLbl.Text = "LOC: " .. (LOCNAME[loc] or loc)
end

openTablet = function()
	tablet.Visible = true
	tabletOpen = true
	selectBody(locBodyId())
end
closeTablet = function()
	tablet.Visible = false
	tabletOpen = false
end
track(closeBtn.Activated:Connect(closeTablet))
track(navBtn.Activated:Connect(function()
	press(navBtn)
	if not (rocket and spaceMode) then setStatus("NAV OFFLINE - LEAVE THE ATMOSPHERE FIRST", RED) return end
	if tabletOpen then closeTablet() else openTablet() end
end))

----------------------------------------------------------------
-- TUTORIAL BOOK (hotbar item "Space Tutorial Book" + "?" on the tablet)
----------------------------------------------------------------
local PAGES = {
	{ title = "HOW TO TRAVEL", index = true,
		left = "1. Place the Nasa rocket, climb the stairs, tap Enter Rocket? and press LAUNCH S5.\n\n2. Fly past 4000 studs. The sky turns to night and the NAV TABLET opens.\n\n3. Tap a world on the chart and press GO.\n\n4. Some worlds would kill you without survival gear. Collect gear by tapping COLLECT on the glowing crates.\n\n5. Your gear is kept for every flight." },
	{ title = "ISS - SPACE STATION", dest = "ISS", gear = { "O2", "SHIELD" },
		left = "Low Earth orbit. Safe - no gear needed.\n\nWarp there from the tablet and the rocket docks by itself. It is zero gravity: float to the glowing crates above the station core and tap COLLECT.\n\nThese two items are needed for Mars, Mercury and Venus." },
	{ title = "THE MOON", dest = "MOON", gear = { "SAMPLE", "RADSUIT" },
		left = "A light-speed jump, then a landing burn. Safe, zero gravity, no gear needed.\n\nTwo crates near your landing site hold gear for Mars and Mercury. Earth hangs in the sky, spinning slowly.\n\nTo leave, walk back to the rocket, tap Enter Rocket? and use the tablet." },
	{ title = "MARS", dest = "MARS", gear = { "HULL", "CRYO" },
		left = "HAZARDS: the air is thin carbon dioxide - you cannot breathe it. Dust storms clog the filters. Gravity is 38% of Earth.\n\nWithout the right gear you would not survive the landing. Bring the Oxygen Tank and a Lunar Sample (it calibrates the dust filters).\n\nA Pressure Hull Plate and a Cryo Insulation Pack wait near the landing site." },
	{ title = "MERCURY", dest = "MERCURY", gear = { "COATING" },
		left = "HAZARDS: the day side is hotter than 400 C and the radiation is brutal, with almost no atmosphere to shield you. Gravity is 38% of Earth.\n\nBring Heat Shield Plating and the Radiation Suit Module.\n\nAn Acid Coating Canister waits near the landing site." },
	{ title = "VENUS", dest = "VENUS", gear = { "SULFUR" },
		left = "HAZARDS: 465 C, pressure 90 times Earth's, and clouds of sulfuric acid. The hardest trip of all.\n\nBring the Heat Shield Plating, the Pressure Hull Plate from Mars and the Acid Coating Canister from Mercury.\n\nA Sulfur Filter Unit waits near the landing site." },
	{ title = "IO", dest = "IO", gear = {},
		left = "HAZARDS: Jupiter's radiation pours over this moon, volcanoes spray sulfur, and the ground is scorching. Gravity is 18% of Earth. Jupiter fills the sky.\n\nBring the Heat Shield Plating, the Radiation Suit Module and the Sulfur Filter Unit from Venus." },
	{ title = "EUROPA", dest = "EUROPA", gear = { "DRILL" },
		left = "HAZARDS: a frozen crust far colder than anywhere on Earth, with deadly radiation from Jupiter. Gravity is 13% of Earth.\n\nBring the Cryo Insulation Pack from Mars, the Radiation Suit Module and the Pressure Hull Plate.\n\nAn Ice Drill Bit waits near the landing site." },
	{ title = "PLUTO", dest = "PLUTO", gear = {},
		left = "HAZARDS: the far edge of the sun's reach. It is bitterly cold, there is almost no air, and the Sun is only a bright star. Gravity is 6% of Earth.\n\nBring the Cryo Insulation Pack, an Oxygen Tank and the Ice Drill Bit from Europa." },
	{ title = "ASTEROID BELT", dest = "ASTEROID", gear = { "GRAV" },
		left = "HAZARDS: a field of tumbling rock. Micrometeorites hit constantly and there is almost no gravity.\n\nBring the Pressure Hull Plate for impacts and an Oxygen Tank for walking outside.\n\nA Gravity Stabilizer waits on the big asteroid near the landing site. You need it for Jupiter and Saturn." },
	{ title = "JUPITER", dest = "JUPITER", gear = { "JOVE" },
		left = "HAZARDS: crushing gravity (2.5x Earth), deadly radiation and violent storms. There is no ground - you land on a floating cloud-top platform.\n\nBring the Heat Shield Plating, the Radiation Suit Module, the Pressure Hull Plate and the Gravity Stabilizer from the Asteroid Belt.\n\nA Jovian Pressure Seal waits near the platform." },
	{ title = "SATURN", dest = "SATURN", gear = { "RING" },
		left = "HAZARDS: freezing winds and a sky full of ring debris. Gravity is about like Earth. You land on a cloud-top platform under the great rings.\n\nBring the Gravity Stabilizer, the Jovian Pressure Seal from Jupiter and the Cryo Insulation Pack.\n\nA Ring Debris Shield waits near the platform." },
	{ title = "URANUS", dest = "URANUS", gear = { "METH" },
		left = "HAZARDS: the coldest atmosphere in the solar system, methane haze, and a world tipped on its side with thin vertical rings.\n\nBring the Jovian Pressure Seal, the Ring Debris Shield from Saturn and the Cryo Insulation Pack.\n\nA Methane Filter waits near the platform." },
	{ title = "NEPTUNE", dest = "NEPTUNE", gear = {},
		left = "HAZARDS: supersonic winds, dark storms and deep cold at the edge of the giant planets.\n\nBring the Ring Debris Shield, the Methane Filter from Uranus and the Ice Drill Bit from Europa." },
	{ title = "TIPS", tips = true,
		left = "- Use + and - (or pinch) to zoom the chart, drag to move it.\n- FIT resets the chart. O centers on your selection.\n- The green ring on the chart is where you are.\n- On a landed rocket: walk back, tap Enter Rocket?, open the tablet and press GO again.\n- While parked in orbit, push the throttle up to fly freely.\n- Suggested order: ISS, Moon, Mars, Asteroid Belt, Mercury, Venus, Jupiter, Io, Europa, Saturn, Uranus, Neptune, Pluto.\n- Only the Sun and Titan are still placeholders." },
}
local pageIdx = 1

local book = new("Frame", {
	Name = "TutorialBook", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(0.8, 0.88), BackgroundColor3 = Color3.fromRGB(88, 55, 32), Visible = false, ZIndex = 60,
}, gui)
new("UISizeConstraint", { MaxSize = Vector2.new(780, 470), MinSize = Vector2.new(320, 230) }, book)
corner(book, 14) stroke(book, Color3.fromRGB(190, 150, 70), 3)
local INK = Color3.fromRGB(50, 35, 20)
local PARCH = Color3.fromRGB(233, 222, 196)
local bookTitle = new("TextLabel", {
	Text = "SPACE TUTORIAL BOOK", Font = Enum.Font.Antique, TextScaled = true, TextColor3 = Color3.fromRGB(235, 200, 110),
	BackgroundTransparency = 1, Position = UDim2.fromScale(0.05, 0.015), Size = UDim2.fromScale(0.8, 0.08),
}, book)
local bookClose = new("TextButton", {
	Text = "X", Font = Enum.Font.GothamBold, TextScaled = true, TextColor3 = Color3.fromRGB(235, 200, 110),
	BackgroundColor3 = Color3.fromRGB(60, 36, 20), AutoButtonColor = false,
	Position = UDim2.fromScale(0.91, 0.015), Size = UDim2.fromScale(0.07, 0.08),
}, book)
corner(bookClose, 6)

local function page(x)
	local f = new("Frame", { Position = UDim2.fromScale(x, 0.11), Size = UDim2.fromScale(0.455, 0.78), BackgroundColor3 = PARCH }, book)
	corner(f, 6)
	local head = new("TextLabel", {
		Text = "", Font = Enum.Font.Antique, TextScaled = true, TextColor3 = Color3.fromRGB(120, 40, 30), TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1, Position = UDim2.fromScale(0.05, 0.03), Size = UDim2.fromScale(0.9, 0.1),
	}, f)
	local body = new("TextLabel", {
		Text = "", Font = Enum.Font.Antique, TextScaled = true, TextWrapped = true, RichText = true, TextColor3 = INK,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.05, 0.15), Size = UDim2.fromScale(0.9, 0.82),
	}, f)
	new("UITextSizeConstraint", { MaxTextSize = 17, MinTextSize = 6 }, body)
	return head, body
end
local leftHead, leftBody = page(0.03)
local rightHead, rightBody = page(0.515)
new("Frame", { Position = UDim2.fromScale(0.4925, 0.11), Size = UDim2.fromScale(0.015, 0.78), BackgroundColor3 = Color3.fromRGB(60, 36, 20), BorderSizePixel = 0 }, book)

local function navBtn2(text, x)
	local b = new("TextButton", {
		Text = text, Font = Enum.Font.GothamBold, TextScaled = true, TextColor3 = Color3.fromRGB(235, 200, 110),
		BackgroundColor3 = Color3.fromRGB(60, 36, 20), AutoButtonColor = false,
		Position = UDim2.fromScale(x, 0.915), Size = UDim2.fromScale(0.16, 0.07),
	}, book)
	corner(b, 6)
	new("UIPadding", { PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3) }, b)
	return b
end
local prevBtn, nextBtn = navBtn2("< PREV", 0.03), navBtn2("NEXT >", 0.81)
local pageLbl = new("TextLabel", {
	Text = "", Font = Enum.Font.Code, TextScaled = true, TextColor3 = Color3.fromRGB(235, 200, 110), BackgroundTransparency = 1,
	Position = UDim2.fromScale(0.4, 0.92), Size = UDim2.fromScale(0.2, 0.06),
}, book)

local function itemLine(id)
	local it = ITEMS[id]
	local tag = inv[id] and '<font color="#1f8a3a">[OK]</font>' or '<font color="#b02a2a">[--]</font>'
	return tag .. " <b>" .. it.name .. "</b>\n      <i>" .. it.where .. "</i>"
end

local function renderPage()
	local p = PAGES[pageIdx]
	leftHead.Text = p.title
	leftBody.Text = p.left
	pageLbl.Text = pageIdx .. " / " .. #PAGES
	local t = {}
	if p.index then
		rightHead.Text = "GEAR INDEX"
		for id in pairs(ITEMS) do t[#t + 1] = id end
		table.sort(t)
		for i, id in ipairs(t) do t[i] = itemLine(id) end
		rightBody.Text = table.concat(t, "\n")
	elseif p.tips then
		rightHead.Text = "YOUR GEAR"
		for id in pairs(ITEMS) do t[#t + 1] = id end
		table.sort(t)
		for i, id in ipairs(t) do t[i] = (inv[id] and '<font color="#1f8a3a">[OK]</font> ' or '<font color="#b02a2a">[--]</font> ') .. ITEMS[id].name end
		rightBody.Text = table.concat(t, "\n")
	else
		rightHead.Text = REQS[p.dest] and "REQUIRED GEAR" or "NO GEAR NEEDED"
		local s = ""
		if REQS[p.dest] then
			for _, id in ipairs(REQS[p.dest]) do s = s .. itemLine(id) .. "\n" end
			local miss = missingFor(p.dest)
			s = s .. "\n" .. (#miss == 0 and '<b><font color="#1f8a3a">READY - YOU WILL SURVIVE</font></b>' or '<b><font color="#b02a2a">NOT SURVIVABLE YET</font></b>')
		else
			s = "This destination is safe.\n"
		end
		if p.gear and #p.gear > 0 then
			s = s .. "\n\n<b>FOUND HERE</b>\n"
			for _, id in ipairs(p.gear) do s = s .. itemLine(id) .. "\n" end
		end
		rightBody.Text = s
	end
end

openBook = function()
	renderPage()
	book.Visible = true
end
local function closeBook() book.Visible = false end
track(bookClose.Activated:Connect(closeBook))
track(prevBtn.Activated:Connect(function() pageIdx = (pageIdx - 2) % #PAGES + 1 renderPage() end))
track(nextBtn.Activated:Connect(function() pageIdx = pageIdx % #PAGES + 1 renderPage() end))
track(helpBtn.Activated:Connect(function() press(helpBtn) openBook() end))
onInvChanged = function()
	if tabletOpen then refreshInfo() end
	if book.Visible then renderPage() end
end

----------------------------------------------------------------
-- TRAVEL (light speed warp + landing / docking)
----------------------------------------------------------------
local function arriveLand(r, key)
	showScene(key)
	if r.moonPad then r.moonPad:Destroy() r.moonPad = nil end
	r.baseRot = CFrame.new().Rotation
	r.pitch, r.roll = 0, 0
	local P = PLANETS[key]
	r.pos = P.origin + Vector3.new(0, 12 * r.S + P.startH, 0)
	setPivot(r)
end

local function arriveOrbit(r)
	showScene("ORBIT")
	if r.moonPad then r.moonPad:Destroy() r.moonPad = nil end
	r.pitch, r.roll = 0, 0
	r.baseRot = SP.issCF.Rotation
	r.pos = (SP.issCF * CFrame.new(0, 75, 700)).Position
	setPivot(r)
end

local function arriveEarth(r)
	restoreEnv()
	spaceMode = false
	scene = nil
	detachSpace()
	if r.moonPad then r.moonPad:Destroy() r.moonPad = nil end
	r.baseRot = r.origin.Rotation
	r.pitch, r.roll = 0, 0
	r.pos = r.origin.Position + Vector3.new(0, 12 * r.S + 2500, 0)
	setPivot(r)
end

travel = function(dest)
	local r = rocket
	if not r or r.busy or not inside then return end
	if dest == loc then setStatus("ALREADY AT THIS LOCATION", AMBER) return end
	local miss = missingFor(dest)
	if #miss > 0 then
		setStatus("MISSION DENIED - YOU WOULD NOT SURVIVE. MISSING: " .. table.concat(miss, ", "):upper(), RED)
		toast("MISSING GEAR - OPEN THE BOOK (?)", RED)
		return
	end
	r.busy = true
	r.state = "TRAVEL"
	r.docked = false
	closeTablet()
	task.spawn(function()
		local ok, err = pcall(function()
			local from = loc
			r.ignite = true
			r.forceThr = 0.5
			if PLANETS[from] then
				setStatus("LIFTING OFF FROM " .. PLANETS[from].name, AMBER)
				local y0 = r.pos.Y
				frames(r, 3.5, function(a)
					r.forceThr = 0.6 + 0.4 * a
					r.pos = Vector3.new(r.pos.X, y0 + a * a * 350, r.pos.Z)
					setPivot(r)
				end)
			else
				setStatus("SPOOLING WARP DRIVE", AMBER)
				frames(r, 1.2, function(a) r.forceThr = 0.5 + 0.5 * a end)
			end
			if r.dead then return end
			r.forceThr = 1
			setStatus("WARP DRIVE ENGAGED - LIGHT SPEED", CYAN)
			warpSeq(r, 6, function()
				if PLANETS[dest] then arriveLand(r, dest)
				elseif dest == "ISS" then arriveOrbit(r)
				else arriveEarth(r) end
			end)
			if r.dead then return end

			if PLANETS[dest] then
				local P = PLANETS[dest]
				setStatus(P.name .. " APPROACH - LANDING SEQUENCE", AMBER)
				landAt(r, P.origin, P.startH, P.landT, P.dust)
				r.moonPad = buildPad(CFrame.new(P.origin), r.S, true)
				r.moonPad.Parent = worldFolder
				loc = dest
				if P.arrive then
					toast(P.arrive, GREEN)
					setStatus("LANDED ON " .. P.name .. " - GEAR HOLDING", GREEN)
				else
					setStatus("LANDED ON " .. P.name .. (P.grav == 0 and " - ZERO GRAVITY" or ""), GREEN)
				end
			elseif dest == "ISS" then
				setStatus("ISS APPROACH - DOCKING", AMBER)
				frames(r, 5, function(a)
					local e = 1 - (1 - a) ^ 2
					r.baseRot = SP.issCF.Rotation
					r.pos = (SP.issCF * CFrame.new(0, 75, 40 + 660 * (1 - e))).Position
					setPivot(r)
					r.forceThr = 0.1 + 0.4 * (1 - a)
				end)
				r.docked = true
				loc = "ISS"
				setStatus("DOCKED WITH THE ISS - ZERO GRAVITY", GREEN)
			else
				setStatus("ATMOSPHERIC ENTRY - LANDING ON PAD", AMBER)
				landAt(r, r.origin.Position, 2500, 10, Color3.fromRGB(140, 120, 95))
				refurbish(r)
				loc = "EARTH"
				setStatus("TOUCHDOWN - WELCOME HOME", GREEN)
			end
			throttle = 0
			r.forceThr, r.ignite, r.busy = nil, false, false
			r.state = (dest == "EARTH") and "IDLE" or "PARKED"
			r.speed = 0
		end)
		if not ok then
			warn("[NasaRocket] " .. tostring(err))
			r.busy, r.forceThr, r.ignite, r.state = false, nil, false, "PARKED"
			flash.BackgroundTransparency = 1
			camera.FieldOfView = baseFOV
		end
	end)
end

track(goBtn.Activated:Connect(function()
	press(goBtn)
	if not sel then return end
	local dest = DEST[sel]
	if not dest then setStatus("PLACEHOLDER - NOT AVAILABLE YET", AMBER) return end
	travel(dest)
end))

SpaceCleanup = function()
	restoreEnv()
	spaceMode, loc, scene = false, "EARTH", nil
	if closeTablet then closeTablet() end
	for _, k in ipairs({ "earth", "clouds", "moon", "iss", "sun", "stars" }) do
		if SP[k] then SP[k]:Destroy() SP[k] = nil end
	end
	if SP.surface then SP.surface:Destroy() SP.surface = nil end
	if warpM then warpM:Destroy() warpM = nil end
	camera.FieldOfView = baseFOV
	flash.BackgroundTransparency = 1
end

----------------------------------------------------------------
-- main loop
----------------------------------------------------------------
track(RunService.RenderStepped:Connect(function(dt)
	local c, hum, hrp = getChar()

	-- animate space (Earth spin, Moon + ISS orbits, stars follow camera)
	if spaceMode and scene and SP.earth then
		SP.spin = SP.spin + dt * 0.05
		SP.accum = SP.accum + dt
		if SP.accum > 0.06 then
			SP.accum = 0
			updateEarth(SP.earthCenter)
		end
		SP.starT = SP.starT + dt
		if SP.starT > 0.3 then
			SP.starT = 0
			SP.stars:PivotTo(CFrame.new(camera.CFrame.Position))
		end
		if scene == "ORBIT" then
			SP.moonAng = SP.moonAng + dt * 0.05
			local a = SP.moonAng
			local mp = SP.earthCenter + Vector3.new(math.cos(a), math.sin(a) * 0.3, math.sin(a)) * MOON_DIST
			SP.moon:PivotTo(CFrame.new(mp) * CFrame.Angles(0, a, 0))
			updateISS(dt)
			-- carry a floating player along with the docked ISS
			if rocket and rocket.docked and not inside and hrp and SP.prevIssCF then
				hrp.CFrame = SP.issCF * SP.prevIssCF:Inverse() * hrp.CFrame
			end
		end
	end

	-- "Enter Rocket?" near the hatch
	local show = false
	if rocket and not inside and not rocket.busy and (rocket.state == "IDLE" or rocket.state == "PARKED") and hrp then
		local dist = (rocket.state == "IDLE") and CFG.ENTER_DISTANCE or 40
		show = (hrp.Position - standPos(rocket)).Magnitude < dist
	end
	enterBtn.Visible = show

	if tabletOpen then updateTablet(dt) end
	if not rocket then return end
	local r = rocket
	local thr = r.forceThr or ((r.fuel > 0) and throttle or 0)

	-- docked: follow the ISS
	if r.docked and scene == "ORBIT" and SP.issCF then
		r.baseRot = SP.issCF.Rotation
		r.pitch, r.roll = 0, 0
		r.pos = (SP.issCF * ISS_DOCK).Position
		setPivot(r)
	end

	-- parked: throttle up = leave the dock / hover, moon needs the NAV
	if r.state == "PARKED" and inside and not r.busy and throttle > 0.03 then
		if PLANETS[loc] then
			throttle = 0
			setStatus("LANDED - OPEN NAV TO CHOOSE A DESTINATION", AMBER)
		else
			local pv = r.model:GetPivot()
			r.docked = false
			r.baseRot = pv.Rotation
			r.pitch, r.roll = 0, 0
			r.pos = pv.Position
			r.speed = 0
			r.state = "FLY"
			loc = "ORBIT"
			setStatus("FREE FLIGHT - STEER WITH THUMBSTICK", GREEN)
		end
	end

	if r.state == "FLY" then
		if inside and hum then
			local md = hum.MoveDirection
			local look = camera.CFrame.LookVector
			local flat = Vector3.new(look.X, 0, look.Z)
			if md.Magnitude > 0.05 and flat.Magnitude > 0.01 then
				flat = flat.Unit
				local right = flat:Cross(Vector3.yAxis)
				local fwd, rgt = md:Dot(flat), md:Dot(right)
				local lim = math.rad(CFG.MAX_TILT)
				r.pitch = math.clamp(r.pitch - fwd * CFG.STEER_RATE * dt, -lim, lim)
				r.roll = math.clamp(r.roll - rgt * CFG.STEER_RATE * dt, -lim, lim)
			end
		end
		local maxS = r.boosters and CFG.MAX_SPEED_BOOST or CFG.MAX_SPEED_NO_BOOST
		local target = thr * maxS
		r.speed = r.speed + (target - r.speed) * math.min(1, dt * (r.boosters and 0.9 or 0.6))
		r.fuel = math.max(0, r.fuel - thr * dt * 1.1)
		if r.fuel <= 0 then throttle = 0 end
		local rot = r.baseRot * CFrame.Angles(r.pitch, 0, r.roll)
		r.alt = math.max(0, r.alt + rot.UpVector.Y * r.speed * dt)
		r.pos = r.pos + rot.UpVector * r.speed * dt
		setPivot(r)
		if not spaceMode then
			if r.alt >= 3000 then
				rampEnv(math.clamp((r.alt - 3000) / (CFG.SPACE_ALT - 3000), 0, 1))
			end
			if r.alt >= CFG.SPACE_ALT and not r.entering then
				r.entering = true
				enterSpace(r)
			end
		end
	end

	-- engine fx
	for _, e in ipairs(r.engines) do
		local base = 0
		if r.ignite then base = (r.state == "COUNT") and 0.25 or (0.25 + thr * 0.75) end
		e.fire.Rate = base * 220 * (e.booster and 0.6 or 1)
		e.smoke.Rate = base * 90
		e.light.Brightness = base * 4
	end

	-- floating player too far from the parked rocket -> bring them back
	if not inside and hrp and spaceMode and (r.state == "PARKED" or r.state == "FLY") then
		if (hrp.Position - r.model:GetPivot().Position).Magnitude > 1800 then
			hrp.CFrame = CFrame.new(standPos(r))
			hrp.AssemblyLinearVelocity = Vector3.zero
		end
	end

	if inside and hrp then
		local pivot = r.model:GetPivot()
		hrp.CFrame = pivot
		hrp.AssemblyLinearVelocity = Vector3.zero
		camera.CameraType = Enum.CameraType.Scriptable
		local shake = 0
		if r.state == "COUNT" and r.ignite then shake = 0.4
		elseif r.state == "FLY" then shake = 0.1 + thr * 0.6
		elseif r.state == "TRAVEL" then shake = 0.5 end
		local camPos = (pivot * CFrame.new(0, 8, CFG.CAM_DIST)).Position
		local cf = CFrame.lookAt(camPos, pivot.Position + pivot.UpVector * 4, pivot.UpVector)
		camera.CFrame = cf * CFrame.new((math.random() - 0.5) * shake, (math.random() - 0.5) * shake, 0)

		-- HUD
		altV.Text = ("%05d"):format(math.floor(r.alt))
		velV.Text = tostring(math.floor(r.dispSpeed or r.speed))
		fuelV.Text = ("%d%%"):format(math.floor(r.fuel))
		fuelFill.Size = UDim2.fromScale(r.fuel / 100, 1)
		fuelFill.BackgroundColor3 = r.fuel > 30 and GREEN or (r.fuel > 12 and AMBER or RED)
		pctLbl.Text = ("%03d%%"):format(math.floor(thr * 100))
		handle.Position = UDim2.fromScale(0.5, TR_TOP + (1 - thr) * TR_H)
		fill.Size = UDim2.new(0, 8, TR_H * thr, 0)
		fill.BackgroundColor3 = thr < 0.6 and GREEN or (thr < 0.85 and AMBER or RED)
		led.BackgroundColor3 = (r.state == "IDLE" and GREEN) or (r.state == "COUNT" and AMBER) or (r.state == "PARKED" and GREEN) or CYAN

		local canRelease = r.boosters and spaceMode
		relBtn.TextColor3 = canRelease and GREEN or Color3.fromRGB(150, 120, 60)
		launchBtn.TextColor3 = (r.state == "IDLE") and GREEN or Color3.fromRGB(70, 120, 90)
		navBtn.TextColor3 = spaceMode and CYAN or Color3.fromRGB(70, 110, 130)
	end
end))

end
initSpaceSystems()

----------------------------------------------------------------
-- item: carry pose + tap to place
----------------------------------------------------------------
local function poseArms(c)
	local up = math.rad(CFG.ARM_UP)
	local inn = math.rad(CFG.ARM_IN)
	local rs, ls = c:FindFirstChild("RightShoulder", true), c:FindFirstChild("LeftShoulder", true)
	if rs and ls then -- R15
		rs.Transform = CFrame.Angles(up, 0, 0) * CFrame.Angles(0, 0, -inn)
		ls.Transform = CFrame.Angles(up, 0, 0) * CFrame.Angles(0, 0, inn)
		return
	end
	local r6r, r6l = c:FindFirstChild("Right Shoulder", true), c:FindFirstChild("Left Shoulder", true)
	if r6r and r6l then -- R6
		r6r.Transform = CFrame.Angles(0, 0, up)
		r6l.Transform = CFrame.Angles(0, 0, -up)
	end
end

local function onEquip()
	if equipped then return end
	local c, hum, hrp = getChar()
	if not (c and hrp) or inside then return end
	equipped = true
	local model = buildRocket(CFG.CARRY_SCALE, CFrame.new(0, 0, 0), false)
	local root = model.PrimaryPart
	local w = Instance.new("Weld")
	w.Part0 = hrp
	w.Part1 = root
	w.C0 = CFG.CARRY_OFFSET
	w.C1 = CFrame.new()
	w.Parent = root
	model.Parent = c
	carryModel = model
	poseConn = RunService.RenderStepped:Connect(function()
		local cc = player.Character
		if cc then poseArms(cc) end
	end)
	hint.Visible = true
end

local function onUnequip()
	if not equipped then return end
	equipped = false
	hint.Visible = false
	if poseConn then poseConn:Disconnect() poseConn = nil end
	if carryModel then carryModel:Destroy() carryModel = nil end
	local c = player.Character
	if c then
		for _, n in ipairs({ "RightShoulder", "LeftShoulder", "Right Shoulder", "Left Shoulder" }) do
			local j = c:FindFirstChild(n, true)
			if j then j.Transform = CFrame.new() end
		end
	end
end

local function giveTool()
	local bp = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack")
	if tool then tool:Destroy() end
	tool = Instance.new("Tool")
	tool.Name = "Nasa rocket"
	tool.ToolTip = "NASA Rocket"
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.Parent = bp
	local t = tool
	t:GetPropertyChangedSignal("Parent"):Connect(function()
		local c = player.Character
		if c and t.Parent == c then onEquip() else onUnequip() end
	end)

	if bookTool then bookTool:Destroy() end
	bookTool = Instance.new("Tool")
	bookTool.Name = "Space Tutorial Book"
	bookTool.ToolTip = "Space Tutorial Book"
	bookTool.RequiresHandle = false
	bookTool.CanBeDropped = false
	bookTool.Parent = bp
	local bt = bookTool
	bt:GetPropertyChangedSignal("Parent"):Connect(function()
		local c = player.Character
		if c and bt.Parent == c then
			if openBook then openBook() end
			local h = c:FindFirstChildOfClass("Humanoid")
			if h then task.defer(function() h:UnequipTools() end) end
		end
	end)
end

local function tryPlace(screenPos)
	if spaceMode or (rocket and rocket.state ~= "IDLE") then hint.Text = "ROCKET IN USE - CAN'T PLACE NOW" return end
	local c, hum = getChar()
	if not c then return end
	local ray = camera:ScreenPointToRay(screenPos.X, screenPos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { c, worldFolder }
	local res = workspace:Raycast(ray.Origin, ray.Direction * 1500, params)
	if not res then hint.Text = "NOTHING THERE - TAP THE GROUND" return end
	if res.Normal.Y < 0.7 then hint.Text = "TOO STEEP - TAP FLAT GROUND" return end
	hint.Text = "TAP FLAT GROUND TO PLACE THE ROCKET"
	placeRocket(res.Position)
	if hum then hum:UnequipTools() end
end

local tapStart = {}
track(UIS.InputBegan:Connect(function(i, gp)
	if gp then return end
	if i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1 then
		tapStart[i] = { pos = i.Position, t = os.clock() }
	end
end))
track(UIS.InputEnded:Connect(function(i)
	local s = tapStart[i]
	tapStart[i] = nil
	if not s or not equipped or inside then return end
	if (i.Position - s.pos).Magnitude > 12 or os.clock() - s.t > 0.35 then return end -- it was a camera drag, not a tap
	tryPlace(i.Position)
end))

----------------------------------------------------------------
-- respawn handling + cleanup
----------------------------------------------------------------
local function resetOnCharacter()
	equipped = false
	if poseConn then poseConn:Disconnect() poseConn = nil end
	if carryModel then carryModel:Destroy() carryModel = nil end
	hint.Visible = false
	local wasSpace = spaceMode
	if SpaceCleanup then SpaceCleanup() end
	if wasSpace then destroyRocket() end
	if inside then
		inside = false
		console.Visible = false
		cdLabel.Visible = false
		camera.CameraType = Enum.CameraType.Custom
	end
	task.wait(1)
	giveTool()
end
track(player.CharacterAdded:Connect(resetOnCharacter))
giveTool()

genv.NASA_ROCKET_CLEANUP = function()
	for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
	pcall(function() if SpaceCleanup then SpaceCleanup() end end)
	if poseConn then poseConn:Disconnect() end
	if carryModel then carryModel:Destroy() end
	if tool then tool:Destroy() end
	if bookTool then bookTool:Destroy() end
	destroyRocket()
	worldFolder:Destroy()
	gui:Destroy()
	camera.CameraType = Enum.CameraType.Custom
	local _, hum, hrp = getChar()
	if hrp then hrp.Anchored = false end
	if hum then camera.CameraSubject = hum end
	setCharHidden(false)
end
