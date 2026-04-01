FROM node:20-bookworm-slim

WORKDIR /app

RUN apt-get update \
	&& apt-get install -y --no-install-recommends python3 make g++ \
	&& rm -rf /var/lib/apt/lists/*

COPY package.json ./
RUN npm install --omit=dev

COPY public ./public
COPY src ./src

EXPOSE 7080

CMD ["node", "src/index.mjs"]