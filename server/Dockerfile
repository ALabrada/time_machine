# syntax=docker/dockerfile:1
FROM dart:stable AS build
WORKDIR /app
COPY time_machine_core ./time_machine_core
COPY time_machine_cloud ./time_machine_cloud
COPY time_machine_sources ./time_machine_sources
COPY server ./server
WORKDIR /app/server
RUN dart pub get
RUN dart compile exe bin/server.dart -o /app/proxy_server

FROM dart:stable
WORKDIR /app
COPY --from=build /app/proxy_server .
COPY build/web ./web
ENV PORT=8080
ENV IMAGE_CACHE_DIR=/app/image-cache
ENV WEB_BUILD_DIR=/app/web
VOLUME ["/app/image-cache"]
EXPOSE 8080
ENTRYPOINT ["./proxy_server"]