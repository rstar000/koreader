local BasePowerD = require("device/generic/powerd")

-- TODO older firmware doesn't have the -0 on the end of the file path
-- local base_path = '/sys/class/power_supply/bq27441-0/'

local Bookeen_PowerD = BasePowerD:new{
    is_charging = nil,
    capacity_file = nil,
    status_file = nil
}

function Bookeen_PowerD:init()
end

function Bookeen_PowerD:frontlightIntensityHW()
    return 0
end

function Bookeen_PowerD:setIntensityHW(intensity)
end

function Bookeen_PowerD:getCapacityHW()
    -- return self:read_int_file(self.capacity_file)
    return 0
end

function Bookeen_PowerD:isChargingHW()
    return false
    -- return self:read_str_file(self.status_file) == "Charging\n"
end

return Bookeen_PowerD

