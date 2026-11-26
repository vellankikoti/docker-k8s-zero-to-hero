# Jenkins for the lab: the official LTS image + the docker CLI (to build/push/deploy through the host's
# Docker engine) + python3 (to run the app's tests) + plugins pre-installed, and configured as code.
FROM docker:27-cli AS dockercli

FROM jenkins/jenkins:lts-jdk17
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 curl jq git \
 && rm -rf /var/lib/apt/lists/*
COPY --from=dockercli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=dockercli /usr/local/libexec/docker/cli-plugins/docker-buildx /usr/local/libexec/docker/cli-plugins/docker-buildx
COPY --from=dockercli /usr/local/libexec/docker/cli-plugins/docker-compose /usr/local/libexec/docker/cli-plugins/docker-compose
# The repo is mounted read-only from your laptop (a different owner): tell git that is fine.
RUN git config --system --add safe.directory '*'

# Optional: trust extra root certificates (corporate proxies). See extra-ca/README.md. Harmless when the folder is empty.
COPY extra-ca/ /tmp/extra-ca/
RUN cd /tmp/extra-ca && for bundle in *.crt; do [ -e "$bundle" ] || continue; \
      awk -v b="$bundle" '/BEGIN CERTIFICATE/{n++} {print > (b "." n ".pem")}' "$bundle"; done; \
    for c in *.pem; do [ -e "$c" ] || continue; \
      keytool -importcert -noprompt -trustcacerts -cacerts -storepass changeit -alias "extra-$c" -file "$c" >/dev/null 2>&1 || true; done; \
    rm -rf /tmp/extra-ca

USER jenkins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
# ALLOW_LOCAL_CHECKOUT: the Git plugin refuses file:// repositories by default (a safety feature).
# We turn it on because the lab builds the repository mounted from your laptop.
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true" \
    CASC_JENKINS_CONFIG=/usr/share/jenkins/casc/jenkins.yaml
# The config lives OUTSIDE the jenkins_home volume, so a rebuilt image is never hidden by old volume data.
COPY casc /usr/share/jenkins/casc
