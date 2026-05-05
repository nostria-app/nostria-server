ARG LLAMA_CPP_IMAGE=ghcr.io/ggml-org/llama.cpp:server
FROM ${LLAMA_CPP_IMAGE}

COPY config/start-llama-server.sh /usr/local/bin/nostria-start-llama-server
RUN chmod +x /usr/local/bin/nostria-start-llama-server

ENTRYPOINT ["/usr/local/bin/nostria-start-llama-server"]
