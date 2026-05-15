FROM nginx:stable

RUN apt-get update \
    && apt-get install -y --no-install-recommends lego \
    && rm -rf /var/lib/apt/lists/*

COPY conf.d/default.conf /etc/nginx/conf.d/default.conf
COPY openssl-mtc.cnf /etc/ssl/openssl-mtc.cnf
COPY issue-and-run.sh /usr/local/bin/issue-and-run.sh
RUN chmod 0755 /usr/local/bin/issue-and-run.sh

ENV OPENSSL_CONF=/etc/ssl/openssl-mtc.cnf

ENTRYPOINT ["/usr/local/bin/issue-and-run.sh"]
