FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm install

COPY . .

# ไม่ต้อง EXPOSE แบบ fix ก็ได้ แต่ใส่ไว้ไม่เสียหาย
EXPOSE 3100

CMD ["npm", "start"]
