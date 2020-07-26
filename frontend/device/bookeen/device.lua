local Generic = require("device/generic/device") -- <= look at this file!
local Event = require("ui/event")
local WakeupMgr = require("device/wakeupmgr")
local TimeVal = require("ui/timeval")
local logger = require("logger")

local function yes() return true end
local function no() return false end

--[[
Bookeen Devices Serial structure : AABBCDDEGYMDSSSSFL

+---------------------------------------------------+
| AA    | Reseller                                  |
| BB    | Screen Type                               |
| C     | Device Generation                         |
| DD    | Device Color                              |
| E     | Hardware Revision                         |
| G     | Option fitted on the hardware             |
| Y     | Year of manufacture                       |
| M     | Month of manufacture                      |
| D     | Day of manufacture                        |
| SSSS  | Build Number of this day of manufacture   |
| F     | Factory                                   |
| L     | Factory's Line                            |
----------------------------------------------------|

Known models:
    Cybook Orizon                   (CYBOR10-BK):   BK60BK021   2011
    Cybook Orizon                   (CYBOR10-BK):   BK60BK02K   2011
    Cybook Odyssey                  (CYBOY10-ADL):  AL60?????   2011
    Cybook Odyssey HD Frontlight    (CYBOY3F-BK):   BK615BK3F   2012    OMAP 3611
    Cybook Odyssey Frontlight       (CYBOY4F-BK):   ?           2013    OMAP 3611
    Nolim                           (CYBOY4F-CF):   ?           2013    OMAP 3611
    Nolimbook+                      (CYBOY4S-CF):   CF605WE4F   2013    Allwinner A13
    Saraiva Lev                     (CYBOY4S-SA):   ?           2014    Allwinner A13
    Saraiva Lev com luz             (CYBOY4F-SA):   ?           2014    Allwinner A13
    Cybook Odyssey Essential        (CYBOY5S-BK):   ?           2014
    Cybook Odyssey Frontlight 2     (CYBOY5F-BK):   ?           2014
    Cybook Muse                     (CYBME1S-BK):   ?           2014
    Cybook Muse Essential           (CYBFT1S-BK):   ?           2014
    Cybook Muse Frontlight          (CYBFT1F-BK):   BK646BK1F   2014    Allwinner A13
    Cybook Ocean                    (CYBON1F-BK):   BK816BK1F   2014    OMAP 3611
    Cybook Ocean                    (CYBON1F-BK):   BK826BK1F   2014    OMAP 3611
    Cybook Muse Light               (CYBME1F-BK):   BK666BK1F
    Cybook Muse Frontlight 2        (CYBME2F-BK):   BK676BK2F
    Cybook Muse HD                  (CYBFT6F-BK):   BK656GY6F   2016
    Nolimbook HD                    (CYBFT1S-CF):   ?           2014
    Nolimbook HD+                   (CYBFT1F-CF):   ?           2014
    Letto Frontlight                (CYBFT1F-AL):   ?           2014
    Nolim XL (Cybook Ocean)         (?):            CF816WE1F
    Saga                            (CYBSB2F-BK):   BK677BK2F   2017
    Diva                            (CYBD1F-BK):    BK658WE1G   2019
    Diva HD                         (CYBD6F-BK):    ?

Screen Type seems to be XY where
- X is Screen Size (6" or 8")
- Y is still unknown

Sources:
* https://blog.soutade.fr/post/2015/03/game_over.html#comment_291
* https://github.com/yoannsculo/blog/blob/master/devices/index.html.markdown2#L12
--]]

local BOOKEEN_RESELLER_ADLIBRIS     = "AL"
local BOOKEEN_RESELLER_BOOKEEN      = "BK"
local BOOKEEN_RESELLER_CARREFOUR    = "CF"
local BOOKEEN_RESELLER_VIRGIN       = "VG"

local BOOKEEN_GENERATION_GEN3_OPUS  = 0x3
local BOOKEEN_GENERATION_ORIZON     = 0x4
local BOOKEEN_GENERATION_ODYSSEY    = 0x5
local BOOKEEN_GENERATION_MUSE_OCEAN = 0x6
local BOOKEEN_GENERATION_SAGA       = 0x7
local BOOKEEN_GENERATION_DIVA       = 0x8

local BOOKEEN_DEVICE_COLOR_BLACK    = "BK"
local BOOKEEN_DEVICE_COLOR_BORDEAUX = "BX"
local BOOKEEN_DEVICE_COLOR_GREEN    = "GN"
local BOOKEEN_DEVICE_COLOR_GREY     = "GY"
local BOOKEEN_DEVICE_COLOR_YELLOW   = "YW"
local BOOKEEN_DEVICE_COLOR_WHITE    = "WE"

local function getSerial()
    local std_out = io.popen("nvram -s|cut -d= -f2")
    local serial = nil
    if std_out ~= nil then
        serial = std_out:read()
        std_out:close()
    end
    return serial
end

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
    serial = getSerial(),
    just_toggled_frontlight = 0
}

function Bookeen:getReseller()
    return self.serial:sub(1, 2)
end

function Bookeen:getScreenType()
    return tonumber(self.serial:sub(3, 4), 16)
end

function Bookeen:getDeviceGeneration()
    return tonumber(self.serial:sub(5, 5), 16)
end

function Bookeen:getDeviceColor()
    return self.serial:sub(6, 7)
end

function Bookeen:getHardwareRevision()
    return tonumber(self.serial:sub(8, 8), 16)
end

function Bookeen:getHardwareOptions()
    return tonumber(self.serial:sub(9, 9), 16)
end

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
    local device_serial = getSerial()
    local device_generation = tonumber(device_serial:sub(5, 5), 16)

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
        local obtain_ip_cmd = "dhcpcd wlan0"
        if device_generation == BOOKEEN_GENERATION_MUSE_OCEAN then
            obtain_ip_cmd = "udhcpc -i wlan0 -R"
        end
        os.execute(obtain_ip_cmd)
    end
    function NetworkMgr:releaseIP()
        local release_ip_cmd = "dhcpcd -k wlan0"
        if device_generation == BOOKEEN_GENERATION_MUSE_OCEAN then
            release_ip_cmd = "killall udhcpc"
        end
        os.execute(release_ip_cmd)
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

    if self:getDeviceGeneration() == BOOKEEN_GENERATION_MUSE_OCEAN then
        -- On the Cybook Muse Frontlight and Ocean
        -- pressing the Home button 1 second toggle the frontlight
        self.input.event_map_adapter.Home = function(ev)
            if self.input:isEvKeyRepeat(ev) then
                self.just_toggled_frontlight = 1
                self.powerd:toggleFrontlight()
                if self.powerd:isFrontlightOn() and self.powerd:frontlightIntensity() == 0 then
                    self.powerd:setIntensity(1)
                end
            elseif self.input:isEvKeyRelease(ev) then
                if self.just_toggled_frontlight == 1 then
                   self.just_toggled_frontlight = 0
                else
                   return Event:new("Home")
                end
            end
        end
    end

    self.input.open("/dev/input/event0") -- Face buttons
    self.input.open("/dev/input/event1") -- Power button
    self.input.open("/dev/input/event2") -- Touch screen

    if self:getDeviceGeneration() ~= BOOKEEN_GENERATION_MUSE_OCEAN then
        self.input.open("/dev/input/event3") -- Accelerometer
    end

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
