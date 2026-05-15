FROM golang:1.26-alpine AS builder

ARG CACTUS_REPOSITORY=https://github.com/dadrian/cactus.git
ARG CACTUS_REF=682f9622c84108bf2e9c89aaa6788bfeaaa98b81

RUN apk add --no-cache ca-certificates git

WORKDIR /src/cactus
RUN git clone "${CACTUS_REPOSITORY}" . \
    && git checkout "${CACTUS_REF}" \
    && go build -tags mldsa -trimpath -ldflags="-s -w -X main.version=${CACTUS_REF}" -o /out/cactus ./cmd/cactus

FROM alpine:3.22

RUN apk add --no-cache ca-certificates

COPY --from=builder /out/cactus /usr/local/bin/cactus
COPY config.json /etc/cactus/config.json

EXPOSE 14000 14080 14090
VOLUME ["/var/lib/cactus"]

ENTRYPOINT ["/usr/local/bin/cactus"]
CMD ["-config", "/etc/cactus/config.json"]
