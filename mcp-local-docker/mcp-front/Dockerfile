FROM node:18-slim
WORKDIR /app
COPY package.json package.json
RUN npm install --silent
COPY . .
EXPOSE 8080
CMD ["node", "server.js"]
