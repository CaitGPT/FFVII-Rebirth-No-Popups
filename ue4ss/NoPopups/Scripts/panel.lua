-- The objective list the game draws for a combat assignment, drawn by the mod.
--
-- With the pop-ups off the game builds no EventProgress widget at all, so this
-- is built from plain UMG at runtime, following Battle Meters' overlay: the
-- game's own EndTextBlock and EndImage draw nothing when created this way, so
-- the text is the engine's Roboto and the plates are tinted Image widgets.
-- Placement and colours are measured from a vanilla capture of Junon Fiend
-- Intel 2 (assignment-checklist.jpg, 2026-11-15).
local M = {}

local VISIBLE, COLLAPSED = 3, 1       -- ESlateVisibility: HitTestInvisible, Collapsed
local ROWS = 6                        -- no assignment has more than three, with room to spare

-- 1920x1080 units, from the capture (x1.627 from its 1180-wide frame).
local LEFT, TOP = 36, 42
local PLATE_W = 470
local TAB_W, TAB_H = 118, 22
local MAIN_Y, MAIN_H = 28, 30
local ROW_Y, ROW_STEP, ROW_H = 62, 33, 28
local BOX, BOX_X = 15, 22
local TEXT_X = 48

local AMBER = {R = 0.96, G = 0.78, B = 0.22, A = 1}
local AMBER_DIM = {R = 0.78, G = 0.66, B = 0.32, A = 1}
local WHITE = {R = 1, G = 1, B = 1, A = 1}
local PLATE = {R = 0, G = 0, B = 0, A = 0.45}
local TAB_PLATE = {R = 0.21, G = 0.16, B = 0.03, A = 0.92}
local BOX_FILL = {R = 0.04, G = 0.04, B = 0.04, A = 0.75}
local SHADOW = {R = 0, G = 0, B = 0, A = 0.75}

local ui = nil

local function safe(f, ...)
    local ok, value = pcall(f, ...)
    if ok then return value end
    return nil
end
local function valid(object)
    return object ~= nil and safe(function() return object:IsValid() end) == true
end
local function find(path)
    local object = safe(StaticFindObject, path)
    return valid(object) and object or nil
end

local function new_name(self, prefix)
    self.count = self.count + 1
    return FName("NoPopups" .. prefix .. self.count)
end

local function add_image(self, tint)
    local image = StaticConstructObject(self.image_class, self.tree, new_name(self, "Image"))
    image:SetColorAndOpacity(tint or WHITE)
    local slot = self.canvas:AddChildToCanvas(image)
    slot:SetAutoSize(false)
    return {widget = image, slot = slot}
end

local function add_text(self, size, colour)
    local text = StaticConstructObject(self.text_class, self.tree, new_name(self, "Text"))
    text.Font.Size = size
    text.Font.TypefaceFontName = FName("Regular")
    text:SetColorAndOpacity({SpecifiedColor = colour, ColorUseRule = 0})
    text:SetShadowOffset({X = 2, Y = 2})
    text:SetShadowColorAndOpacity(SHADOW)
    local slot = self.canvas:AddChildToCanvas(text)
    slot:SetAutoSize(false)
    return {widget = text, slot = slot}
end

local function create(world_object)
    local statics = find("/Script/Engine.Default__GameplayStatics")
    local library = find("/Script/UMG.Default__WidgetBlueprintLibrary")
    local widget_class = find("/Script/UMG.UserWidget")
    local text_class, image_class = find("/Script/UMG.TextBlock"), find("/Script/UMG.Image")
    if not (statics and library and widget_class and text_class and image_class) then
        return nil, "UMG classes not found"
    end
    -- In a battle GetPlayerController can come back empty even with a live
    -- pawn (live 2026-11-15), so the controller is looked up directly then.
    local controller = nil
    if world_object ~= nil then
        controller = safe(function() return statics:GetPlayerController(world_object, 0) end)
    end
    if not valid(controller) then controller = safe(FindFirstOf, "EndPlayerControllerBP_C") end
    if not valid(controller) then return nil, "no player controller" end
    local widget = safe(function() return library:Create(controller, widget_class, controller) end)
    if not valid(widget) then return nil, "Create failed" end

    local tree = StaticConstructObject(find("/Script/UMG.WidgetTree"), widget, FName("NoPopupsTree"))
    widget.WidgetTree = tree
    local canvas = StaticConstructObject(find("/Script/UMG.CanvasPanel"), tree, FName("NoPopupsCanvas"))
    tree.RootWidget = canvas
    local self = {widget = widget, tree = tree, canvas = canvas,
        text_class = text_class, image_class = image_class, count = 0, rows = {}}

    -- Built back to front, once; what is not needed is collapsed.
    self.tab_plate = add_image(self, TAB_PLATE)
    self.main_plate = add_image(self, PLATE)
    self.tab = add_text(self, 14, AMBER)
    self.main_mark = add_text(self, 20, AMBER)
    self.main = add_text(self, 21, AMBER)
    for i = 1, ROWS do
        self.rows[i] = {plate = add_image(self, PLATE), box = add_image(self, AMBER),
                        fill = add_image(self, BOX_FILL), text = add_text(self, 18, WHITE)}
    end
    widget:AddToViewport(900)
    widget:SetVisibility(VISIBLE)
    return self
