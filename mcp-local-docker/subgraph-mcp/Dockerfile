# Simplified build from upstream subgraph-mcp repo
ARG RUST_VERSION=1.86
ARG CHEF_IMAGE=lukemathwalker/cargo-chef:latest-rust-${RUST_VERSION}-slim-bookworm

# Stage 1: Prepare recipe
FROM ${CHEF_IMAGE} AS chef
WORKDIR /app
RUN apt-get update && apt-get install -y git pkg-config libssl-dev ca-certificates && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 https://github.com/graphops/subgraph-mcp.git .
RUN cargo chef prepare --recipe-path recipe.json

# Stage 2: Build dependencies + binary
FROM ${CHEF_IMAGE} AS builder
WORKDIR /app
RUN apt-get update && apt-get install -y pkg-config libssl-dev binutils ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=chef /app/recipe.json recipe.json
RUN cargo chef cook --release --recipe-path recipe.json
COPY --from=chef /app /app
RUN cargo build --release && strip target/release/subgraph-mcp

# Stage 3: Runtime
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /app/target/release/subgraph-mcp /usr/local/bin/subgraph-mcp

ENV GATEWAY_API_KEY=""
ENV RUST_LOG=info

EXPOSE 8000

CMD ["subgraph-mcp"]
