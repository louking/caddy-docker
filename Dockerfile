FROM caddy:builder-alpine AS builder

# see https://caddyserver.com/docs/modules/http.ip_sources.cloudflare
RUN xcaddy build \
    --with github.com/caddyserver/transform-encoder \
    --with github.com/caddy-dns/cloudflare \
    --with github.com/WeidiDeng/caddy-cloudflare-ip

FROM caddy:alpine

# Update package index and install only necessary packages
RUN apk update && apk add --no-cache nss-tools su-exec

# Define a build argument with a default (e.g., 1000)
ARG CADDY_UID=1000
ARG CADDY_GID=1000

USER root

# Delete existing caddy user/group if they exist, then recreate with the specific IDs
RUN deluser caddy || true && \
    delgroup caddy || true && \
    addgroup -g ${CADDY_GID} caddy && \
    adduser -u ${CADDY_UID} -G caddy -g caddy -s /bin/sh -D caddy

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
COPY ./entrypoint.sh ./

ENTRYPOINT ["./entrypoint.sh"]

# adapted from https://hub.docker.com/layers/library/caddy/latest/images/sha256-d8c17a862962def15cde69863a3a463f25a2664942eafd7bdbf050e9c3116b83
CMD ["caddy", "run", "--config", "/etc/caddy/Caddyfile", "--adapter", "caddyfile"]
