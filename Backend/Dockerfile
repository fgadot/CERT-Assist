# Build stage
FROM swift:5.9-jammy as build

RUN apt-get update && apt-get install -y \
    libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Package.swift ./
COPY Sources ./Sources

RUN swift build -c release

# Production stage
FROM swift:5.9-jammy-slim

RUN apt-get update && apt-get install -y \
    libsqlite3-0 \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -u 1000 -s /bin/bash vapor && \
    mkdir -p /app && \
    chown -R vapor:vapor /app

WORKDIR /app

# Copy as root, then change ownership
COPY --from=build /app/.build/release /app
COPY Public ./Public

# Change ownership of all files to vapor user
RUN chown -R vapor:vapor /app

# Switch to non-root user
USER vapor

EXPOSE 8080

ENV ENVIRONMENT=production

ENTRYPOINT ["./Run"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
