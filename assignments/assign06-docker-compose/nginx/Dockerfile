# ChikwexDockerApp - Nginx Reverse Proxy Dockerfile
FROM nginx:alpine

# Install curl for health checks
RUN apk add --no-cache curl

# Create non-root user
RUN addgroup -g 1001 -S chikwex && \
    adduser -S -D -H -u 1001 -h /var/cache/nginx -s /sbin/nologin -G chikwex chikwex

# Remove default config
RUN rm /etc/nginx/conf.d/default.conf

# Copy custom config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Create required directories and set permissions
RUN chown -R chikwex:chikwex /var/cache/nginx && \
    chown -R chikwex:chikwex /var/log/nginx && \
    touch /var/run/nginx.pid && \
    chown -R chikwex:chikwex /var/run/nginx.pid

# Expose port 80
EXPOSE 80

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -sf http://localhost:80/health > /dev/null || exit 1

# Run nginx
CMD ["nginx", "-g", "daemon off;"]
