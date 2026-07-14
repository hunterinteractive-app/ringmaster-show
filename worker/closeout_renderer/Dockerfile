FROM dart:stable AS build
WORKDIR /src
COPY worker/closeout_renderer/pubspec.yaml worker/closeout_renderer/analysis_options.yaml ./
RUN dart pub get
COPY lib ./lib
COPY worker/closeout_renderer/bin ./bin
RUN dart compile exe bin/closeout_renderer.dart -o /tmp/closeout_renderer

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --uid 10001 renderer
WORKDIR /app
COPY --chmod=0555 --from=build /tmp/closeout_renderer /app/closeout_renderer
COPY --chmod=0555 assets/fonts /app/assets/fonts
COPY --chmod=0555 assets/images /app/assets/images
USER renderer
ENV ASSET_ROOT=/app/assets PORT=8080
EXPOSE 8080
ENTRYPOINT ["/app/closeout_renderer"]
CMD ["--serve"]
