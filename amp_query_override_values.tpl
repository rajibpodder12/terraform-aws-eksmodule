serviceAccount:
    name: "amp-iamproxy-query-service-account"
    annotations:
        eks.amazonaws.com/role-arn: "${grafana_ingest_role}"
grafana.ini:
  auth:
    sigv4_auth_enabled: true
