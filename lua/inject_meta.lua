local args = ngx.req.get_uri_args()
local icao = args["icao"]
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
    local groundspeed = -1;
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
                -- if i == 1 then
                --     -- get where we are flying from https://nominatim.openstreetmap.org/reverse?latx&lon=y&zoom=5&format=json
                --     -- and then get .address.country, .address.state
                --     res, err = httpc:request_uri("https://nominatim.openstreetmap.org/reverse?lat=" .. aircraft["lat"] .. "&lon=" .. aircraft["lon"] .. "&zoom=5&format=json", {
                --         ssl_verify = false
                --     })
                --     if res and res.status == 200 then
                --         local data = cjson.decode(res.body)
                --         local country = data["address"]["country"] or ""
                --         local state = data["address"]["state"] or ""
                --         -- separator is ", " if both country and state are present, otherwise use ""
                --         local separator = country ~= "" and state ~= "" and ", " or ""
                --         -- check that iether country or state are set
                --         if country ~= "" or state ~= "" then
                --             table.insert(aircraft_descriptions, string.format("✈️🗺️🔎 %s%s%s", country, separator, state))
                --         end
                --     end
                local tentative_gs = aircraft["gs"] or -1
                if tentative_gs > groundspeed then
                    groundspeed = tentative_gs
                end
                ngx.log(ngx.ERR, "groundspeed: ", groundspeed)
                ngx.log(ngx.ERR, "ac lat: ", aircraft["lat"])
                ngx.log(ngx.ERR, "ac lon: ", aircraft["lon"])
                -- tonumber
                aircraft["lat"] = tonumber(aircraft["lat"])
                aircraft["lon"] = tonumber(aircraft["lon"])
                if not min_lat or aircraft["lat"] < min_lat then
                    min_lat = aircraft["lat"]
                end
                if not min_lon or aircraft["lon"] < min_lon then
                    min_lon = aircraft["lon"]
                end
                if not max_lat or aircraft["lat"] > max_lat then
                    max_lat = aircraft["lat"]
                end
                if not max_lon or aircraft["lon"] > max_lon then
                    max_lon = aircraft["lon"]
                end


                local type = aircraft["t"] or ""
                type = aircraft_types[type] and aircraft_types[type][1] or type

                local alt = math.floor(aircraft["alt_baro"] or 0)
                local speed = math.floor(aircraft["gs"] or 0)
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
    if groundspeed > 0 then
        image_url = image_url .. "gs=" .. groundspeed .. "&"
    end
    if min_lat and min_lon and max_lat and max_lon then
        image_url = image_url .. "min_lat=" .. min_lat .. "&min_lon=" .. min_lon .. "&max_lat=" .. max_lat .. "&max_lon=" .. max_lon .. "&"
    end
    ngx.log(ngx.ERR, "lat/lons: ", min_lat, min_lon, max_lat, max_lon)
    open_graph_tags:set(cache_key .. ":image", image_url)
    open_graph_tags:set(cache_key .. ":description", description)
else
    ngx.log(ngx.ERR, "No icao parameter in URL")
end
