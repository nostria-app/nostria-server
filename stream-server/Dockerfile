FROM node:20-bookworm-slim

WORKDIR /app

RUN apt-get update \
	&& apt-get install -y --no-install-recommends python3 make g++ \
	&& rm -rf /var/lib/apt/lists/*

COPY package.json ./
RUN npm install --omit=dev

COPY public ./public
RUN mkdir -p ./public/vendor \
	&& cp ./node_modules/janus-gateway/npm/src/janus.js ./public/vendor/janus.js \
	&& cp ./node_modules/webrtc-adapter/out/adapter.js ./public/vendor/adapter.js
COPY src ./src

EXPOSE 7080

CMD ["node", "src/index.mjs"]