# ------------------------------------------
# - Stage: 01 - builder
# ------------------------------------------

# This image is also based on frappe/bench which we use for production
# https://github.com/pipech/erpnext-docker-debian/blob/master/Dockerfile
FROM pipech/erpnext-docker-debian:version-15-latest AS builder

# These variable has been set from base image
# $systemUser, $benchFolderName
USER $systemUser
WORKDIR /home/$systemUser/$benchFolderName

# Pin exact app versions. The base tag (version-15-latest) is a MOVING target that upstream
# froze at ~15.91 (Dec 2025) and abandoned for v16 — so we pin forward ourselves here.
# To upgrade later: bump these tags and rebuild (reproducible, unlike the moving base tag).
ARG FRAPPE_VERSION=v15.108.0
ARG ERPNEXT_VERSION=v15.108.3
# Cache bust: change this value to force rebuild of this layer
ARG CUSTOM_APPS_VERSION=8
RUN echo "-> Start builder (frappe ${FRAPPE_VERSION}, erpnext ${ERPNEXT_VERSION}, custom apps v${CUSTOM_APPS_VERSION})" \
    ### remove unused sites, created by base image
    && rm -rf /home/$systemUser/$benchFolderName/sites/site1.local \
    ### pin frappe + erpnext to exact release tags (base image only ships ~15.91)
    && cd /home/$systemUser/$benchFolderName/apps/frappe \
    && git fetch --depth 1 origin tag ${FRAPPE_VERSION} \
    && git -c advice.detachedHead=false checkout ${FRAPPE_VERSION} \
    && cd /home/$systemUser/$benchFolderName/apps/erpnext \
    && git fetch --depth 1 origin tag ${ERPNEXT_VERSION} \
    && git -c advice.detachedHead=false checkout ${ERPNEXT_VERSION} \
    && cd /home/$systemUser/$benchFolderName \
    ### IPv6 hotfix dropped: fixed upstream in v15.108 (connections.py now uses getaddrinfo/AF_UNSPEC)
    && bench setup requirements \
    ### install custom apps from monorepo
    && git clone https://github.com/mikpam/erpnext-custom-apps.git /tmp/custom-apps \
    && cp -r /tmp/custom-apps/ai_task_log /home/$systemUser/$benchFolderName/apps/ai_task_log \
    && /home/$systemUser/$benchFolderName/env/bin/pip install -e /home/$systemUser/$benchFolderName/apps/ai_task_log \
    && printf '\nai_task_log\n' >> /home/$systemUser/$benchFolderName/sites/apps.txt \
    && /home/$systemUser/$benchFolderName/env/bin/pip install google-generativeai \
    && rm -rf /tmp/custom-apps \
    && echo "-> Builder done!"


# ------------------------------------------
# - Stage: 02 - production
# ------------------------------------------

# Image version should also match with stage 01
# (Check pipech/erpnext-docker-debian Dockerfile)
# https://github.com/frappe/frappe_docker/blob/main/images/bench/Dockerfile
FROM frappe/bench:v5.22.9

# this env should match stage 01
# (Check pipech/erpnext-docker-debian Dockerfile)
ENV systemUser=frappe
ENV benchFolderName=bench

# Copied bench folder from build stage
COPY --from=builder --chown=$systemUser /home/$systemUser/$benchFolderName /home/$systemUser/$benchFolderName

# Copy template
COPY /railway/temp_nginx.conf /home/$systemUser/temp_nginx.conf
COPY /railway/temp_supervisor.conf /home/$systemUser/temp_supervisor.conf

USER root
WORKDIR /home/$systemUser/$benchFolderName

# [fix] "debconf: unable to initialize frontend: Dialog"
# https://github.com/moby/moby/issues/27988
ARG DEBIAN_FRONTEND=noninteractive

RUN echo "-> Install nginx & supervisor" \
    # apt-get update
    && apt-get update \
    && apt-get install -y \
    # nginx for serving files
    nginx \
    # supervisor to run multiple server per container
    supervisor \
    && echo "-> Cleaning installation" \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && echo "-> Remove nginx default site" \
    && rm /etc/nginx/sites-enabled/default \
    && echo "-> Rebuilding bench" \
    && su $systemUser -c "bench build" \
    && su $systemUser -c "cp -r /home/$systemUser/$benchFolderName/sites /home/$systemUser/$benchFolderName/built_sites"

COPY --chown=$systemUser --chmod=0755 /railway/railway-setup.sh /home/$systemUser/$benchFolderName/railway-setup.sh
COPY --chown=$systemUser --chmod=0755 /railway/railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
COPY --chown=$systemUser --chmod=0755 /railway/railway-cmd.sh /usr/local/bin/railway-cmd.sh

ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
CMD ["/usr/local/bin/railway-cmd.sh"]

EXPOSE 80
