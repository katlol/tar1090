FROM openresty/openresty:alpine
WORKDIR /opt/tar1090
COPY html .
COPY install_cachebust.sh /tmp
COPY nginx.conf /etc/nginx/tar1090.conf

RUN set -ex && \
    apk add --virtual=.build-deps git sed bash perl curl && \
    apk add --virtual=.run-deps ca-certificates && \
    # Make a single certs pem file
    mkdir -p /etc/ssl/certs/ && \
    cat /usr/share/ca-certificates/mozilla/* > /etc/ssl/certs/ca-certificates.pem && \
    bash /tmp/install_cachebust.sh && \
    mkdir -p /opt/tar1090-db && \
    opm get ledgetech/lua-resty-http && \
    wget -qO- https://github.com/katlol/tar1090-db/releases/latest/download/db.tar | tar -C /opt/tar1090-db -xvf - && \
    ln -s /opt/tar1090-db/db /opt/tar1090/db2 && \
    sed -i'' "s/INSTANCE\///" /etc/nginx/tar1090.conf && \
    sed -i'' "s/\/INSTANCE/\//" /etc/nginx/tar1090.conf && \
    sed -i'' 's/\/SERVICE/\/readsb/' /etc/nginx/tar1090.conf && \
    sed -i'' 's/SOURCE_DIR\//\/run\/readsb\//' /etc/nginx/tar1090.conf && \
    sed -i'' 's/HTMLPATH\//\/opt\/tar1090\//' /etc/nginx/tar1090.conf && \
    echo "server {listen 80;listen [::]:80;server_name _;include /etc/nginx/tar1090.conf;}" > /etc/nginx/conf.d/default.conf && \
    # Add resolvers, 1.1.1.1 and 10.96.0.10
    # goes in http{}
    sed -i'' 's/http {/http {\n    resolver 10.96.0.10 1.1.1.1;lua_shared_dict open_graph_tags 10M;\n/' /usr/local/openresty/nginx/conf/nginx.conf && \
    nginx -t && \
    apk del .build-deps
COPY lua/*lua /etc/nginx/lua/
COPY lua/aircraft_types.lua /usr/local/openresty/site/lualib/
COPY lua/icao_ranges.lua /usr/local/openresty/site/lualib/
