FROM nikolaik/python-nodejs:python3.10-nodejs18

# Install the PM2 process manager for Node.js
RUN npm install pm2 -g

# Copy the application's dependencies files
COPY poetry.lock pyproject.toml ./

# Install the Python dependencies
RUN poetry install --no-dev --no-root

# Copy the rest of the application's files
COPY . .

RUN cp config/projects.example.json config/projects.json
RUN cp config/settings.example.json config/settings.json

# Make the shell scripts executable
RUN chmod +x ./snapshotter_autofill.sh ./docker-entrypoint.sh

# Start the application using PM2
# CMD pm2 start pm2.config.js && pm2 logs --lines 100

ENTRYPOINT ["/bin/bash", "-c", "./docker-entrypoint.sh"]