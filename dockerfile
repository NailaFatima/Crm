FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV HOME=/home/frappe

# Install docker-friendly dependencies and frappe bench prerequisites
RUN apt-get update && apt-get install -y \
    python3-pip python3-dev python3-venv git wget curl build-essential \
    mariadb-server redis-server nginx supervisor locales sudo procps \
    nodejs npm yarn \
    && rm -rf /var/lib/apt/lists/*

# Create frappe user and workspace
RUN useradd -ms /bin/bash frappe && mkdir -p /workspace
WORKDIR /workspace

# Install bench CLI
RUN pip3 install --no-cache-dir frappe-bench

# Prepare MariaDB dirs
RUN mkdir -p /var/run/mysqld /var/lib/mysql && chown -R mysql:mysql /var/lib/mysql /var/run/mysqld

# Copy init script and configs
COPY init.sh /workspace/init.sh
COPY start.sh /workspace/start.sh
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY nginx.conf /etc/nginx/sites-enabled/default

RUN chmod +x /workspace/init.sh  /workspace/start.sh

# expose port 8000
EXPOSE 8000

# start supervisord which will run mariadb, redis, nginx and bench (init.sh)
CMD ["/usr/bin/supervisord","-n","-c","/etc/supervisor/conf.d/supervisord.conf"]
