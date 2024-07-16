local args = ngx.req.get_uri_args()
-- if icao is not defined, nothing to do. exit.
if not args["icao"] then
    return
end
-- get icao arg, but escape it.
local icao = ngx.escape_uri(args["icao"])

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

if icao then
    local http = require "resty.http"
    local httpc = http.new()
    httpc:set_timeout(100)

    local res, err = httpc:request_uri("http://reapi-readsb.adsblol.svc.cluster.local:30152/?find_hex=" .. icao, {
        ssl_verify = false
    })

    if err then
        ngx.log(ngx.ERR, "API request failed: ", err)
        res, err = httpc:request_uri("https://re-api.adsb.lol/?find_hex=" .. icao, {
            ssl_verify = false
        })
    end

    local description = "Check out this aircraft."
    local max_groundspeed = -1;
    local min_lat, min_lon, max_lat, max_lon = false, false, false, false
    if res and res.status == 200 then
        local cjson = require "cjson"
        local data = cjson.decode(res.body)
        local n_aircraft = #data["aircraft"]
        if data["aircraft"] and n_aircraft > 0 then
            local aircraft_descriptions = {}
            for i, aircraft in ipairs(data["aircraft"]) do
                local callsign = aircraft["flight"] or ""
                callsign = callsign:gsub("%s+", "")
                local reg = aircraft["r"] or ""
                local reg_country = find_country_by_hex(aircraft["hex"] or "")
                reg = reg_country .. reg

                aircraft["lat"] = tonumber(aircraft["lat"]) or false
                aircraft["lon"] = tonumber(aircraft["lon"]) or false

                local tentative_gs = tonumber(aircraft["gs"]) or -1
                if tentative_gs > max_groundspeed then
                    max_groundspeed = tentative_gs
                end

                if aircraft["lat"] and aircraft["lon"] then
                    if not min_lat or not min_lon or not max_lat or not max_lon then
                        ngx.log(ngx.ERR, "first valid aircraft")
                        min_lat = aircraft["lat"]
                        min_lon = aircraft["lon"]
                        max_lat = aircraft["lat"]
                        max_lon = aircraft["lon"]
                    else
                        ngx.log(ngx.ERR, "not first aircraft")
                        min_lat = math.min(min_lat, aircraft["lat"])
                        min_lon = math.min(min_lon, aircraft["lon"])
                        max_lat = math.max(max_lat, aircraft["lat"])
                        max_lon = math.max(max_lon, aircraft["lon"])
                    end
                else
                    ngx.log(ngx.ERR, "invalid lat/lon for aircraft ", aircraft["hex"])
                end

                ngx.log(ngx.ERR, "groundspeed: ", groundspeed)
                ngx.log(ngx.ERR, "ac lat: ", aircraft["lat"])
                ngx.log(ngx.ERR, "ac lon: ", aircraft["lon"])


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

    local open_graph_tags = ngx.shared.open_graph_tags
    local cache_key = icao

    local image_url = "https://api-dev.adsb.lol/0/screenshot/" .. icao .. "?"
    if max_groundspeed > 0 then
        image_url = image_url .. "gs=" .. max_groundspeed .. "&"
    end
    if min_lat and min_lon and max_lat and max_lon then
        image_url = image_url .. "min_lat=" .. min_lat .. "&min_lon=" .. min_lon .. "&max_lat=" .. max_lat .. "&max_lon=" .. max_lon .. "&"
    end
    ngx.log(ngx.ERR, "lat/lons: ", min_lat, min_lon, max_lat, max_lon)
    -- remove image_url trailing & if found
    open_graph_tags:set(cache_key .. ":image", image_url:gsub("&$", ""))
    open_graph_tags:set(cache_key .. ":description", description)
else
    ngx.log(ngx.ERR, "No icao parameter in URL")
end
