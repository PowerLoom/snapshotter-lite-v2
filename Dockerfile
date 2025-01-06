FROM nikolaik/python-nodejs:python3.10-nodejs18

# Install the PM2 process manager for Node.js
RUN npm install pm2 -g

# Copy the application's dependencies files
COPY poetry.lock pyproject.toml ./

# Install the Python dependencies
RUN poetry install --no-dev --no-root

# Create directories for repos
RUN mkdir -p /app/computes /app/config

# Copy bootstrap script and make it executable
COPY bootstrap.sh /app/bootstrap.sh
RUN chmod +x /app/bootstrap.sh

# Copy the rest of the application's files
COPY . .

# Make the shell scripts executable
RUN chmod +x ./snapshotter_autofill.sh ./init_docker.sh

# Set workdir
WORKDIR /app

# Start the application using PM2
# CMD pm2 start pm2.config.js && pm2 logs --lines 100
