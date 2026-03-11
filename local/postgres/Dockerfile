FROM postgres:16-alpine AS build

RUN apk add --no-cache build-base git postgresql-dev \
    && git clone --depth 1 https://github.com/fboulnois/pg_uuidv7.git /tmp/pg_uuidv7 \
    && cd /tmp/pg_uuidv7 \
    && gcc -Wall -fPIC -fvisibility=hidden -shared \
       -I$(pg_config --includedir-server) \
       -o pg_uuidv7.so pg_uuidv7.c \
    && cp pg_uuidv7.so $(pg_config --pkglibdir)/ \
    && cp pg_uuidv7.control $(pg_config --sharedir)/extension/ \
    && cp sql/*.sql $(pg_config --sharedir)/extension/

FROM postgres:16-alpine

COPY --from=build /usr/local/lib/postgresql/pg_uuidv7.so /usr/local/lib/postgresql/
COPY --from=build /usr/local/share/postgresql/extension/pg_uuidv7.control /usr/local/share/postgresql/extension/
COPY --from=build /usr/local/share/postgresql/extension/pg_uuidv7--1.7.sql /usr/local/share/postgresql/extension/
