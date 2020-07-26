local Generic = require("device/generic/device") -- <= look at this file!
local WakeupMgr = require("device/wakeupmgr")
local logger = require("logger")
local TimeVal = require("ui/timeval")
local logger = require("logger")

local function yes() return true end
local function no() return false end


local Bookeen = Generic:new{
    model = "Bookeen",
    isBookeen = yes,
    hasKeys = yes,
    hasOTAUpdates = yes,
    hasWifiManager = yes,
    canReboot = yes,
    canPowerOff = yes,
    canHWInvert = no,
    isTouchDevice = yes,
    isAlwaysPortrait = yes,
    hasMultitouch = yes,
    hasFrontlight = yes,
    touch_probe_ev_epoch_time = yes,
    touch_switch_xy = yes,
    touch_mirrored_x = yes,
    display_dpi = 212,
}

local function bookeenEnableWifi(toggle)
    if toggle == 1 then
        logger.info("Bookeen: enabling Wifi")
        os.execute("./wlan.sh start")
    else
        logger.info("Bookeen: disabling Wifi")
        os.execute("./wlan.sh stop")
    end
end

function Bookeen:initNetworkManager(NetworkMgr)
    function NetworkMgr:turnOffWifi(complete_callback)
        bookeenEnableWifi(0)
        self.releaseIP()
    end

    function NetworkMgr:turnOnWifi(complete_callback)
        bookeenEnableWifi(1)
        self:reconnectOrShowNetworkMenu(complete_callback)

    end

    NetworkMgr:setWirelessBackend(
        "wpa_supplicant", {ctrl_interface = "/var/run/wpa_supplicant/wlan0"})

    function NetworkMgr:obtainIP()
        os.execute("dhcpcd wlan0")
    end
    function NetworkMgr:releaseIP()
        os.execute("dhcpcd -k wlan0")
    end
    function NetworkMgr:restoreWifiAsync()
        os.execute("./restore-wifi-async.sh")
    end

    function NetworkMgr:isWifiOn()
        local fd = io.open("/proc/modules", "r")
        if fd then
            local lsmod = fd:read("*all")
            fd:close()
            if lsmod:len() > 0 then
                local module = os.getenv("WIFI_MODULE") or "8188eu"
                if lsmod:find(module) then
                    return true
                end
            end
        end
        return false
    end
end


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
            [353] = "Light",
        },
        event_map_adapter = {
            Light = function(ev)
                if self.input:isEvKeyRelease(ev) then
                    self.powerd:toggleFrontlight()
                end
            end,
        }
    }

    self.input.open("/dev/input/event0") -- Face buttons
    self.input.open("/dev/input/event1") -- Power button
    self.input.open("/dev/input/event2") -- Touch screen
    self.input.open("/dev/input/event3") -- Accelerometer
    self.input.handleTouchEv = self.input.handleBookeenTouchEvent
    self:initEventAdjustHooks()
    -- self.input.open("fake_events")  -- no free slots :(

    local rotation_mode = self.screen.ORIENTATION_PORTRAIT
    self.screen.native_rotation_mode = rotation_mode
    self.screen.cur_rotation_mode = rotation_mode

    Generic.init(self)
end

function Bookeen:supportsScreensaver() return true end

function Bookeen:setDateTime(year, month, day, hour, min, sec)
    if hour == nil or min == nil then return true end
    local command
    if year and month and day then
        command = string.format("date -s '%d-%d-%d %d:%d:%d'", year, month, day, hour, min, sec)
    else
        command = string.format("date -s '%d:%d'",hour, min)
    end

    if os.execute(command) == 0 then
        os.execute('hwclock -u -w')
        return true
    else
        return false
    end
end

function Bookeen:intoScreenSaver()
    local Screensaver = require("ui/screensaver")
    if self.screen_saver_mode == false then
        Screensaver:show()
    end
    self.powerd:beforeSuspend()
    self.screen_saver_mode = true
end

function Bookeen:outofScreenSaver()
    if self.screen_saver_mode == true then
        local Screensaver = require("ui/screensaver")
        Screensaver:close()
    end
    self.powerd:afterResume()
    self.screen_saver_mode = false
end

function Bookeen:suspend()
    local f, re, err_msg, err_code

    f = io.open("/sys/power/state", "w")
    if not f then
        return false
    end
    logger.info("Bookeen going to sleep!")
    re, err_msg, err_code = f:write("mem\n")
    io.close(f)
    logger.info("Bookeen woke up!")
end

function Bookeen:resume()
end

function Bookeen:powerOff()
    os.execute("/bin/busybox poweroff")
end

function Bookeen:reboot()
    os.execute("/bin/busybox reboot")
end

return Bookeen
