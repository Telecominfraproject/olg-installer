# OpenLAN Gateway uCentral Client Docker Image
#
# Extends the RouterArchitects base image with OLG-specific VyOS integration files
#
# Base image provides:
# - uCentral client framework
# - Standard AP/switch templates
# - Core utilities and libraries
#
# This image adds:
# - VyOS-specific configuration generator (JSON/merge approach)
# - VyOS REST API client
# - State reporter using VyOS show commands
# - Modified capabilities detection for VyOS
# - Custom templates for VyOS integration

FROM routerarchitect123/ucentral-client:olgV5

# Metadata
LABEL maintainer="OLG Project"
LABEL version="olgV6"
LABEL description="OpenLAN Gateway uCentral client with VyOS integration"
LABEL base-image="routerarchitect123/ucentral-client:olgV5"

# Copy OLG-specific root-level uCentral files (modified from base)
COPY iso-files/ucentral-customizations/capabilities.uc /usr/share/ucentral/
COPY iso-files/ucentral-customizations/ucentral.uc /usr/share/ucentral/

# Copy VyOS integration core files
COPY iso-files/ucentral-customizations/vyos/config_prepare.uc /usr/share/ucentral/vyos/
COPY iso-files/ucentral-customizations/vyos/https_server_api.uc /usr/share/ucentral/vyos/
COPY iso-files/ucentral-customizations/vyos/parsers.uc /usr/share/ucentral/vyos/
COPY iso-files/ucentral-customizations/vyos/state.uc /usr/share/ucentral/vyos/

# Copy VyOS template files (only modified/new templates)
COPY iso-files/ucentral-customizations/vyos/templates/interface.uc /usr/share/ucentral/vyos/templates/
COPY iso-files/ucentral-customizations/vyos/templates/interface/bridge.uc /usr/share/ucentral/vyos/templates/interface/
COPY iso-files/ucentral-customizations/vyos/templates/interface/router.uc /usr/share/ucentral/vyos/templates/interface/
COPY iso-files/ucentral-customizations/vyos/templates/nat.uc /usr/share/ucentral/vyos/templates/

# Fix state.uc symlink to point to VyOS version
RUN rm -f /usr/share/ucentral/state.uc && \
    ln -s /usr/share/ucentral/vyos/state.uc /usr/share/ucentral/state.uc

# Ensure correct permissions
RUN chmod +x /usr/share/ucentral/capabilities.uc \
             /usr/share/ucentral/ucentral.uc \
             /usr/share/ucentral/vyos/*.uc \
             /usr/share/ucentral/vyos/templates/*.uc \
             /usr/share/ucentral/vyos/templates/interface/*.uc

# The container still requires runtime configuration via volume mounts:
# - /etc/config (UCI configuration files)
# - /etc/config-shadow (UCI shadow configuration files)
# - /etc/ucentral (gateway.json, vyos-info.json, certificates)
#
# These are site-specific and must be provided at runtime.

# Note: This image inherits the following unchanged from base image:
# - Standard service templates (DHCP, DNS, HTTPS, SSH)
# - Standard system templates (PKI, system, version)
# - Standard interface templates (ethernet)
# - All uCentral framework files (renderer.uc, schemareader.uc, etc.)
