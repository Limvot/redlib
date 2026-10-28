# Use the official cargo-zigbuild image which natively cross-compiles all targets from any host
FROM --platform=$BUILDPLATFORM ghcr.io/rust-cross/cargo-zigbuild:latest AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    make \
    cmake \
    g++ \
    perl \
    && rm -rf /var/lib/apt/lists/*

RUN rustup component add rust-src

WORKDIR /redlib

# 1. Copy only dependency manifest files first for caching
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs

# Injected automatically by Docker Buildx for each platform in your workflow
ARG TARGETPLATFORM

# 2. Build dependencies with explicit target resolution
RUN --mount=type=cache,target=/usr/local/cargo/registry,id=reg-${TARGETPLATFORM} \
    --mount=type=cache,target=/redlib/target,id=target-${TARGETPLATFORM} \
    case "${TARGETPLATFORM}" in \
        "linux/amd64")    export T="x86_64-unknown-linux-musl" ;; \
        "linux/arm64")    export T="aarch64-unknown-linux-musl" ;; \
        "linux/arm/v7")   export T="armv7-unknown-linux-musleabihf" ;; \
        "linux/riscv64")  export T="riscv64gc-unknown-linux-musl" ;; \
        *) echo "Unsupported platform: ${TARGETPLATFORM}"; exit 1 ;; \
    esac && \
    echo "Building for target: $T" && \
    rustup target add "$T" && \
    cargo zigbuild --release --target "$T" --bin redlib || true

# 3. Copy actual source code and build the final binary
COPY . .
RUN --mount=type=cache,target=/usr/local/cargo/registry,id=reg-${TARGETPLATFORM} \
    --mount=type=cache,target=/redlib/target,id=target-${TARGETPLATFORM} \
    case "${TARGETPLATFORM}" in \
        "linux/amd64")    export T="x86_64-unknown-linux-musl" ;; \
        "linux/arm64")    export T="aarch64-unknown-linux-musl" ;; \
        "linux/arm/v7")   export T="armv7-unknown-linux-musleabihf" ;; \
        "linux/riscv64")  export T="riscv64gc-unknown-linux-musl " ;; \
    esac && \
    cargo zigbuild --release --target "$T" --bin redlib && \
    cp target/"$T"/release/redlib /usr/local/bin/redlib

########################
## Release Image
########################
FROM alpine AS release
RUN apk add --no-cache ca-certificates
COPY --from=builder /usr/local/bin/redlib /usr/local/bin/redlib

# Security: Non-root user
RUN adduser --home /nonexistent --no-create-home --disabled-password redlib
USER redlib

EXPOSE 8080
HEALTHCHECK --interval=1m --timeout=3s CMD wget --spider -q http://localhost:8080/settings || exit 1

LABEL org.opencontainers.image.title="Redlib" \
      org.opencontainers.image.description="Private front-end for Reddit written in Rust" \
      org.opencontainers.image.url="https://github.com/evrial/redlib" \
      org.opencontainers.image.source="https://github.com/evrial/redlib" \
      org.opencontainers.image.licenses="AGPL-3.0"

CMD ["/usr/local/bin/redlib"]
