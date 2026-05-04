# ChikwexDockerApp Frontend Dockerfile
# Multi-stage build for optimized production image

# ============================================
# Stage 1: Build - Compile React application
# ============================================
FROM node:20-alpine as build

WORKDIR /app

# Copy package files first (better layer caching)
COPY package*.json ./

# Install dependencies (including devDependencies for build)
RUN npm install

# Copy source code
COPY . .

# Build the production app
RUN npm run build

# ============================================
# Stage 2: Production - Serve with Nginx
# ============================================
FROM nginx:alpine as production

# Create non-root user
RUN addgroup -g 1001 -S chikwex && \
    adduser -S -D -H -u 1001 -h /var/cache/nginx -s /sbin/nologin -G chikwex chikwex

# Copy built files from build stage
COPY --from=build /app/build /usr/share/nginx/html

# Copy custom nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Set ownership
RUN chown -R chikwex:chikwex /var/cache/nginx && \
    chown -R chikwex:chikwex /var/log/nginx && \
    touch /var/run/nginx.pid && \
    chown -R chikwex:chikwex /var/run/nginx.pid

# Expose port
EXPOSE 80

# Install curl for health check (wget --spider has issues in busybox)
RUN apk add --no-cache curl

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -sf http://localhost:80/ > /dev/null || exit 1

# Run nginx
CMD ["nginx", "-g", "daemon off;"]
