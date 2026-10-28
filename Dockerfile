FROM --platform=$BUILDPLATFORM ghcr.io/rust-cross/cargo-zigbuild:latest AS builder

RUN rustup default stable
RUN apt-get update && apt-get install -y --no-install-recommends \
    git make cmake g++ perl file && rm -rf /var/lib/apt/lists/*

RUN rustup component add rust-src

WORKDIR /redlib

# Accept the target directly from GitHub Actions build-args
ARG RUST_TARGET
RUN echo "Building for target: ${RUST_TARGET}" && rustup target add "${RUST_TARGET}"

# Copy dependency files and cache
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs

RUN --mount=type=cache,target=/usr/local/cargo/registry,id=reg-${RUST_TARGET} \
    --mount=type=cache,target=/redlib/target,id=target-${RUST_TARGET} \
    cargo zigbuild --release --target "${RUST_TARGET}" --bin redlib || true

# Copy source and build final binary
COPY . .
RUN --mount=type=cache,target=/usr/local/cargo/registry,id=reg-${RUST_TARGET} \
    --mount=type=cache,target=/redlib/target,id=target-${RUST_TARGET} \
    cargo zigbuild --release --target "${RUST_TARGET}" --bin redlib && \
    cp target/"${RUST_TARGET}"/release/redlib /usr/local/bin/redlib

RUN file /usr/local/bin/redlib

########################
## Release Image
########################
FROM alpine AS release
RUN apk add --no-cache ca-certificates
COPY --from=builder /usr/local/bin/redlib /usr/local/bin/redlib

RUN adduser --home /nonexistent --no-create-home --disabled-password redlib
USER redlib

EXPOSE 8080
HEALTHCHECK --interval=1m --timeout=3s CMD wget --spider -q http://localhost:8080/settings || exit 1

CMD ["/usr/local/bin/redlib"]
