# Use Swift official image
FROM swift:5.9-jammy as build

# Install dependencies
RUN apt-get update && apt-get install -y \
    libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy package files
COPY Package.swift ./
COPY Sources ./Sources

# Build the application
RUN swift build -c release

# Production image
FROM swift:5.9-jammy-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libsqlite3-0 \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy built executable
COPY --from=build /app/.build/release /app
COPY Public ./Public

# Expose port
EXPOSE 8080

# Set environment
ENV ENVIRONMENT=production

# Run the app
ENTRYPOINT ["./Run"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
