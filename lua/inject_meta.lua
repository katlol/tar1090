local args = ngx.req.get_uri_args()
-- if icao is not defined, nothing to do. exit.
if not args["icao"] then
    return
end
local unsafe_icao = args["icao"]

local aircraft_types = require "aircraft_types"
local icao_ranges = require "icao_ranges"

local function get_country(lat, lon)
    return ""
end

function find_country_by_hex(hex)
    local hex_number = tonumber(hex, 16)
    if not hex_number then
        return "?"
    end

    for _, range in ipairs(icao_ranges) do
        if hex_number >= range.start and hex_number <= range.stop then
            return range.country
        end
    end
    return "??"
end

if unsafe_icao then
    ngx.log(ngx.ERR, "icao: ", unsafe_icao)
    local http = require "resty.http"
    local httpc = http.new()
    httpc:set_timeout(100)
        local res, err = httpc:request_uri("http://reapi-readsb.adsblol.svc.cluster.local:30152/?find_hex=" .. unsafe_icao, {
        ssl_verify = false
    })

    if err then
        ngx.log(ngx.ERR, "API request failed: ", err)
        res, err = httpc:request_uri("https://re-api.adsb.lol/?find_hex=" .. unsafe_icao, {
            ssl_verify = false
        })
    end

    local description = "Check out this aircraft."
    local max_groundspeed = -1;
    local min_lat, min_lon, max_lat, max_lon = false, false, false, false
    local safe_icao = ""
    ngx.log(ngx.ERR, "res: " .. res.body)
    if res and res.status == 200 then
        local cjson = require "cjson"
        local data = cjson.decode(res.body)
        local n_aircraft = #data["aircraft"]
        if data["aircraft"] and n_aircraft > 0 then
            ngx.log(ngx.ERR, "safe_icao: ", safe_icao)
            local aircraft_descriptions = {}
            for i, aircraft in ipairs(data["aircraft"]) do
                safe_icao = safe_icao .. aircraft["hex"] .. ","
                local callsign = aircraft["flight"] or ""
                callsign = callsign:gsub("%s+", "")
                local reg = aircraft["r"] or ""
                local reg_country = find_country_by_hex(aircraft["hex"] or "")
                reg = reg_country .. reg

                local type = aircraft["t"] or ""
                type = aircraft_types[type] and aircraft_types[type][1] or type

                --local alt = aircraft["alt_baro"] or 0
                -- alt might be '' when empty
                local alt = tonumber(aircraft["alt_baro"]) or 0
                local speed = tonumber(aircraft["gs"]) or 0
                local lat = tonumber(aircraft["lat"])
                local lon = tonumber(aircraft["lon"])
                local country = get_country(lat, lon)

                local squawk = aircraft["squawk"] or ""
                local emergency_squawks = {["7500"] = true, ["7600"] = true, ["7700"] = true, ["7777"] = true}
                print("squawk", squawk)
                -- If it is an emergency squawk, show it; otherwise, do not show it
                if emergency_squawks[squawk] then
                    squawk =  "EMERGENCY!" .. squawk
                else
                    squawk = ""
                end


                local bit = require "bit"
                local dbflags_str = {}
                local dbflags = aircraft["dbFlags"] or 0
                if bit.band(dbflags, 1) ~= 0 then table.insert(dbflags_str, "mil") end
                if bit.band(dbflags, 2) ~= 0 then table.insert(dbflags_str, "!") end
                if bit.band(dbflags, 4) ~= 0 then table.insert(dbflags_str, "PIA") end
                if bit.band(dbflags, 8) ~= 0 then table.insert(dbflags_str, "LADD") end
                dbflags_str = table.concat(dbflags_str, ", ")
                local altspeed_str = ""
                if n_aircraft < 2 then
                    altspeed_str = string.format(", %s ft, %s mph", alt, speed)
                end
                local desc = string.format("%s %s %s %s, %s %s %s", callsign, squawk, reg, country, dbflags_str, type, altspeed_str)
                desc = desc:gsub("%s+", " "):gsub(" ,", ",")
                table.insert(aircraft_descriptions, desc)
            end

            if #aircraft_descriptions > 0 then
                description = table.concat(aircraft_descriptions, " &#10;&#13; ")
            end
        end
    else
        ngx.log(ngx.ERR, "API request failed: ", err)
    end
    if not safe_icao then
        ngx.log(ngx.ERR, "No safe_icao found")
        return
    end
    -- otherwise, remove , from the end of safe_icao
    safe_icao = safe_icao:gsub(",$", "")

    local open_graph_tags = ngx.shared.open_graph_tags
    local cache_key = safe_icao


    -- remove image_url trailing & if found
    open_graph_tags:set(cache_key .. ":image",  "https://api-dev.adsb.lol/0/screenshot/" .. safe_icao)
    open_graph_tags:set(cache_key .. ":description", description)
else
    ngx.log(ngx.ERR, "No icao parameter in URL")
end
