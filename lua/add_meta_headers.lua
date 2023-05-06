local args = ngx.req.get_uri_args()
local icao = args["icao"]

if icao then
    local open_graph_tags = ngx.shared.open_graph_tags
    -- If empty, return
    if not open_graph_tags then
        return
    end
    local cache_key = icao
    local og_image = open_graph_tags:get(cache_key .. ":image")
    local og_description = open_graph_tags:get(cache_key .. ":description")

    if og_image and og_description then
        local chunk = '<meta name="twitter:card" content="summary_large_image" /><meta property="og:image" content="' .. og_image .. '">'
        local chunk2 = '<meta property="og:description" content="' .. og_description .. '">'
        -- prepend to </head>
        ngx.arg[1] = ngx.arg[1]:gsub("</head>", chunk .. chunk2 .. "</head>")
    end
end