end

local function place(item, x, y, w, h)
    if item.x ~= x or item.y ~= y then
        item.slot:SetPosition({X = x, Y = y}); item.x, item.y = x, y
    end
    if item.w ~= w or item.h ~= h then
        item.slot:SetSize({X = w, Y = h}); item.w, item.h = w, h
    end
    if item.hidden ~= false then item.widget:SetVisibility(VISIBLE); item.hidden = false end
end

local function collapse(item)
    if item and item.hidden ~= true then item.widget:SetVisibility(COLLAPSED); item.hidden = true end
end

local function set_text(item, value)
    if item.shown ~= value then item.widget:SetText(FText(value)); item.shown = value end
end

local function set_text_colour(item, colour)
    if item.colour ~= colour then
        item.widget:SetColorAndOpacity({SpecifiedColor = colour, ColorUseRule = 0})
        item.colour = colour
    end
end

-- view = {tab = "World Intel", title = "Defeat All Nearby Enemies", title_done = false,
--         rows = {{text = "Stagger an enemy.", done = false}, ...}}
local function draw(self, view)
    place(self.tab_plate, LEFT, TOP, TAB_W, TAB_H)
    set_text(self.tab, view.tab)
    place(self.tab, LEFT + 8, TOP + 2, TAB_W, TAB_H)

    place(self.main_plate, LEFT, TOP + MAIN_Y, PLATE_W, MAIN_H)
    set_text(self.main_mark, view.title_done and "x" or "+")
    place(self.main_mark, LEFT + 6, TOP + MAIN_Y + 2, 24, MAIN_H)
    set_text(self.main, view.title)
    place(self.main, LEFT + 30, TOP + MAIN_Y + 3, PLATE_W - 30, MAIN_H)

    for i = 1, ROWS do
        local row, item = view.rows[i], self.rows[i]
        if row then
            local y = TOP + ROW_Y + (i - 1) * ROW_STEP
            place(item.plate, LEFT + 14, y, PLATE_W - 14, ROW_H)
            place(item.box, LEFT + BOX_X, y + 5, BOX, BOX)
            if row.done then
                collapse(item.fill)                       -- a filled box reads as ticked
            else
                place(item.fill, LEFT + BOX_X + 2, y + 7, BOX - 4, BOX - 4)
            end
            set_text(item.text, row.text)
            set_text_colour(item.text, row.done and AMBER_DIM or WHITE)
            place(item.text, LEFT + TEXT_X, y + 3, PLATE_W - TEXT_X, ROW_H)
        else
            collapse(item.plate); collapse(item.box); collapse(item.fill); collapse(item.text)
        end
    end
end

function M.show(view, world_object)
    -- A level change takes the panel off the screen without destroying it.
    if not (ui and valid(ui.widget) and safe(function() return ui.widget:IsInViewport() end) == true) then
        local made, problem = create(world_object)
        if not made then
            if M.last_error ~= problem then print("[NoPopups] panel: " .. tostring(problem)) end
            M.last_error = problem
            return false
        end
        ui = made
        print("[NoPopups] panel created")
    end
    if ui.hidden then ui.widget:SetVisibility(VISIBLE); ui.hidden = false end
    draw(ui, view)
    return true
end

function M.hide()
    if ui and not ui.hidden and valid(ui.widget) then
        ui.widget:SetVisibility(COLLAPSED); ui.hidden = true
    end
end

return M
