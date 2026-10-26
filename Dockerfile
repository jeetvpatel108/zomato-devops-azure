# Stage 1: build the React app (build tools live ONLY in this stage)
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

# Stage 2: ship only the finished static files, served by nginx as a non-root user
FROM nginxinc/nginx-unprivileged:stable-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/build /usr/share/nginx/html
EXPOSE 3000
# The base image already starts nginx in the foreground; no CMD needed.