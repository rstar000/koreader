local Generic = require("device/generic/device") -- <= look at this file!
local TimeVal = require("ui/timeval")
local logger = require("logger")

local function yes() return true end
local function no() return false end

local Bookeen = Generic:new{
    model = "Bookeen",
    isBookeen = yes,
    hasKeys = yes,
    hasOTAUpdates = yes,
    canReboot = yes,
    canPowerOff = yes,
    isTouchDevice = yes,
    isAlwaysPortrait = yes,
    hasMultitouch = yes,
    hasFrontlight = yes,
    touch_probe_ev_epoch_time = yes,
    touch_switch_xy = yes,
    display_dpi = 212,
}

local EV_ABS = 3
local ABS_X = 00
local ABS_Y = 01
local ABS_MT_POSITION_X = 53
local ABS_MT_POSITION_Y = 54

local screen_width = 1024 -- unscaled_size_check: ignore
local screen_height = 768 -- unscaled_size_check: ignore
local mt_width = 767 -- unscaled_size_check: ignore
local mt_height = 1023 -- unscaled_size_check: ignore
local mt_scale_x = screen_width / mt_width
local mt_scale_y = screen_height / mt_height

local probeEvEpochTime
-- this function will update itself after the first touch event
probeEvEpochTime = function(self, ev)
    local now = TimeVal:now()
    -- This check should work as long as main UI loop is not blocked for more
    -- than 10 minute before handling the first touch event.
    if ev.time.sec <= now.sec - 600 then
        -- time is seconds since boot, force it to epoch
        probeEvEpochTime = function(_, _ev)
            _ev.time = TimeVal:now()
        end
        ev.time = now
    else
        -- time is already epoch time, no need to do anything
        probeEvEpochTime = function(_, _) end
    end
end
function Bookeen:initEventAdjustHooks()
    if self.touch_switch_xy then
        self.input:registerEventAdjustHook(self.input.adjustTouchSwitchXY)
    end
    if self.touch_mirrored_x then
        self.input:registerEventAdjustHook(
            self.input.adjustTouchMirrorX,
            self.screen:getWidth()
        )
    end
    if self.touch_probe_ev_epoch_time then
        self.input:registerEventAdjustHook(function(_, ev)
            probeEvEpochTime(_, ev)
        end)
    end

    if self.touch_legacy then
        self.input.handleTouchEv = self.input.handleTouchEvLegacy
    end
end


function Bookeen:init()
    self.screen = require("ffi/framebuffer_mxcfb"):new{device = self, debug = logger.dbg}
    self.powerd = require("device/bookeen/powerd"):new{device = self}
    self.input = require("device/input"):new{
        device = self,
        event_map = {
            [407] = "LPgFwd",
            [158] = "LPgBack",
            [139] = "Home",
            [116] = "Power",
        },
    }

    self.input.open("/dev/input/event0") -- Face buttons
    self.input.open("/dev/input/event1") -- Power button
    self.input.open("/dev/input/event2") -- Touch screen
    self.input.open("/dev/input/event3") -- Accelerometer
    -- self.input.handleTouchEv = self.input.handleTouchEvPhoenix
    self:initEventAdjustHooks()
    -- self.input.open("fake_events")
    -- self.input:registerEventAdjustHook(adjustTouchEvt)
    -- USB plug/unplug, battery charge/not charging are generated as fake events

    local rotation_mode = self.screen.ORIENTATION_PORTRAIT
    self.screen.native_rotation_mode = rotation_mode
    self.screen.cur_rotation_mode = rotation_mode

    Generic.init(self)
end

function Bookeen:supportsScreensaver() return true end

function Bookeen:setDateTime(year, month, day, hour, min, sec)
    -- if hour == nil or min == nil then return true end
    -- local command
    -- if year and month and day then
    --     command = string.format("timedatectl set-time '%d-%d-%d %d:%d:%d'", year, month, day, hour, min, sec)
    -- else
    --     command = string.format("timedatectl set-time '%d:%d'",hour, min)
    -- end
    -- return os.execute(command) == 0
end

function Bookeen:intoScreenSaver()
    -- local Screensaver = require("ui/screensaver")
    -- if self.screen_saver_mode == false then
    --     Screensaver:show()
    -- end
    -- self.powerd:beforeSuspend()
    -- self.screen_saver_mode = true
end

function Bookeen:outofScreenSaver()
    -- if self.screen_saver_mode == true then
    --     local Screensaver = require("ui/screensaver")
    --     Screensaver:close()
    -- end
    -- self.powerd:afterResume()
    -- self.screen_saver_mode = false
end

function Bookeen:suspend()
    -- os.execute("systemctl suspend")
end

function Bookeen:resume()
end

function Bookeen:powerOff()
    os.execute("poweroff")
end

function Bookeen:reboot()
    os.execute("reboot")
end

return Bookeen


