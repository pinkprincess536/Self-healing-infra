# FROM: base image — official NGINX on a small Debian variant.
FROM nginx:1.27-alpine

# WORKDIR: sets the working directory for subsequent instructions.
# Not strictly required for NGINX, but demonstrates the instruction.
WORKDIR /usr/share/nginx/html

# COPY: bring in our static site content (build-time, baked into the image).
COPY html/ /usr/share/nginx/html/

# COPY: replace default server config with ours (adds the /health endpoint).
COPY nginx.conf /etc/nginx/conf.d/default.conf

# RUN: example of a layer-creating instruction. Kept minimal here since the
# base image already contains everything NGINX needs.
RUN nginx -t

# NGINX listens on 80 inside the container.
EXPOSE 80

# CMD: default process the container runs. nginx:alpine's base image already
# defines this, but it's explicit here so the instruction is visible.
CMD ["nginx", "-g", "daemon off;"]
