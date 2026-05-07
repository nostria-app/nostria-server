ARG UBUNTU_VERSION=24.04

FROM ubuntu:${UBUNTU_VERSION} AS build

ARG SDCPP_REF=master

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential ca-certificates cmake git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --recursive --depth 1 --branch "${SDCPP_REF}" https://github.com/leejet/stable-diffusion.cpp.git .

RUN cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
    && cmake --build build --config Release --parallel

FROM ubuntu:${UBUNTU_VERSION} AS runtime

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates libgomp1 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /src/build/bin/sd-cli /sd-cli
COPY --from=build /src/build/bin/sd-server /sd-server

ENTRYPOINT ["/sd-cli"]