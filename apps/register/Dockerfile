FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /workspace
COPY packages/pos_domain/ packages/pos_domain/
COPY apps/register/pubspec.yaml apps/register/pubspec.lock apps/register/
WORKDIR /workspace/apps/register
RUN flutter pub get
COPY apps/register/ /workspace/apps/register/
RUN flutter build web --release

FROM nginxinc/nginx-unprivileged:stable-alpine
COPY apps/register/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /workspace/apps/register/build/web/ /usr/share/nginx/html/
EXPOSE 8080
