# The production front door. Its config is *replaced at deploy time* (docker cp + nginx reload),
# so it is baked into the image instead of bind-mounted (a bind-mounted file cannot be replaced).
FROM nginx:1.27-alpine
COPY default.conf /etc/nginx/conf.d/default.conf
