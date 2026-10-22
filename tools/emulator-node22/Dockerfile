# Linux Firebase emulator image on Node 22 (matches functions engines.node 22 / nodejs22 runtime).
FROM node:22-trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends openjdk-21-jre-headless ca-certificates && apt-get clean
RUN npm install -g firebase-tools@15.17.0
WORKDIR /work
