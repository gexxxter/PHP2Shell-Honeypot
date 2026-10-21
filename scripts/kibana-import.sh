#!/bin/bash
# Imports a "php-Honeypot" dashboard (data view + aggregation-based visualizations) into T-Pot's Kibana.
# Needs jq and curl. Safe to re-run (overwrites by id). Best effort: if Kibana rejects something, the live
# dashboard still works and the data view alone is enough to build charts in Discover / Lens.
set -e
KB="${KIBANA_URL:-}"
if [ -z "$KB" ]; then
    for u in http://127.0.0.1:64296 http://127.0.0.1:64296/kibana; do
        curl -fsS -o /dev/null "$u/api/status" 2>/dev/null && KB="$u" && break
    done
fi
[ -n "$KB" ] || { echo "Kibana not reachable on 127.0.0.1:64296 yet; set KIBANA_URL and re-run scripts/kibana-import.sh"; exit 1; }

OUT="$(mktemp)"
REF='[{"name":"kibanaSavedObjectMeta.searchSourceJSON.index","type":"index-pattern","id":"php2shell"}]'

# vis <id> <title> <type> <params-json> <aggs-json> <kql-query>
vis() {
    jq -nc --arg id "$1" --arg title "$2" --arg type "$3" --argjson params "$4" --argjson aggs "$5" --arg q "$6" --argjson ref "$REF" '
    {id:$id, type:"visualization",
     attributes:{title:$title, description:"", uiStateJSON:"{}",
       visState:({title:$title, type:$type, aggs:$aggs, params:$params}|tostring),
       kibanaSavedObjectMeta:{searchSourceJSON:({query:{query:$q,language:"kuery"},filter:[],indexRefName:"kibanaSavedObjectMeta.searchSourceJSON.index"}|tostring)}},
     references:$ref}' >> "$OUT"
}

COUNT='{"id":"1","enabled":true,"type":"count","params":{},"schema":"metric"}'
terms() { # id field size [schema]
    echo "{\"id\":\"$1\",\"enabled\":true,\"type\":\"terms\",\"params\":{\"field\":\"$2\",\"orderBy\":\"1\",\"order\":\"desc\",\"size\":$3,\"otherBucket\":false,\"missingBucket\":false},\"schema\":\"${4:-segment}\"}"
}
METRIC_PARAMS='{"addTooltip":true,"addLegend":false,"type":"metric","metric":{"percentageMode":false,"useRanges":false,"colorSchema":"Green to Red","metricColorMode":"None","colorsRange":[{"from":0,"to":10000}],"labels":{"show":true},"invertColors":false,"style":{"bgFill":"#000","bgColor":false,"labelColor":false,"subText":"","fontSize":48}}}'
PIE_PARAMS='{"type":"pie","addTooltip":true,"addLegend":true,"legendPosition":"right","isDonut":true,"labels":{"show":false,"values":true,"last_level":true,"truncate":100}}'
TABLE_PARAMS='{"perPage":10,"showPartialRows":false,"showMetricsAtAllLevels":false,"showTotal":false,"totalFunc":"sum","percentageCol":""}'
HIST_PARAMS='{"type":"histogram","grid":{"categoryLines":false},"categoryAxes":[{"id":"CategoryAxis-1","type":"category","position":"bottom","show":true,"style":{},"scale":{"type":"linear"},"labels":{"show":true,"filter":true,"truncate":100},"title":{}}],"valueAxes":[{"id":"ValueAxis-1","name":"LeftAxis-1","type":"value","position":"left","show":true,"style":{},"scale":{"type":"linear","mode":"normal"},"labels":{"show":true,"rotate":0,"filter":false,"truncate":100},"title":{"text":"Count"}}],"seriesParams":[{"show":true,"type":"histogram","mode":"stacked","data":{"label":"Count","id":"1"},"valueAxis":"ValueAxis-1","drawLinesBetweenPoints":true,"lineWidth":2,"showCircles":true}],"addTooltip":true,"addLegend":true,"legendPosition":"right","times":[],"addTimeMarker":false,"labels":{"show":false},"thresholdLine":{"show":false,"value":10,"width":1,"style":"full","color":"#E7664C"}}'
DATEH='{"id":"2","enabled":true,"type":"date_histogram","params":{"field":"@timestamp","useNormalizedEsInterval":true,"scaled":false,"interval":"auto","drop_partials":false,"min_doc_count":1,"extended_bounds":{}},"schema":"segment"}'

