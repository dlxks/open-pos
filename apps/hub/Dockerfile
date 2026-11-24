# Use latest stable channel SDK.
FROM dart:stable AS build

WORKDIR /workspace
COPY packages/pos_domain/ packages/pos_domain/
COPY apps/hub/pubspec.yaml apps/hub/pubspec.lock apps/hub/
WORKDIR /workspace/apps/hub
RUN dart pub get

COPY apps/hub/ /workspace/apps/hub/
RUN dart build cli --target bin/server.dart -o output
RUN dart build cli --target bin/maintenance.dart -o maintenance_output
RUN mkdir -p /tmp/pos-data && chown 65532:65532 /tmp/pos-data

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /workspace/apps/hub/output/bundle/ /app/
COPY --from=build /workspace/apps/hub/maintenance_output/bundle/ /maintenance/
COPY --chown=65532:65532 --from=build /tmp/pos-data/ /data/

ENV PORT=8080
ENV POS_HUB_DATABASE=/data/open_pos.sqlite
EXPOSE 8080
USER 65532:65532
ENTRYPOINT ["/app/bin/server"]
