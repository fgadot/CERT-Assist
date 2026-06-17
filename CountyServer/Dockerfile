# Build stage
FROM swift:5.9-jammy as build

WORKDIR /app

COPY Package.swift ./
COPY Sources ./Sources

RUN swift build -c release

# Production stage
FROM swift:5.9-jammy-slim

RUN useradd -m -u 1000 -s /bin/bash vapor && \
    mkdir -p /app && \
    chown -R vapor:vapor /app

WORKDIR /app

COPY --from=build /app/.build/release /app
COPY Public ./Public

RUN chown -R vapor:vapor /app

USER vapor

EXPOSE 8080

ENV ENVIRONMENT=production

ENTRYPOINT ["./Run"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
