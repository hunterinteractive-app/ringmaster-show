FROM dart:stable AS build
WORKDIR /src
COPY worker/closeout_renderer/pubspec.yaml worker/closeout_renderer/analysis_options.yaml ./
RUN dart pub get
COPY lib ./lib
COPY worker/closeout_renderer/bin ./bin
RUN dart compile exe bin/closeout_renderer.dart -o /tmp/closeout_renderer

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates python3 python3-venv \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --uid 10001 renderer
WORKDIR /app
RUN python3 -m venv /app/venv
COPY worker/closeout_renderer/python/requirements.txt /app/requirements.txt
RUN /app/venv/bin/pip install --no-cache-dir -r /app/requirements.txt
COPY worker/closeout_renderer/python/print_pack.py /app/print_pack.py
COPY --from=build /tmp/closeout_renderer /app/closeout_renderer
RUN chmod 0555 /app/closeout_renderer
COPY assets/fonts /app/assets/fonts
COPY assets/images /app/assets/images
RUN chmod -R a+rX /app/assets
USER renderer
ENV ASSET_ROOT=/app/assets PORT=8080
EXPOSE 8080
ENTRYPOINT ["/app/closeout_renderer"]
CMD ["--serve"]
