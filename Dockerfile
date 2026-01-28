# ─── BASE STAGE (cached Rust + Go toolchain) ─────────────────────────────────────
# Build from parent directory: docker build -f bor/Dockerfile -t bor .
FROM mirror.gcr.io/library/golang:1.25-alpine AS base

RUN apk add --no-cache build-base git linux-headers curl

# Install Rust toolchain (cached in this layer)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# ─── BUILDER STAGE ───────────────────────────────────────────────────────────────
FROM base AS builder

ARG BOR_DIR=/var/lib/bor/
ENV BOR_DIR=$BOR_DIR

WORKDIR /var/lib

# Copy full source (triedb-ffi expects triedb at ../../../triedb)
COPY triedb/ ./triedb/
COPY bor/ ./bor/

WORKDIR ${BOR_DIR}

# Build with cached deps (mount caches persist across builds)
RUN --mount=type=ssh \
    --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    --mount=type=cache,target=/root/.cargo/registry \
    --mount=type=cache,target=/root/.cargo/git \
    --mount=type=cache,target=/var/lib/bor/triedb-go/target \
    git submodule update --init --recursive && \
    go mod download && \
    make bor

# ─── RUNTIME STAGE ────────────────────────────────────────────────────────────────
FROM mirror.gcr.io/library/alpine:3.21

ARG BOR_DIR=/var/lib/bor/
ENV BOR_DIR=$BOR_DIR

RUN apk add --no-cache bash ca-certificates libgcc && \
    mkdir -p ${BOR_DIR}

WORKDIR ${BOR_DIR}

COPY --from=builder ${BOR_DIR}/build/bin/bor /usr/bin/

EXPOSE 8545 8546 8547 30303 30303/udp

ENTRYPOINT ["bor"]
