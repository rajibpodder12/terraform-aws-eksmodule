serviceAccounts:
        server:
            name: "amp-iamproxy-ingest-service-account"
            annotations:
                eks.amazonaws.com/role-arn: "${amp_ingest_role}"
server:
    remoteWrite:
        - url: ${prometheus_endpoint}/api/v1/remote_write
          sigv4:
            region: ${region}
          queue_config:
            max_samples_per_send: 1000
            max_shards: 200
            capacity: 2500
