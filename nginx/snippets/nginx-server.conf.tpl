server {
    listen 80;
    server_name __SERVER_NAME__;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name __SERVER_NAME__;

    ssl_certificate __SSL_CERTIFICATE_PATH__;
    ssl_certificate_key __SSL_CERTIFICATE_KEY_PATH__;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    access_log /var/log/nginx/__SAFE_NAME__.access.log;
    error_log /var/log/nginx/__SAFE_NAME__.error.log warn;

    location / {
        proxy_pass __UPSTREAM__;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header Connection "";
    }
}
