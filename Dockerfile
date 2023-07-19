FROM ubuntu:20.04 as builder

ARG GO_VERSION="1.20.5"
ADD https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz /go.tar.gz

# Basic dependencies.
ENV HOME="/node" DEBIAN_FRONTEND="noninteractive" GOPATH="/dist"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    apt-utils \
    bsdmainutils \
    curl \
    git \
    && update-ca-certificates && \
    && rm -rf /var/lib/apt/lists/* && \
    \
    tar -C /usr/local -xzf /go.tar.gz && \
    rm -rf /go.tar.gz

ENV PATH="/usr/local/go/bin:${PATH}"

COPY ./docker/files/ /dist/files
COPY ./installer/genesis /dist/files/run/genesis
COPY ./cmd/updater/update.sh /dist/files/build/update.sh
COPY ./installer/config.json.example /dist/files/run/config.json.example

# Install algod binaries.
RUN /dist/files/build/install.sh \
    -p "${GOPATH}/bin" \
    -d "/algod/data" \ 
    -c "stable" \
    -u "https://github.com/algorand/go-algorand.git" \
    -s "2ee0385060033f1d89db3096d5939adf7e7f85cb9b611d003418968018f01690"

FROM debian:bookworm-20230703-slim as final

ENV PATH="/node/bin:${PATH}" ALGOD_PORT="8080" KMD_PORT="7833" ALGORAND_DATA="/algod/data"

# curl is needed to lookup the fast catchup url
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl supervisor grep && \
    update-ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p "$ALGORAND_DATA" && \
    chown -R root:root /algod

USER root
COPY --chown=algorand:algorand --from=builder "/dist/bin/" "/node/bin/"
COPY --chown=algorand:algorand --from=builder "/dist/files/run/" "/node/run/"
COPY healthcheck /usr/local/bin
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

RUN chmod 755 /usr/local/bin/healthcheck
RUN mkdir -p /var/log/supervisor

# Expose Algod REST API, KMD REST API, Algod Gossip, and Prometheus Metrics ports
EXPOSE $ALGOD_PORT $KMD_PORT 4160 9100 1337

WORKDIR /algod

ENTRYPOINT ["/usr/bin/supervisord"]
