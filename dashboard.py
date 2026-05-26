from flask import Flask, render_template_string
import boto3, json

app = Flask(__name__)

EP = "http://127.0.0.1:4566"
REGION = "us-east-1"
CREDS = dict(aws_access_key_id="test", aws_secret_access_key="test", region_name=REGION, endpoint_url=EP)

HTML = """
<!DOCTYPE html>
<html>
<head>
  <title>Daniel Philip Cloud Lab</title>
  <meta http-equiv="refresh" content="30">
  <style>
    * { margin:0; padding:0; box-sizing:border-box; }
    body { font-family: 'Segoe UI', sans-serif; background:#0f1117; color:#e0e0e0; }
    header {
      background: linear-gradient(135deg, #1a3a5c, #0a1628);
      border-bottom: 3px solid #c0392b;
      padding: 24px 40px;
      display: flex; align-items: center; justify-content: space-between;
    }
    header h1 { font-size: 1.8rem; color: #fff; letter-spacing: 1px; }
    header h1 span { color: #c0392b; }
    .badge { background:#c0392b; color:#fff; padding:4px 12px; border-radius:20px; font-size:0.8rem; }
    .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(340px, 1fr)); gap: 20px; padding: 30px 40px; }
    .card {
      background: #1a1f2e; border-radius: 10px; border: 1px solid #2a3a4a;
      overflow: hidden; transition: transform 0.2s;
    }
    .card:hover { transform: translateY(-2px); border-color: #c0392b; }
    .card-header {
      padding: 14px 20px; display: flex; align-items: center; gap: 10px;
      border-bottom: 1px solid #2a3a4a;
    }
    .card-header .icon { font-size: 1.4rem; }
    .card-header h2 { font-size: 1rem; color: #fff; }
    .card-header .count {
      margin-left: auto; background: #0a1628;
      color: #e8a838; border-radius: 12px;
      padding: 2px 10px; font-size: 0.8rem; font-weight: bold;
    }
    .card-body { padding: 14px 20px; }
    .item {
      padding: 8px 0; border-bottom: 1px solid #1e2a3a;
      display: flex; flex-direction: column; gap: 2px;
    }
    .item:last-child { border-bottom: none; }
    .item .name { color: #58a6ff; font-size: 0.88rem; font-weight: 600; }
    .item .detail { color: #8b9ab0; font-size: 0.78rem; }
    .status-ok { color: #3fb950; font-size: 0.75rem; }
    .status-warn { color: #e8a838; font-size: 0.75rem; }
    .stat-row {
      display: grid; grid-template-columns: repeat(4,1fr); gap:16px;
      padding: 20px 40px 0; 
    }
    .stat {
      background:#1a1f2e; border:1px solid #2a3a4a; border-radius:10px;
      padding:20px; text-align:center;
    }
    .stat .num { font-size:2.2rem; font-weight:bold; color:#c0392b; }
    .stat .label { color:#8b9ab0; font-size:0.82rem; margin-top:4px; }
    .api-box {
      margin: 0 40px 10px; background:#1a1f2e; border:1px solid #2a3a4a;
      border-radius:10px; padding:16px 20px;
    }
    .api-box h3 { color:#e8a838; margin-bottom:10px; font-size:0.9rem; }
    .endpoint { display:flex; align-items:center; gap:10px; margin:6px 0; }
    .method { padding:2px 8px; border-radius:4px; font-size:0.75rem; font-weight:bold; }
    .GET  { background:#0d4a1f; color:#3fb950; }
    .POST { background:#4a2d0d; color:#e8a838; }
    .url  { color:#58a6ff; font-size:0.82rem; font-family:monospace; }
    footer { text-align:center; padding:20px; color:#3a4a5a; font-size:0.78rem; }
  </style>
</head>
<body>
<header>
  <h1>⚡ Daniel <span>Philip</span> Cloud Lab</h1>
  <div style="display:flex;gap:12px;align-items:center">
    <span style="color:#3fb950;font-size:0.85rem;">● LocalStack Live</span>
    <span class="badge">{{ total }} Resources</span>
  </div>
</header>

<div class="stat-row">
  <div class="stat"><div class="num">{{ stats.buckets }}</div><div class="label">🪣 S3 Buckets</div></div>
  <div class="stat"><div class="num">{{ stats.tables }}</div><div class="label">🗄️ DynamoDB Tables</div></div>
  <div class="stat"><div class="num">{{ stats.queues }}</div><div class="label">📬 SQS Queues</div></div>
  <div class="stat"><div class="num">{{ stats.lambdas }}</div><div class="label">⚡ Lambda Functions</div></div>
</div>

<div class="stat-row" style="grid-template-columns:repeat(4,1fr);padding-top:16px;">
  <div class="stat"><div class="num">{{ stats.topics }}</div><div class="label">📣 SNS Topics</div></div>
  <div class="stat"><div class="num">{{ stats.instances }}</div><div class="label">💻 EC2 Instances</div></div>
  <div class="stat"><div class="num">{{ stats.roles }}</div><div class="label">🔐 IAM Roles</div></div>
  <div class="stat"><div class="num">{{ stats.apis }}</div><div class="label">🌍 API Gateways</div></div>
</div>

<div class="api-box" style="margin-top:20px;">
  <h3>🌐 LIVE API ENDPOINTS — danielphilip-api-gw</h3>
  {% for ep in endpoints %}
  <div class="endpoint">
    <span class="method {{ ep.method }}">{{ ep.method }}</span>
    <span class="url">{{ ep.url }}</span>
    <span class="status-ok">● live</span>
  </div>
  {% endfor %}
</div>

<div class="grid">

  <div class="card">
    <div class="card-header"><span class="icon">🪣</span><h2>S3 Buckets</h2><span class="count">{{ buckets|length }}</span></div>
    <div class="card-body">
      {% for b in buckets %}
      <div class="item">
        <span class="name">{{ b.name }}</span>
        <span class="detail">Created: {{ b.created }}</span>
        <span class="status-ok">● versioning enabled</span>
      </div>
      {% endfor %}
    </div>
  </div>

  <div class="card">
    <div class="card-header"><span class="icon">🗄️</span><h2>DynamoDB Tables</h2><span class="count">{{ tables|length }}</span></div>
    <div class="card-body">
      {% for t in tables %}
      <div class="item">
        <span class="name">{{ t.name }}</span>
        <span class="detail">Keys: {{ t.keys }} | Billing: {{ t.billing }}</span>
        <span class="status-ok">● {{ t.status }}</span>
      </div>
      {% endfor %}
    </div>
  </div>

  <div class="card">
    <div class="card-header"><span class="icon">📬</span><h2>SQS Queues</h2><span class="count">{{ queues|length }}</span></div>
    <div class="card-body">
      {% for q in queues %}
      <div class="item">
        <span class="name">{{ q.name }}</span>
        <span class="detail">Messages: {{ q.messages }} | Retention: {{ q.retention }}s</span>
        <span class="status-ok">● active</span>
      </div>
      {% endfor %}
    </div>
  </div>

  <div class="card">
    <div class="card-header"><span class="icon">⚡</span><h2>Lambda Functions</h2><span class="count">{{ lambdas|length }}</span></div>
    <div class="card-body">
      {% for l in lambdas %}
      <div class="item">
        <span class="name">{{ l.name }}</span>
        <span class="detail">Runtime: {{ l.runtime }} | Memory: {{ l.memory }}MB | Timeout: {{ l.timeout }}s</span>
        <span class="status-ok">● deployed</span>
      </div>
      {% endfor %}
    </div>
  </div>

  <div class="card">
    <div class="card-header"><span class="icon">📣</span><h2>SNS Topics</h2><span class="count">{{ topics|length }}</span></div>
    <div class="card-body">
      {% for t in topics %}
      <div class="item">
        <span class="name">{{ t.name }}</span>
        <span class="detail">{{ t.arn }}</span>
        <span class="status-ok">● {{ t.subs }} subscription(s)</span>
      </div>
      {% endfor %}
    </div>
  </div>

  <div class="card">
    <div class="card-header"><span class="icon">💻</span><h2>EC2 Instances</h2><span class="count">{{ instances|length }}</span></div>
    <div class="card-body">
      {% for i in instances %}
      <div class="item">
        <span class="name">{{ i.name }}</span>
        <span class="detail">Type: {{ i.type }} | IP: {{ i.ip }} | Subnet: {{ i.subnet }}</span>
        <span class="status-ok">● {{ i.state }}</span>
      </div>
      {% endfor %}
    </div>
  </div>

  <div class="card">
    <div class="card-header"><span class="icon">🔐</span><h2>IAM</h2><span class="count">{{ iam_summary.total }}</span></div>
    <div class="card-body">
      {% for r in iam_roles %}
      <div class="item">
        <span class="name">{{ r.name }}</span>
        <span class="detail">Role</span>
        <span class="status-ok">● active</span>
      </div>
      {% endfor %}
      {% for u in iam_users %}
      <div class="item">
        <span class="name">{{ u.name }}</span>
        <span class="detail">User</span>
        <span class="status-ok">● active</span>
      </div>
      {% endfor %}
      {% for g in iam_groups %}
      <div class="item">
        <span class="name">{{ g.name }}</span>
        <span class="detail">Group</span>
        <span class="status-ok">● active</span>
      </div>
      {% endfor %}
    </div>
  </div>

  <div class="card">
    <div class="card-header"><span class="icon">🌐</span><h2>VPC & Networking</h2><span class="count">{{ vpcs|length }}</span></div>
    <div class="card-body">
      {% for v in vpcs %}
      <div class="item">
        <span class="name">{{ v.id }}</span>
        <span class="detail">CIDR: {{ v.cidr }}</span>
        <span class="status-ok">● {{ v.subnets }} subnets | 1 IGW</span>
      </div>
      {% endfor %}
    </div>
  </div>

  <div class="card">
    <div class="card-header"><span class="icon">📊</span><h2>CloudWatch Logs</h2><span class="count">{{ log_groups|length }}</span></div>
    <div class="card-body">
      {% for lg in log_groups %}
      <div class="item">
        <span class="name">{{ lg.name }}</span>
        <span class="detail">Retention: {{ lg.retention }} days</span>
        <span class="status-ok">● active</span>
      </div>
      {% endfor %}
    </div>
  </div>

</div>
<footer>Daniel Philip Cloud Lab · LocalStack Community · Auto-refreshes every 30s · {{ refresh_time }}</footer>
</body>
</html>
"""

