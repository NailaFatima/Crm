FROM python:3.10-slim

# 1. Install system deps
RUN apt-get update && apt-get install -y \
    curl \
    gnupg \
    build-essential \
    redis-tools \
    nginx \
    supervisor \
    git \
    && rm -rf /var/lib/apt/lists/*

# 2. Install Node.js 18 + Yarn
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs

RUN npm install -g yarn

# 3. Install bench
RUN pip install frappe-bench==5.19

# 4. Create workspace
WORKDIR /workspace

# Copy code
COPY . .

# Permissions
RUN chmod +x /workspace/init.sh /workspace/start.sh

CMD ["/usr/bin/supervisord", "-c", "/workspace/supervisord.conf"]
