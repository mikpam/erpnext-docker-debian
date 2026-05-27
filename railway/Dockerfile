FROM frappe/erpnext:v16.19.1

USER root
RUN apt-get update && apt-get install -y supervisor && rm -rf /var/lib/apt/lists/*
COPY railway/supervisord.conf /etc/supervisor/conf.d/frappe.conf
COPY --chmod=0755 railway/entrypoint.sh /usr/local/bin/railway-entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
