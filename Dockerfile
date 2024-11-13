# Use specific version for reproducible builds
FROM timescale/timescaledb-ha:pg16.4-ts2.17.1-all

# MAINTAINER is deprecated, use LABEL instead
LABEL maintainer="Keith Brings <keith.brings@noizu.com>"

USER root

# Use WORKDIR to specify working directory
WORKDIR /docker-scripts

# COPY is preferred over ADD unless extracting remote archives
COPY ./scripts .

# Combine RUN commands and use absolute paths
RUN chmod u+x ./setup.sh && ./setup.sh

USER postgres

