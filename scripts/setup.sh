#!/bin/bash
# Prepares T-Pot's Elasticsearch for php-Honeypot data: enrichment pipeline, 30-day retention, index template.
# Run once on the VPS before `docker compose up`. Re-running is safe.
set -e
ES="${ES_URL:-http://127.0.0.1:64298}"
put() { curl -fsS -X PUT "$ES$1" -H 'Content-Type: application/json' -d "$2" >/dev/null && echo "ok  $1"; }

put /_ingest/pipeline/php2shell-enrich '{
  "description": "php-Honeypot enrichment: GeoIP, ASN, user agent",
  "processors": [
    {"geoip": {"field": "src_ip", "target_field": "geo", "ignore_missing": true, "ignore_failure": true}},
    {"geoip": {"field": "src_ip", "target_field": "asn", "database_file": "GeoLite2-ASN.mmdb", "ignore_missing": true, "ignore_failure": true}},
    {"user_agent": {"field": "ua", "target_field": "ua_parsed", "ignore_missing": true, "ignore_failure": true}}
  ]}'

put /_ilm/policy/php2shell '{
  "policy": {"phases": {"hot": {"actions": {}}, "delete": {"min_age": "30d", "actions": {"delete": {}}}}}}'

put /_index_template/php2shell '{
  "index_patterns": ["php2shell-*"],
  "template": {
    "settings": {"index.lifecycle.name": "php2shell", "number_of_shards": 1, "number_of_replicas": 0},
    "mappings": {
      "dynamic_templates": [{"strings_as_keywords": {"match_mapping_type": "string",
        "mapping": {"type": "keyword", "ignore_above": 1024}}}],
      "properties": {
        "@timestamp": {"type": "date"},
        "src_ip": {"type": "ip", "ignore_malformed": true},
        "geo": {"properties": {"location": {"type": "geo_point"}}},
        "headers": {"type": "object", "enabled": false},
        "multipart": {"type": "object", "dynamic": true},
        "exploit_like": {"type": "boolean"},
        "tls": {"type": "boolean"},
        "body_len": {"type": "long"},
        "resp_len": {"type": "long"},
        "upstream_ms": {"type": "long"},
        "read_ms": {"type": "long"},
        "request_line": {"type": "keyword", "ignore_above": 512},
        "body_preview_b64": {"type": "keyword", "ignore_above": 1024, "index": false}
      }}}}'
echo "done. Check data later with:  curl -s $ES/php2shell-*/_count"
