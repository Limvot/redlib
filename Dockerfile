# Use the official cargo-zigbuild image which natively cross-compiles all targets from any host
FROM --platform=$BUILDPLATFORM ghcr.io/rust-cross/cargo-zigbuild:latest AS builder

# Install cmake and build tools required for C/C++ dependencies like BoringSSL (btls-sys)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    make \
    cmake \
    g++ \
    perl \
    && rm -rf /var/lib/apt/lists/*

RUN rustup component add rust-src

WORKDIR /redlib
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs

# Fetch/build dependencies for the target
RUN --mount=type=cache,target=/usr/local/cargo/registry,id=reg-${TARGETPLATFORM} \
    --mount=type=cache,target=/redlib/target,id=target-${TARGETPLATFORM} \
    case "${TARGETPLATFORM}" in \
        "linux/amd64")    T="x86_64-unknown-linux-musl" ;; \
        "linux/arm64")    T="aarch64-unknown-linux-musl" ;; \
        "linux/arm/v7")   T="armv7-unknown-linux-musleabihf" ;; \
        "linux/riscv64")  T="riscv64gc-unknown-linux-musl" ;; \
    esac && \
    rustup target add "$T" && \
    cargo zigbuild --release --target "$T" --bin redlib || true

# Now copy the real source code and build your binary
COPY . .
RUN --mount=type=cache,target=/usr/local/cargo/registry,id=reg-${TARGETPLATFORM} \
    --mount=type=cache,target=/redlib/target,id=target-${TARGETPLATFORM} \
    cargo zigbuild --release --target "$T" --bin redlib && \
    cp target/"$T"/release/redlib /usr/local/bin/redlib

########################
## Release Image
########################
FROM alpine:latest AS release
RUN apk add --no-cache ca-certificates
COPY --from=builder /usr/local/bin/redlib /usr/local/bin/redlib

# Security: Non-root user
RUN adduser --home /nonexistent --no-create-home --disabled-password redlib
USER redlib

EXPOSE 8080
HEALTHCHECK --interval=1m --timeout=3s CMD wget --spider -q http://localhost:8080/settings || exit 1

CMD ["/usr/local/bin/redlib"]
