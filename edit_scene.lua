local themes = require('themes')
local ssvc = require('chord')
local audio = require('audio')
local edit = require('editor')
local converter = require('svg_converter')

local ins = table.insert
local min, floor = math.min, math.floor
local sin, log = math.sin, math.log
local tostring = tostring
local KBisDown = love.keyboard.isDown

---@type Zenitha.Scene
local scene = {}

function scene.load()
    edit:newChord(1)
    edit:moveCursor(0)
end

function scene.wheelMove(_, dy)
    if KBisDown('lshift', 'rshift') then
        edit:scroll(-dy / 2.6, 0)
    elseif KBisDown('lctrl', 'rctrl') then
        edit:scale(1 + dy * .1)
    else
        edit:scroll(0, -dy / 2.6)
    end
end

function scene.keyDown(key, isRep)
    if key == 'lctrl' or key == 'rctrl' or key == 'lshift' or key == 'rshift' or key == 'lalt' or key == 'ralt' then
        return true
    end
    local CTRL = KBisDown('lctrl', 'rctrl')
    local SHIFT = KBisDown('lshift', 'rshift')
    local ALT = KBisDown('lalt', 'ralt')

    if key == 'space' then
        if isRep then return true end
        if edit.playing then
            edit:stopPlaying()
        elseif SHIFT then
            -- Play selected note
            audio.playNote(edit.curPitch)
        else
            -- Play selected chords
            edit.playL, edit.playR = edit:getSelection()
            edit.playing = edit.playL
            -- editor.timer0 = .5 + .5 / (editor.playR - editor.playL + 1)
            edit.timer0 = .62
            edit:playChord()
        end
    elseif key == 'down' or key == 'up' then
        if CTRL then return true end
        if ALT then
            -- Move chord
            local s, e = edit:getSelection()
            for i = s, e do
                edit:moveChord(edit.chordList[i], key == 'up' and edit.gridStep or -edit.gridStep)
            end
            edit:focusCursor()
        else
            -- Select note
            local allInfo = TABLE.flatten(TABLE.copyAll(edit.chordList[edit.cursor].tree))
            local pitchInfo = TABLE.alloc()
            for k, v in next, allInfo do
                if k:sub(-5) == 'pitch' then
                    ins(pitchInfo, { v, k:sub(1, -7) })
                end
            end
            table.sort(pitchInfo, edit._pitchSorter)
            local curPos
            for i = 1, #pitchInfo do
                if pitchInfo[i][1] == edit.curPitch then
                    curPos = i; break
                end
            end
            if not curPos then return end
            if key == 'up' then
                while curPos < #pitchInfo and (pitchInfo[curPos][1] <= edit.curPitch) do curPos = curPos + 1 end
            else
                while curPos > 1 and (pitchInfo[curPos][1] >= edit.curPitch) do curPos = curPos - 1 end
            end
            edit.curPitch = pitchInfo[curPos][1]
            edit.ghostPitch = edit.curPitch
            edit.nCur = STRING.split(pitchInfo[curPos][2], ".")
            for i = 1, #edit.nCur do
                edit.nCur[i] = tonumber(edit.nCur[i])
            end
            edit:refreshText()
            TABLE.free(pitchInfo)
            edit:focusCursor()
        end
    elseif key == 'left' or key == 'right' then
        if CTRL then return true end
        if ALT then
            -- Bias note
            if #edit.nCur == 0 then return true end
            local chord, curNote = edit:getChord(), edit:getNote()
            local tar = key == 'left' and 'l' or 'r'
            if curNote.bias ~= tar then
                curNote.bias = not curNote.bias and tar or nil
                edit:renderChord(chord)
            end
            edit:focusCursor()
        else
            -- Move cursor (normally)
            edit:moveCursor(key == 'left' and -1 or 1)
            edit:focusCursor()
        end
    elseif key == 'pageup' then
        if isRep then return true end
        edit:moveCursor(-4)
        edit:focusCursor()
    elseif key == 'pagedown' then
        if isRep then return true end
        edit:moveCursor(4)
        edit:focusCursor()
    elseif key == 'home' then
        if isRep then return true end
        edit:moveCursor(-1e99)
        edit:focusCursor()
    elseif key == 'end' then
        if isRep then return true end
        edit:moveCursor(1e99)
        edit:focusCursor()
    elseif key == 'return' then
        if isRep then return true end
        -- Create new chord
        edit:newChord(edit.cursor + 1, not CTRL)
        edit:moveCursor(1)
        edit:focusCursor()
    elseif key == 'backspace' then
        if isRep then return true end
        if ALT then
            edit:reCalculatePitch(edit:getChord().tree, 1)
            edit.curPitch = 1
            edit.ghostPitch = edit.curPitch
            edit:focusCursor()
        else
            -- Delete selected note
            edit:deleteCursorNote()
            edit:focusCursor()
        end
    elseif key == 'delete' then
        if isRep then return true end
        -- Delete current chord
        edit:deleteChord(edit:getSelection())
        edit.selMark = false
        edit:focusCursor()
    elseif #key == 1 and MATH.between(tonumber(key) or 0, 1, 7) then
        if isRep then return true end

        local keyNum = tonumber(key)
        ---@cast keyNum number

        if ALT then
            -- Set custom grid step
            edit.gridStep = keyNum
            edit.gridStepAnimTimer = .42
            edit:focusCursor()
        else
            -- Add/Remove note
            local step = keyNum
            if SHIFT then step = -step end
            local curNote = edit:getNote()
            local exist
            for i = 1, #curNote do
                if curNote[i].d == step then
                    exist = i
                    break
                end
            end

            local pitch = edit.curPitch * ssvc.dimData[step].freq
            local needRender
            if not exist then
                ins(curNote, { d = step, pitch = pitch })
                table.sort(curNote, edit._levelSorter)
                needRender = true
            end
            if CTRL then
                curNote.note = 'mute'
                needRender = true
            end
            if needRender then edit:renderChord(edit:getChord()) end
            edit:focusCursor()

            audio.playNote(pitch, nil, .26)
        end
    elseif ALT and key == 'm' then
        if isRep then return true end
        -- Mark selected note as mute note
        local curNote = edit:getNote()
        curNote.note = curNote.note ~= 'mute' and 'mute' or nil
        edit:renderChord(edit:getChord())
        edit:focusCursor()
    elseif ALT and key == 'h' then
        if isRep then return true end
        -- Mark selected note as hidden note
        local curNote = edit:getNote()
        curNote.note = curNote.note ~= 'skip' and 'skip' or nil
        edit:renderChord(edit:getChord())
        edit:focusCursor()
    elseif ALT and key == 'b' then
        if isRep then return true end
        -- Mark selected note as base
        edit:switchBase()
        edit:focusCursor()
    elseif ALT and key == 'l' then
        if isRep then return true end
        -- Switch extended line
        edit:switchExtended()
        edit:focusCursor()
    elseif CTRL and key == 'a' then
        if isRep then return true end
        -- Select all
        edit:moveCursor(-1e99)
        edit.selMark = #edit.chordList
        edit:focusCursor()
    elseif CTRL and key == 'c' then
        if isRep then return true end
        -- Copy
        local res = edit:dumpChord(true, edit:getSelection())
        CLIPBOARD.set(table.concat(res, ' '))
        MSG('check', "Copied " .. #res .. " chords")
    elseif CTRL and key == 'x' then
        if isRep then return true end
        -- Cut (Copy+Delete)
        local res = edit:dumpChord(true, edit:getSelection())
        CLIPBOARD.set(table.concat(res, ' '))
        edit:deleteChord(edit:getSelection())
        edit:moveCursor(0)
        edit.selMark = false
        MSG('check', "Cut " .. #res .. " chords")
        edit:focusCursor()
    elseif CTRL and key == 'v' then
        if isRep then return true end
        -- Paste (after)
        local count = edit:pasteChord(CLIPBOARD.get(), edit.cursor)
        MSG('check', "Pasted " .. count .. " chords")
        edit:focusCursor()
    elseif SHIFT and key == 'v' then
        if isRep then return true end
        -- Paste (before)
        edit.cursor = edit.cursor - 1
        local count = edit:pasteChord(CLIPBOARD.get(), edit.cursor)
        MSG('check', "Pasted " .. count .. " chords")
        edit.cursor = edit.cursor + 1
        edit:focusCursor()
    elseif CTRL and key == 'e' then
        if isRep then return true end
        -- Export SVG
        local fileName = os.date("progression_%y%m%d_%H%M%S.svg") ---@cast fileName string
        local s, e = edit:getSelection()
        local chordPitches = {}
        for i = 1, #edit.chordList do
            chordPitches[i] = log(edit.chordList[i].tree.pitch, 2)
        end
        FILE.save(converter(edit:dumpChord(false, s, e), chordPitches), fileName)
        MSG('check', ("Exported %d chord%s to file " .. fileName .. ",\nPress Ctrl+D to open the export directory"):format(
            e - s + 1,
            e > s and "s" or ""
        ))
    elseif CTRL and key == 'd' then
        if isRep then return true end
        -- Open export directory
        UTIL.openSaveDirectory()
    elseif key == 'tab' then
        if isRep then return true end
        edit:switchTheme()
    elseif key == 'escape' then
        if isRep then return true end
        -- Clear selection
        edit.selMark = false
    end
    return true
end

-- function scene.keyUp(key)
-- end

function scene.update(dt)
    edit:update(dt)
    audio.update(dt)
end

local gc = love.graphics
local gc_push, gc_pop = gc.push, gc.pop
local gc_clear, gc_replaceTransform = gc.clear, gc.replaceTransform
local gc_translate, gc_scale = gc.translate, gc.scale
local gc_setColor, gc_setLineWidth = gc.setColor, gc.setLineWidth
local gc_print, gc_draw, gc_line = gc.print, gc.draw, gc.line
local gc_rectangle = gc.rectangle
local gc_setAlpha, gc_setColorMask = GC.setAlpha, GC.setColorMask
local gc_mDraw, gc_strokeDraw = GC.mDraw, GC.strokeDraw

local keyboardQuad = GC.newQuad(0, 0, 137, 543 * 6, TEX.dark.keyboard)
TEX.dark.keyboard:setWrap('clampzero', 'repeat')
TEX.bright.keyboard:setWrap('clampzero', 'repeat')
function scene.draw()
    local theme = themes[edit.theme]
    ---@diagnostic disable-next-line
    local tex = TEX[edit.theme] ---@type SSVT.TextureMap
    local X, Y, K = edit.scrX1, edit.scrY1, edit.scrK1

    FONT.set(30)

    gc_clear(theme.bgbase)

    gc_replaceTransform(SCR.xOy)
    gc_setColor(theme.bg)
    gc_rectangle('fill', 0, 0, SCR.w0, SCR.h0)

    if edit.gridStepAnimTimer > 0 then
        gc_replaceTransform(SCR.xOy_m)
        gc_setColor(1, 1, 1, edit.gridStepAnimTimer)
        gc_mDraw(tex.symbol[edit.gridStep], 0, 0, 0, 2)
    end

    gc_replaceTransform(SCR.xOy_ur)
    gc_setColor(1, 1, 1, .26)
    gc_mDraw(TEX.lamplight, -40, 40, 0, .16)

    gc_replaceTransform(SCR.xOy_l)
    gc_translate(100, 0)
    gc_scale(260 * K)
    gc_translate(-X, -Y)
    local topY = Y - 2.6 / K
    local btmY = Y + 2.6 / K

    -- Grid line
    do
        gc_setLineWidth(.01)
        gc_setColor(theme.dimGridColor[edit.gridStep])
        local dist = log(ssvc.dimData[edit.gridStep].freq, 2)
        local y = 0
        gc_translate(X, 0)
        while y < 2.6 do
            gc_line(-2.6, y, 26, y)
            y = y + dist
        end
        y = -dist
        while y > -3.5 do
            gc_line(-2.6, y, 26, y)
            y = y - dist
        end
        gc_translate(-X, 0)
    end

    -- Selection
    do
        ---@type number, number
        local s, e = edit.cursor1, edit.selMark or edit.cursor1
        if s > e then s, e = e, s end
        s, e = (s - 1) * 1.2, e * 1.2
        gc_setColor(theme.select)
        gc_rectangle('fill', s, topY, e - s, btmY - topY)
        if edit.selMark then
            gc_setColor(theme.cursor)
            gc_draw(TEX.transition, s, 0, 0, .2 / 128, 12, 0, .5)
            gc_draw(TEX.transition, e, 0, 0, -.2 / 128, 12, 0, .5)
        end
    end

    -- Chords
    gc_push('transform')
    for i = 1, #edit.chordList do
        -- Separator line
        gc_setColor(theme.sepLine)
        gc_setLineWidth(.01)
        gc_line(1.2, topY, 1.2, btmY)

        -- Chord textures
        gc_setColor(1, 1, 1)
        local drawData = edit.chordList[i].drawData
        local dy = -log(edit.chordList[i].tree.pitch, 2)

        if not edit.selMark and i == edit.cursor then
            local float = .0126 + .0026 * sin(love.timer.getTime() * 2.6)
            for j = 1, #drawData do
                local d = drawData[j]
                local t = tex[d.texture]
                local x, y = .1 + d.x, dy + d.y
                local kx, ky = d.w / t:getWidth(), d.h / t:getHeight()
                gc_setColorMask(true, false, false, false)
                gc_draw(t, x, y - float, 0, kx, ky)
                gc_setColorMask(false, true, false, false)
                gc_draw(t, x, y, 0, kx, ky)
                gc_setColorMask(false, false, true, false)
                gc_draw(t, x, y + float, 0, kx, ky)
                gc_setColorMask()
            end
        else
            for j = 1, #drawData do
                local d = drawData[j]
                local t = tex[d.texture]
                gc_draw(t, .1 + d.x, dy + d.y, 0, d.w / t:getWidth(), d.h / t:getHeight())
            end
        end

        -- Chord Code
        gc_setColor(theme.text)
        gc_scale(1 / K)
        local text = edit.chordList[i].textObj
        gc_draw(text, .03, 1.75 + Y * K, 0, min(.004, 1.14 / text:getWidth() * K), .004)
        gc_scale(K)

        gc_translate(1.2, 0)
    end
    gc_pop()

    -- Keyboard
    gc_setColor(1, 1, 1, MATH.clampInterpolate(.1, 1, .26, .26, X))
    gc_draw(tex.keyboard, keyboardQuad, X - .36, -3.206, 0, .00184)

    -- Cursor
    do
        gc_setColor(theme.cursor)
        local x, y = 1.2 * (edit.cursor1 - 1), -log(edit.curPitch1, 2)
        gc_draw(TEX.transition, X, y, 0, 1 / 128, 2.6 / 128, 128, .5)
        gc_print(tostring(floor(440 * edit.curPitch)), X - .37, y - .09, 0, .0018)
        gc_setAlpha(.7 + .3 * sin(love.timer.getTime() * 6.2))
        gc_setLineWidth(.01)
        gc_rectangle('line', x, y - .03, 1.2, .06)
        if edit.ghostPitch ~= edit.curPitch then
            gc_setAlpha(.1)
            gc_rectangle('fill', x, -log(edit.ghostPitch, 2) - .03, 1.2, .06)
        end
        gc_setColor(0, 0, 0)
        gc_strokeDraw('corner', .0042, edit.cursorText, x - .04, y - .16, 0, .0035)
        gc_setColor(theme.cursor)
        gc_draw(edit.cursorText, x - .04, y - .16, 0, .0035)
    end

    -- Playing selection
    if edit.playing then
        local s, e = edit.playL, edit.playR
        s, e = (s - 1) * 1.2, e * 1.2
        gc_setColor(theme.preview)
        gc_draw(TEX.transition, s, 0, 0, .2 / 128, 12, 0, .5)
        gc_draw(TEX.transition, e, 0, 0, -.2 / 128, 12, 0, .5)
        gc_setLineWidth(.026)
        gc_setColor(theme.playline)
        local progress = edit.playing + (1 - edit.timer / edit.timer0)
        local x = MATH.interpolate(edit.playL, s, edit.playR + 1, e, progress)
        gc_line(x, topY, x, btmY)
    end
end

local aboutText = [[
Based on Shasavistic Music Theory
Original theory & art design from L4MPLIGHT
App design & developed by MrZ_26
]]
local hintText1 = [[
Help (Edit)
Num(1-7)        Add note
Shift+[Num]     Add downwards
Alt+M           Mute note
Alt+H            Hide note
Alt+B            Mark base note
Alt+L            Add extended line
Ctrl+[Num]      Mute & Add note

Alt+[Num]       Change grid step
Alt+Up/Down    Move chord
Alt+Left/Right   Bias note

Bksp             Delete note
Alt+Bksp         Reset chord pitch

Enter            Add chord
Delete           Delete chord
]]
local hintText2 = [[
Help (Navigation)
(Ctrl/Shift+)WHEEL      Scroll & Zoom

ARROW                  Move cursor
PgUp/PgDn/Home/End  Fast Move
Ctrl+ARROW/'-'/'='       Scroll & Zoom

Shift+[Move]             Create selection
Ctrl+A                    Select all
Ctrl+C/V/X               Copy/Paste/Cut
Shift+V                   Paste before cursor
Ctrl+E                    Export SVG
Ctrl+D                    Open export directory

Tab                       Switch theme
F11                        Fullscreen
]]
hintText1 = hintText1:gsub(" ", "  ")
hintText2 = hintText2:gsub(" ", "  ")
hintText1 = hintText1:gsub("(%S)  (%S)", "%1 %2")
hintText2 = hintText2:gsub("(%S)  (%S)", "%1 %2")
scene.widgetList = {
    WIDGET.new {
        type = 'hint',
        fontSize = 50, frameColor = COLOR.X,
        pos = { 1, 0 }, x = -40, y = 40, w = 60,
        labelPos = 'bottomLeft',
        floatText = aboutText,
        floatFontSize = 30,
        floatFillColor = { .1, .1, .1, .62 },
    },
    WIDGET.new {
        type = 'hint', text = "?",
        fontSize = 50, frameColor = COLOR.lG, textColor = { .62, .9, .62 },
        pos = { 1, 0 }, x = -110, y = 40, w = 60,
        labelPos = 'bottomLeft',
        floatText = hintText1,
        floatFontSize = 30,
        floatFillColor = { .1, .1, .1, .62 },
    },
    WIDGET.new {
        type = 'hint', text = "?",
        fontSize = 50, frameColor = COLOR.lR, textColor = { 1, .62, .62 },
        pos = { 1, 0 }, x = -180, y = 40, w = 60,
        labelPos = 'bottomLeft',
        floatText = hintText2,
        floatFontSize = 30,
        floatFillColor = { .1, .1, .1, .62 },
    },
}

return scene
