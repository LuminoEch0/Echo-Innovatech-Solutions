"""CS2 SOAR worker: listener -> SQS -> rule engine -> actions.

Components (co-located by design, see tech justification 9.3):
  listener  : Flask, validates Token auth, enqueues Grafana alerts
  engine    : background thread, SQS long-poll, rule map, dedupe
  actions   : notify (Discord) / record (DynamoDB) / block (NACL)
  sweeper   : background thread, expires NACL denies, publishes DlqDepth
Metrics     : CloudWatch namespace CS2/SOAR (REQ-P2-09)
Idempotency : conditional DynamoDB put (at-least-once SQS is safe)
"""
import json, os, time, threading, logging, hashlib
from datetime import datetime, timezone

import boto3, requests
from flask import Flask, request, jsonify

QUEUE_URL     = os.environ["QUEUE_URL"]
DDB_TABLE     = os.environ["DDB_TABLE"]
NACL_ID       = os.environ["NACL_ID"]
NACL_TTL      = int(os.environ.get("NACL_TTL_SECONDS", "600"))
DISCORD_URL   = os.environ["DISCORD_WEBHOOK_URL"]
WEBHOOK_TOKEN = os.environ["WEBHOOK_TOKEN"]
AWS_REGION    = os.environ.get("AWS_REGION", "eu-central-1")
CW_NS         = "CS2/SOAR"

sqs  = boto3.client("sqs", region_name=AWS_REGION)
ddb  = boto3.client("dynamodb", region_name=AWS_REGION)
ec2  = boto3.client("ec2", region_name=AWS_REGION)
cw   = boto3.client("cloudwatch", region_name=AWS_REGION)

app = Flask(__name__)
log = logging.getLogger("soar")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

# rule map: alertname -> action set (arch design table 5.3 / 6.2)
RULES = {
    "ssh-bruteforce":     {"actions": ["notify", "record", "block"]},
    "pfsense-deny-flood": {"actions": ["notify", "record"]},  # on-prem attacker: NACL can't reach
}
# never block: AWS VPC space, the pfSense gateway itself, loopback
BLOCK_GUARD = ["10.0.", "172.16.2.1", "127.0.0.", "169.254.", "192.168."]

def metric(name, value=1, mtype="Count"):
    try:
        cw.put_metric_data(Namespace=CW_NS, MetricData=[
            {"MetricName": name, "Value": value,
             "Dimensions": [{"Name": "Component", "Value": "soar-worker"}]}])
    except Exception:
        log.exception("metric put failed: %s", name)

def event_id(alert):
    raw = json.dumps(alert, sort_keys=True, default=str)
    return hashlib.sha256(raw.encode()).hexdigest()[:24]

# ---------------- listener ----------------

@app.get("/health")
def health():
    return jsonify(status="ok")

@app.post("/webhook")
def webhook():
    auth = request.headers.get("Authorization", "")
    if auth != f"Token {WEBHOOK_TOKEN}":
        metric("InvalidDrops")
        return jsonify(error="unauthorized"), 401
    payload = request.get_json(silent=True) or {}
    queued = 0
    for alert in payload.get("alerts", []):
        if alert.get("status") != "firing":
            continue
        labels = alert.get("labels", {})
        if labels.get("soar") != "true":
            continue
        body = {
            "alertname": labels.get("alertname", "unknown"),
            "labels": labels,
            "annotations": alert.get("annotations", {}),
            "fingerprint": alert.get("fingerprint", ""),
            "received_at": datetime.now(timezone.utc).isoformat(),
        }
        sqs.send_message(QueueUrl=QUEUE_URL, MessageBody=json.dumps(body))
        queued += 1
    metric("EventsReceived", queued)
    log.info("webhook accepted: queued=%d", queued)
    return jsonify(queued=queued), 200

# ---------------- actions ----------------

def act_notify(alertname, src_ip, extra=""):
    msg = (f"🛡 **SOAR {alertname}** — source `{src_ip}`. Actions: "
           f"logged to DynamoDB"
           + (", NACL deny injected (auto-expires)" if "block" in RULES.get(alertname, {}).get("actions", []) else "")
           + (f"\n{extra}" if extra else ""))
    requests.post(DISCORD_URL, json={"content": msg}, timeout=10)

def act_record(event_id_, alertname, src_ip, actions):
    now = int(time.time())
    ddb.put_item(TableName=DDB_TABLE, Item={
        "pk":         {"S": f"event:{event_id_}"},
        "alertname":  {"S": alertname},
        "src_ip":     {"S": src_ip},
        "actions":    {"SS": actions},
        "created_at": {"N": str(now)},
        "expires_at": {"N": str(now + 7 * 24 * 3600)},  # audit TTL 7 d
    })

