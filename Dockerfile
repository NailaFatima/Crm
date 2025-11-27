# -----------------------------------------------------------
# 1. Base image = frappe bench
# -----------------------------------------------------------
FROM frappe/bench:latest

# -----------------------------------------------------------
# 2. Install MariaDB + Redis inside same container
# -----------------------------------------------------------
USER root

RUN apt-get update && apt-get install -y \
    mariadb-server \
    redis-server \
    supervisor \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------
# 3. Create directories
# -----------------------------------------------------------
RUN mkdir -p /var/log/supervisor \
    && mkdir -p /workspace

WORKDIR /workspace

# -----------------------------------------------------------
# 4. Copy project + init script
# -----------------------------------------------------------
COPY . /workspace
RUN chmod +x /workspace/init.sh

# -----------------------------------------------------------
# 5. Configure MariaDB for Frappe
# -----------------------------------------------------------
RUN sed -i 's/^bind-address.*/bind-address = 0.0.0.0/' /etc/mysql/mariadb.conf.d/50-server.cnf

# -----------------------------------------------------------
# 6. Create Supervisor config (Redis + MariaDB + Bench)
# -----------------------------------------------------------
RUN bash -c 'cat > /etc/supervisor/conf.d/services.conf <<EOF
[program:mariadb]
command=/usr/sbin/mysqld
autostart=true
autorestart=true

[program:redis]
command=/usr/bin/redis-server
autostart=true
autorestart=true

[program:bench]
command=bash /workspace/init.sh
directory=/workspace
autostart=true
autorestart=true
EOF'

# -----------------------------------------------------------
# 7. Expose ports
# -----------------------------------------------------------
EXPOSE 8000
EXPOSE 9000

# -----------------------------------------------------------
# 8. Start everything via supervisor
# -----------------------------------------------------------
CMD ["/usr/bin/supervisord", "-n"]
