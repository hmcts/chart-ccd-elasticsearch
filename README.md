# chart-ccd-elasticsearch

This chart is intended for deploying the full CCD product stack with elasticsearch enabled search.
Currently included are:
* data-store-api
* user-profile-api
* definition-store-api
* case-management-web (optional, enabled with a flag)
* print-api (aka case-print-service which is optional, enabled with a flag)
* logstash
* elasticsearch

**__Please use the base ccd chart unless you really need the extra search functionalities provided by elasticsearch as these cost resources and increase deployment time.__**

We will take small PRs and small features to this chart but more complicated needs should be handled in your own chart.

## Example configuration

Below is example configuration for running this chart on a PR to test your application with CCD, it could easily be tweaked to work locally if you wish, PRs to make that simpler are welcome.

requirements.yaml
```yaml
dependencies:
  - name: ccd-elasticsearch
    version: '0.4.0'
    repository: '@hmcts'
```

The `SERVICE_FQDN`, `INGRESS_IP` and `CONSUL_LB_IP` are all provided by the pipeline, but require you to pass them through

values.template.yaml
```yaml
ccd-elasticsearch:

  ccd:
    ingressHost: ${SERVICE_FQDN}
    ingressIP: ${INGRESS_IP}
    consulIP: ${CONSUL_LB_IP}

    apiGateway:
      s2sKey: ${API_GATEWAY_S2S_KEY}
      idamClientSecret: ${API_GATEWAY_IDAM_SECRET}

    dataStoreApi:
      s2sKey: ${DATA_STORE_S2S_KEY}

    definitionStoreApi:
      s2sKey: ${DEFINITION_STORE_S2S_KEY}

    caseManagementWeb:
     # enabled: true # if you need access to the web ui then enable this, otherwise it won't be deployed

    printApi:
      # enabled: true # if you need access to the case print service then enable this
      s2sKey: ${PRINT_S2S_KEY}
      probateTemplateUrl: http://${SERVICE_NAME}-probate-app

```

The data sink between ccd and elasticsearch has the following default configuration which can also be overridden in values.template.yaml
```yaml
ccd-elasticsearch:

logstash:
  elasticsearch:
    host: "{{ .Release.Name }}-ccd-elasticsearch-client"
    port: 9200
  configTpl:
    postgresql.host: "{{ .Release.Name }}-ccd-postgres"
    postgresql.port: "5432"
  inputs:
    main: |-
      input {
        jdbc {
          # Postgres jdbc connection string to our database, mydb
          jdbc_connection_string => "jdbc:postgresql://${POSTGRESQL_HOST}:${POSTGRESQL_PORT}/data-store"
          # The user we wish to execute our statement as
          jdbc_user => "hmcts"
          jdbc_password => "hmcts"
          jdbc_validate_connection => true
          # The path to jdbc driver
          jdbc_driver_library => "/usr/share/logstash/drivers/postgresql-42.2.5.jar"
          # The name of the driver class for Postgresql
          jdbc_driver_class => "org.postgresql.Driver"
          jdbc_paging_enabled => "true"
          jdbc_page_size => "1000"
          jdbc_default_timezone => "UTC"
          statement => "SELECT id, created_date, last_modified, jurisdiction, case_type_id, state, data::TEXT as json_data, data_classification::TEXT as json_data_classification, reference, security_classification from case_data where last_modified >= :sql_last_value::timestamp"
          clean_run => false
          # every second
          schedule => "* * * * * *"
          # every 2 seconds
          # schedule => "/2 * * * * *"
        }
      }
  filters:
    main: |-
      filter {
        json {
          source => "json_data"
          target => "data"
          remove_field => ["json_data"]
        }
        json {
          source => "json_data_classification"
          target => "data_classification"
          remove_field => ["json_data_classification"]
        }
        mutate {
          add_field => { "index_id" => "%{case_type_id}_cases" }
        }
        mutate {
          lowercase => [ "index_id" ]
        }
      }
  outputs:
    main: |-
      #FIXME document_type is deprecated
      output {
        elasticsearch {
          hosts => ["${ELASTICSEARCH_HOST}:${ELASTICSEARCH_PORT}"]
          sniffing => false
          index => "%{[index_id]}"
          document_type => "_doc"
          document_id => "%{id}"
        }
      }

```


The idam secret and s2s keys need to be loaded in the pipeline,
example config:

```
def secrets = [
  'your-vault-${env}': [
    secret('idam-client-secret', 'IDAM_CLIENT_SECRET') // optional, this is an example
  ],
  's2s-${env}'      : [
    secret('microservicekey-ccd-data', 'DATA_STORE_S2S_KEY'),
    secret('microservicekey-ccd-definition', 'DEFINITION_STORE_S2S_KEY'),
    secret('microservicekey-ccd-gw', 'API_GATEWAY_S2S_KEY'),
    secret('microservicekey-ccd-ps', 'PRINT_S2S_KEY')
  ],
  'ccd-${env}'      : [
    secret('ccd-api-gateway-oauth2-client-secret', 'API_GATEWAY_IDAM_SECRET')
  ]
]

withPipeline(type, product, component) {
  loadVaultSecrets(secrets)
}
```

## Configuration

This chart does not introduce any new templates. It is a composition of the following charts:

- [chart-ccd](https://github.com/hmcts/chart-ccd)
- [logstash](https://github.com/hmcts/charts/stable/logstash) 
- [elasticsearch](https://github.com/hmcts/charts/stable/elasticsearch) 

For details of configurable parameters please check the specific chart.


## Development and Testing

Default configuration (e.g. default image and ingress host) is setup for sandbox. This is suitable for local development and testing.

- Ensure you have logged in with `az cli` and are using `sandbox` subscription (use `az account show` to display the current one).
- For local development see the `Makefile` for available targets.
- To execute an end-to-end build, deploy and test run `make`.
- to clean up deployed releases, charts, test pods and local charts, run `make clean`

`helm test` will deploy a busybox container alongside the release which performs a simple HTTP request against the service health endpoint. If it doesn't return `HTTP 200` the test will fail. **NOTE:** it does NOT run with `--cleanup` so the test pod will be available for inspection.

### Testing inside another chart locally

You can easily include this chart in another chart for testing:

requirements.yaml
```
  - name: ccd-elasticsearch
    version: '>0.4.0'
    repository: file://<path-to-repository-can-be-relative-or-absolute>/chart-ccd-elasticsearch/ccd-elasticsearch
```

## Azure DevOps Builds
Builds are run against the 'nonprod' AKS cluster.

### Pull Request Validation
A build is triggered when pull requests are created. This build will run `helm lint`, deploy the chart using `ci-values.yaml` and run `helm test`.

### Release Build
Triggered when the repository is tagged (e.g. when a release is created). Also performs linting and testing, and will publish the chart to ACR on success.