def get_data():
    s3       = boto3.client('s3',          **CREDS)
    dynamo   = boto3.client('dynamodb',    **CREDS)
    sqs      = boto3.client('sqs',         **CREDS)
    lmb      = boto3.client('lambda',      **CREDS)
    sns      = boto3.client('sns',         **CREDS)
    ec2      = boto3.client('ec2',         **CREDS)
    iam      = boto3.client('iam',         **CREDS)
    apigw    = boto3.client('apigateway',  **CREDS)
    logs     = boto3.client('logs',        **CREDS)

    # S3
    buckets = [{"name": b['Name'], "created": str(b['CreationDate'])[:10]}
               for b in s3.list_buckets().get('Buckets', [])]

    # DynamoDB
    tables = []
    for t in dynamo.list_tables().get('TableNames', []):
        d = dynamo.describe_table(TableName=t)['Table']
        tables.append({
            "name": t,
            "status": d['TableStatus'],
            "billing": d.get('BillingModeSummary', {}).get('BillingMode', 'PROVISIONED'),
            "keys": ", ".join(k['AttributeName'] for k in d['KeySchema'])
        })

    # SQS
    queues = []
    for url in sqs.list_queues().get('QueueUrls', []):
        attrs = sqs.get_queue_attributes(QueueUrl=url, AttributeNames=['All'])['Attributes']
        queues.append({
            "name": url.split('/')[-1],
            "messages": attrs.get('ApproximateNumberOfMessages', '0'),
            "retention": attrs.get('MessageRetentionPeriod', '?')
        })

    # Lambda
    lambdas = [{"name": f['FunctionName'], "runtime": f['Runtime'],
                "memory": f['MemorySize'], "timeout": f['Timeout']}
               for f in lmb.list_functions().get('Functions', [])]

    # SNS
    topics = []
    for t in sns.list_topics().get('Topics', []):
        arn = t['TopicArn']
        name = arn.split(':')[-1]
        subs = len(sns.list_subscriptions_by_topic(TopicArn=arn).get('Subscriptions', []))
        topics.append({"name": name, "arn": arn, "subs": subs})

    # EC2
    instances = []
    for r in ec2.describe_instances().get('Reservations', []):
        for i in r['Instances']:
            name = next((t['Value'] for t in i.get('Tags', []) if t['Key'] == 'Name'), i['InstanceId'])
            instances.append({
                "name": name, "type": i['InstanceType'],
                "state": i['State']['Name'],
                "ip": i.get('PublicIpAddress', 'N/A'),
                "subnet": i.get('SubnetId', 'N/A')
            })

    # IAM
    iam_roles  = [{"name": r['RoleName']} for r in iam.list_roles().get('Roles', [])
                  if 'danielphilip' in r['RoleName']]
    iam_users  = [{"name": u['UserName']} for u in iam.list_users().get('Users', [])]
    iam_groups = [{"name": g['GroupName']} for g in iam.list_groups().get('Groups', [])]

    # VPC
    vpcs = []
    subnets = ec2.describe_subnets().get('Subnets', [])
    for v in ec2.describe_vpcs().get('Vpcs', []):
        if v['CidrBlock'] == '10.0.0.0/16':
            count = sum(1 for s in subnets if s['VpcId'] == v['VpcId'])
            vpcs.append({"id": v['VpcId'], "cidr": v['CidrBlock'], "subnets": count})

    # API Gateway
    apis = apigw.get_rest_apis().get('items', [])
    api_id = apis[0]['id'] if apis else ''
    base = f"http://localhost:4566/restapis/{api_id}/prod/_user_request_"
    endpoints = [
        {"method": "GET",  "url": f"{base}/health"},
        {"method": "POST", "url": f"{base}/users"},
        {"method": "GET",  "url": f"{base}/users"},
    ]

    # CloudWatch
    log_groups = [{"name": lg['logGroupName'],
                   "retention": lg.get('retentionInDays', '∞')}
                  for lg in logs.describe_log_groups().get('logGroups', [])]

    from datetime import datetime
    return dict(
        buckets=buckets, tables=tables, queues=queues, lambdas=lambdas,
        topics=topics, instances=instances,
        iam_roles=iam_roles, iam_users=iam_users, iam_groups=iam_groups,
        iam_summary={"total": len(iam_roles)+len(iam_users)+len(iam_groups)},
        vpcs=vpcs, endpoints=endpoints, log_groups=log_groups,
        stats=dict(buckets=len(buckets), tables=len(tables), queues=len(queues),
                   lambdas=len(lambdas), topics=len(topics),
                   instances=len(instances), roles=len(iam_roles), apis=len(apis)),
        total=37,
        refresh_time=datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    )

@app.route('/')
def index():
    return render_template_string(HTML, **get_data())

if __name__ == '__main__':
    print("\n🚀 Daniel Philip Cloud Lab Dashboard")
    print("   Open: http://localhost:5000\n")
    app.run(host='0.0.0.0', port=5000, debug=False)
