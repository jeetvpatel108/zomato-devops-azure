FROM node:20-slim AS builder
WORKDIR /app
COPY package*.json ./
RUN npm config set fetch-retries 5 \
 && npm config set fetch-retry-mintimeout 60000 \
 && npm config set fetch-retry-maxtimeout 600000 \
 && npm config set fetch-timeout 600000 \
 && npm install --no-audit --no-fund --loglevel=error
COPY . .
RUN npm run build

# Stage 2: Production
FROM builder AS final
WORKDIR /app
COPY --from=builder /app/build ./build
COPY package*.json ./
RUN npm install --production --no-audit --no-fund --loglevel=error
EXPOSE 3000
CMD ["npm", "start"]