ARG BASE_IMAGE_VERSION=3.7.12
FROM --platform=linux/amd64 python:${BASE_IMAGE_VERSION}

LABEL org.opencontainers.image.title="mus-mgmt" \
      org.opencontainers.image.description="MUS hardware automation framework" \
      org.opencontainers.image.authors="MUS Team"

COPY Pipfile Pipfile
COPY Pipfile.lock Pipfile.lock

RUN apt-get update -y \
 && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y sshpass iproute2 \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* \
 && pip install --no-cache-dir pipenv \
 && pipenv install --system --ignore-pipfile --clear