# data view. `raw_request` is a runtime field that reads the readable request text from _source: the stored request_text field
# is too long to be indexed (ignore_above), so Kibana could not show it in a table column otherwise.
RUNTIME='{"raw_request":{"type":"keyword","script":{"source":"if (params._source.containsKey(\"request_text\")) { String s = params._source.request_text; emit(s.length() > 30000 ? s.substring(0, 30000) : s); }"}}}'
jq -nc --arg rt "$RUNTIME" '{id:"php2shell",type:"index-pattern",attributes:{title:"php2shell-*",timeFieldName:"@timestamp",runtimeFieldMap:$rt},references:[]}' >> "$OUT"

# saved searches (Discover tables) embedded in the dashboard: the requests themselves, newest first.
# search <id> <title> <kql-query> <columns-json> <rows-per-cell>
search() {
    local q="$3"
    if [ -n "$IGN" ]; then if [ -n "$q" ]; then q="($q) and $IGN"; else q="$IGN"; fi; fi
    jq -nc --arg id "$1" --arg title "$2" --arg q "$q" --argjson cols "$4" --argjson rh "$5" --argjson ref "$REF" '
    {id:$id, type:"search",
     attributes:{title:$title, description:"", hits:0, columns:$cols, sort:[["@timestamp","desc"]], grid:{}, hideChart:true,
       isTextBasedQuery:false, viewMode:"documents", rowHeight:$rh, headerRowHeight:1,
       kibanaSavedObjectMeta:{searchSourceJSON:({query:{query:$q,language:"kuery"},filter:[],indexRefName:"kibanaSavedObjectMeta.searchSourceJSON.index"}|tostring)}},
     references:$ref}' >> "$OUT"
}
search s-requests     "Exploit-like requests: the raw HTTP request, newest first" 'exploit_like:true and kind:"request"' '["src_ip","geo.country_name","tags","raw_request"]' 12
search s-all-requests "All requests: the raw HTTP request, newest first"          'kind:"request"'                        '["src_ip","geo.country_name","tags","raw_request"]' 8

vis v-req      "Requests"                  metric "$METRIC_PARAMS" "[$COUNT]" 'kind:"request"'
vis v-exploit  "Exploit-like requests"     metric "$METRIC_PARAMS" "[$COUNT]" 'exploit_like:true and kind:"request"'
vis v-rce      "RCE confirmed"             metric "$METRIC_PARAMS" "[$COUNT]" 'kind:"rce_confirmed"'
vis v-crash    "PHP worker crashes"        metric "$METRIC_PARAMS" "[$COUNT]" 'kind:"php_crash"'
vis v-ht       "Honeytoken reuse / decoy"  metric "$METRIC_PARAMS" "[$COUNT]" 'tags:"honeytoken-reuse" or kind:"decoy_connect"'
vis v-time     "Events over time by kind"  histogram "$HIST_PARAMS" "[$COUNT,$DATEH,$(terms 3 kind 5 group)]" ''
vis v-tags     "Tags"                      pie "$PIE_PARAMS" "[$COUNT,$(terms 2 tags 15)]" ''
vis v-country  "Source countries"          pie "$PIE_PARAMS" "[$COUNT,$(terms 2 geo.country_name 12)]" 'kind:"request"'
vis v-ips      "Top source IPs"            table "$TABLE_PARAMS" "[$COUNT,$(terms 2 src_ip 15 bucket)]" 'kind:"request"'
vis v-asn      "Top networks"              table "$TABLE_PARAMS" "[$COUNT,$(terms 2 asn.organization_name 15 bucket)]" 'kind:"request"'
vis v-shapes   "Payload shapes"            table "$TABLE_PARAMS" "[$COUNT,$(terms 2 shape_hash 15 bucket)]" 'exploit_like:true and kind:"request"'
vis v-paths    "Paths requested"           table "$TABLE_PARAMS" "[$COUNT,$(terms 2 path 15 bucket)]" 'kind:"request"'
vis v-ua       "User-agent families"       pie "$PIE_PARAMS" "[$COUNT,$(terms 2 ua_parsed.name 10)]" 'kind:"request"'
vis v-rcecmd   "RCE commands"              table "$TABLE_PARAMS" "[$COUNT,$(terms 2 cmdline 15 bucket)]" 'kind:"rce_confirmed"'
vis v-iocs     "Extracted IOCs"            table "$TABLE_PARAMS" "[$COUNT,$(terms 2 iocs 15 bucket)]" 'kind:"request"'