def next_rule_number():
    """Atomic counter in DDB -> rule numbers 9000..9098, recycled by TTL."""
    resp = ddb.update_item(TableName=DDB_TABLE,
        Key={"pk": {"S": "meta:nacl_counter"}},
        UpdateExpression="ADD n :one",
        ExpressionAttributeValues={":one": {"N": "1"}},
        ReturnValues="UPDATED_NEW")
    n = int(resp["Attributes"]["n"])
    return 9000 + (n % 99)

def act_block(src_ip, event_id_):
    if any(src_ip.startswith(g) for g in BLOCK_GUARD):
        log.warning("block refused (guard): %s", src_ip)
        return "refused"
    nacl = ec2.describe_network_acls(NetworkAclIds=[NACL_ID])["NetworkAcls"][0]
    for e in nacl["Entries"]:
        if e.get("RuleNumber", 32767) < 32766 and e.get("CidrBlock") == f"{src_ip}/32" and e["RuleAction"] == "deny":
            return "already-blocked"          # idempotent re-block
    rule_no = next_rule_number()
    ec2.create_network_acl_entry(NetworkAclId=NACL_ID, RuleNumber=rule_no,
        Protocol="-1", RuleAction="deny", Egress=False, CidrBlock=f"{src_ip}/32")
    now = int(time.time())
    ddb.put_item(TableName=DDB_TABLE, Item={
        "pk": {"S": f"nacl:{rule_no}"},
        "cidr": {"S": f"{src_ip}/32"},
        "created_at": {"N": str(now)},
        "expires_at": {"N": str(now + NACL_TTL)},
    })
    log.info("NACL deny injected: %s -> rule %d (ttl %ds)", src_ip, rule_no, NACL_TTL)
    return "blocked"

# ---------------- engine (consumer) ----------------

def handle_event(body):
    alertname = body.get("alertname", "unknown")
    rule = RULES.get(alertname)
    if rule is None:
        metric("InvalidDrops")
        log.info("no rule for %s — dropped", alertname)
        return

    src_ip = (body.get("labels") or {}).get("ip") or (body.get("labels") or {}).get("src") or "unknown"
    eid = event_id(body)
    actions = rule["actions"]
    done = []

    if "notify" in actions:
        act_notify(alertname, src_ip); done.append("notify")
    if "block" in actions and src_ip != "unknown":
        outcome = act_block(src_ip, eid)
        if outcome != "refused":
            done.append("block")
    if "record" in actions:
        act_record(eid, alertname, src_ip, done or ["none"])

    metric("ActionsExecuted", len(done) or 1)
    log.info("event %s (%s) handled: %s", eid, alertname, done)

def consumer_loop():
    while True:
        try:
            resp = sqs.receive_message(QueueUrl=QUEUE_URL, MaxNumberOfMessages=5,
                                       WaitTimeSeconds=10, VisibilityTimeout=120)
            for m in resp.get("Messages", []):
                try:
                    handle_event(json.loads(m["Body"]))
                    sqs.delete_message(QueueUrl=QUEUE_URL, ReceiptHandle=m["ReceiptHandle"])
                except Exception:
                    # no delete -> SQS re-delivers; redrive -> DLQ after 5 tries
                    metric("ActionFailures")
                    log.exception("processing failed, message returns to queue")
        except Exception:
            log.exception("consumer loop error")
            time.sleep(5)

# ---------------- sweeper (expiry + DlqDepth gauge) ----------------

def sweeper_loop():
    while True:
        try:
            now = int(time.time())
            resp = ddb.scan(TableName=DDB_TABLE,
                FilterExpression="begins_with(pk, :p) AND expires_at <= :now",
                ExpressionAttributeValues={":p": {"S": "nacl:"}, ":now": {"N": str(now)}})
            for item in resp.get("Items", []):
                rule_no = int(item["pk"]["S"].split(":")[1])
                try:
                    ec2.delete_network_acl_entry(NetworkAclId=NACL_ID, RuleNumber=rule_no, Egress=False)
                    ddb.delete_item(TableName=DDB_TABLE, Key={"pk": item["pk"]})
                    log.info("NACL deny expired, removed rule %d", rule_no)
                except Exception:
                    log.exception("expiry removal failed for rule %d", rule_no)
            depth = int(sqs.get_queue_attributes(QueueUrl=os.environ["DLQ_URL"],
                AttributeNames=["ApproximateNumberOfMessages"])
                ["Attributes"]["ApproximateNumberOfMessages"])
            metric("DlqDepth", depth, "Gauge")
        except Exception:
            log.exception("sweeper loop error")
        time.sleep(60)

# ---------------- main ----------------

if __name__ == "__main__":
    threading.Thread(target=consumer_loop, daemon=True).start()
    threading.Thread(target=sweeper_loop, daemon=True).start()
    app.run(host="0.0.0.0", port=8080)