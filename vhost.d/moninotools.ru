# Базовые настройки прокси
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection 'upgrade';
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_cache_bypass $http_upgrade;
proxy_redirect off;

# Статика Next.js
location /_next/static {
    alias /app/.next/static;
    expires 365d;
    add_header Cache-Control "public, max-age=31536000, immutable";
    access_log off;
}

location /static {
    alias /app/public/static;
    expires 365d;
    access_log off;
}

# Обработка изображений через Next.js Image Optimization
location /_next/image {
    proxy_pass http://user:3000/_next/image;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}

# Проксирование API запросов
location /file/ {
    proxy_pass http://api:3000/file/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}

# Основное проксирование
location / {
    proxy_pass http://user:3000;
}