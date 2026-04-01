FROM node:22-bookworm-slim
RUN apt-get update -qq && apt-get install -y --no-install-recommends ca-certificates git && rm -rf /var/lib/apt/lists/*
