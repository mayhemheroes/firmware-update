# Build Stage
FROM --platform=linux/amd64 ubuntu:22.04 AS builder

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y curl build-essential
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain nightly
ENV PATH="/root/.cargo/bin:${PATH}"
RUN cargo install -f cargo-fuzz

## Add source code to the build stage.
ADD . /src
WORKDIR /src
RUN rm -f rust-toolchain.toml Cargo.lock

RUN echo building instrumented harnesses && \
    bash -c "pushd fuzz && cargo fuzz build && popd" && \
    mv fuzz/target/x86_64-unknown-linux-gnu/release/png /png && \
    echo done

RUN echo building non-instrumented harnesses && \
    export RUSTFLAGS="--cfg fuzzing -Clink-dead-code -Cdebug-assertions -C codegen-units=1" && \
    bash -c "pushd fuzz && cargo build --release && popd" && \
    mv fuzz/target/release/png /png_no_inst && \
    echo done

# Package Stage
FROM ubuntu:22.04

COPY --from=builder /png /png_no_inst /
