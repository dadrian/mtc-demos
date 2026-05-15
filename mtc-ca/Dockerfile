FROM golang:1.26-alpine AS builder

ARG CACTUS_REPOSITORY=https://github.com/mcpherrinm/cactus.git
ARG CACTUS_REF=c7bcec61c45b3dd20964e2839eb9542ee8e7a5cf

RUN apk add --no-cache ca-certificates git

WORKDIR /src/cactus
RUN git clone "${CACTUS_REPOSITORY}" . \
    && git checkout "${CACTUS_REF}" \
    && go build -tags mldsa -trimpath -ldflags="-s -w -X main.version=${CACTUS_REF}" -o /out/cactus ./cmd/cactus

FROM alpine:3.22

RUN apk add --no-cache ca-certificates

COPY --from=builder /out/cactus /usr/local/bin/cactus
COPY config.json /etc/cactus/config.json
COPY keys/ca-cosigner.seed.b64 /cactus-demo/keys/ca-cosigner.seed.b64
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh

EXPOSE 14000 14080 14090
VOLUME ["/var/lib/cactus"]

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