# dashboard layout: id w h
PANELS=(v-req:8:6 v-exploit:8:6 v-rce:8:6 v-crash:8:6 v-ht:8:6 s-requests:48:24 v-time:48:12 v-tags:16:14 v-country:16:14 v-ua:16:14
        v-ips:24:14 v-asn:24:14 v-shapes:24:14 v-paths:24:14 v-rcecmd:24:14 v-iocs:24:14 s-all-requests:48:22)
panels="[]"; refs="[]"; x=0; y=0; rowh=0; i=0
for p in "${PANELS[@]}"; do
    IFS=: read -r id w h <<<"$p"
    if [ $((x + w)) -gt 48 ]; then x=0; y=$((y + rowh)); rowh=0; fi
    ptype=visualization; [[ "$id" == s-* ]] && ptype=search       # s-* ids are saved searches (raw request tables)
    panels=$(jq -c --argjson x $x --argjson y $y --argjson w $w --argjson h $h --arg i "$i" --arg t "$ptype" \
        '. + [{version:"8.0.0",type:$t,gridData:{x:$x,y:$y,w:$w,h:$h,i:$i},panelIndex:$i,embeddableConfig:{},panelRefName:("panel_"+$i)}]' <<<"$panels")
    refs=$(jq -c --arg n "panel_$i" --arg id "$id" --arg t "$ptype" '. + [{name:$n,type:$t,id:$id}]' <<<"$refs")
    x=$((x + w)); [ "$h" -gt "$rowh" ] && rowh=$h; i=$((i + 1))
done
jq -nc --arg panels "$panels" --argjson refs "$refs" '
  {id:"php2shell-dashboard",type:"dashboard",
   attributes:{title:"php-Honeypot", description:"Attacks on the fake webshop and confirmed RCE",
     panelsJSON:$panels, optionsJSON:"{\"useMargins\":true,\"hidePanelTitles\":false}",
     timeRestore:true, timeFrom:"now-24h", timeTo:"now", refreshInterval:{pause:false,value:10000},
     kibanaSavedObjectMeta:{searchSourceJSON:"{\"query\":{\"query\":\"\",\"language\":\"kuery\"},\"filter\":[]}"}},
   references:$refs}' >> "$OUT"

resp=$(curl -sS -X POST "$KB/api/saved_objects/_import?overwrite=true" -H "kbn-xsrf: true" -F file=@"$OUT;filename=php2shell.ndjson")
echo "$resp" | jq -c '{success, successCount, errors: [.errors[]? | {id, type, error: .error.type}]}' 2>/dev/null || echo "$resp"
rm -f "$OUT"
echo "Dashboard: open T-Pot's Kibana (https://<vps>:64297 -> Kibana) -> Dashboards -> php-Honeypot"
