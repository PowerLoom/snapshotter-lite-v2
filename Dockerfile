FROM python:3.10.16-slim

RUN apt-get update && apt-get install -y \
    build-essential git\
    && rm -rf /var/lib/apt/lists/*

# Install the PM2 process manager for Node.js
RUN pip install poetry

# Copy the application's dependencies files
COPY poetry.lock pyproject.toml /app/

# Install the Python dependencies
RUN cd /app && poetry install --no-root

# Create directories for repos
RUN mkdir -p /app/computes /app/config

# Copy the rest of the application's files
COPY . /app/

# Make the shell scripts executable
RUN chmod +x /app/*.sh

# Set workdir
WORKDIR /app
