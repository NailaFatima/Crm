FROM python:3.10-slim

# System dependencies
RUN apt-get update && apt-get install -y \
    curl \
    gnupg \
    build-essential \
    redis-tools \
    nginx \
    supervisor \
    git \
    && rm -rf /var/lib/apt/lists/*

# Node + Yarn
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs
RUN npm install -g yarn

# FIX 1 (Required!) Click compatible version
RUN pip install --no-cache-dir "click==8.1.3"

# Install bench
RUN pip install --no-cache-dir frappe-bench==5.19

WORKDIR /workspace

COPY . .

RUN chmod +x /workspace/init.sh \
             /workspace/start.sh

CMD ["/usr/bin/supervisord", "-c", "/workspace/supervisord.conf"]
