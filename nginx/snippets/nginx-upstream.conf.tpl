upstream __UPSTREAM_NAME__ {
    least_conn;
    server __UPSTREAM_TARGET__;
    keepalive 32;
}
