# 1. Fetch the latest official Amazon Linux 2023 AMI dynamically
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# 2. Launch Template: Installs Docker & runs containerized web app with auto-restart
resource "aws_launch_template" "web_lt" {
  name_prefix   = "web-server-template-"
  image_id = "ami-06121aa3085b6f918"
  instance_type = "t3.micro"
  key_name      = aws_key_pair.management_key.key_name  

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.web_sg.id]
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              # Doesn't requre updating the system as Amazon Linux 2023 is already up-to-date
              dnf install -y docker
              dnf install -y docker nmap-ncat
              systemctl start docker
              systemctl enable docker

              # ── DB connection info injected by Terraform ──
              # (endpoint comes from the RDS resource reference)
              cat <<'APPENV' > /opt/app.env
              DB_HOST=${aws_db_instance.postgres.address}
              DB_PORT=5432
              DB_NAME=appdb
              DB_USER=dbadmin
              DB_PASSWORD=${random_password.db.result}
              APPENV

              # ── The app: Flask + psycopg, serves data from Postgres ──
              mkdir -p /opt/app
              cat <<'PYAPP' > /opt/app/app.py
              import os, psycopg2
              from flask import Flask, jsonify
              app = Flask(__name__)

              def get_conn():
                  return psycopg2.connect(
                      host=os.environ["DB_HOST"], port=os.environ["DB_PORT"],
                      dbname=os.environ["DB_NAME"], user=os.environ["DB_USER"],
                      password=os.environ["DB_PASSWORD"])

              def seed_if_empty():
                  """Creates table and idempotently inserts demo rows (race-safe)."""
                  conn = get_conn()
                  cur = conn.cursor()
                  cur.execute("""CREATE TABLE IF NOT EXISTS team_members (
                                 id serial primary key,
                                 name text UNIQUE,
                                 role text)""")
                  cur.execute("""INSERT INTO team_members (name, role) VALUES
                                 ('Alice', 'Backend Engineer'),
                                 ('Bob', 'Frontend Engineer'),
                                 ('Carol', 'DevOps Engineer')
                                 ON CONFLICT (name) DO NOTHING""")
                  conn.commit()
                  conn.close()

              seed_if_empty()   # runs once at container start; safe if both instances race

              @app.route("/")
              def index():
                  conn = get_conn(); cur = conn.cursor()
                  cur.execute("SELECT id, name, role FROM team_members ORDER BY id")
                  rows = cur.fetchall(); conn.close()
                  return "<h1>Team (live from RDS Postgres)</h1>" + "".join(
                      f"<p>{r[0]}. <b>{r[1]}</b> — {r[2]}</p>" for r in rows)

              @app.route("/api/members")
              def api():
                  conn = get_conn(); cur = conn.cursor()
                  cur.execute("SELECT id, name, role FROM team_members ORDER BY id")
                  rows = [{"id": r[0], "name": r[1], "role": r[2]} for r in cur.fetchall()]
                  conn.close()
                  return jsonify(rows)

              # Only runs when executed directly (python app.py).
              # Under gunicorn this block is skipped — gunicorn imports `app` instead.
              if __name__ == "__main__":
                  app.run(host="0.0.0.0", port=80)
              PYAPP

              cat <<'REQS' > /opt/app/requirements.txt
              flask
              psycopg2-binary
              REQS

              # ── NGINX config: reverse proxy on :80 → gunicorn on :8080 ──
              cat <<'NGINXCONF' > /opt/app/nginx.conf
              server {
                  listen 80;
                  location / {
                      proxy_pass http://127.0.0.1:8080;
                      proxy_set_header Host $host;
                      proxy_set_header X-Real-IP $remote_addr;
                      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                  }
              }
              NGINXCONF

              # ── Wait for RDS to be fully available before first connect ──
              until nc -z ${aws_db_instance.postgres.address} 5432 2>/dev/null; do
                echo "Waiting for database..."; sleep 10
              done

              # ── App server: gunicorn (2 workers × 2 threads) on :8080 ──
              docker run -d --name app-server --restart always \
                --network host \
                --env-file /opt/app.env \
                -v /opt/app:/app:ro \
                -w /app \
                python:3.12-slim \
                sh -c "pip install -r requirements.txt gunicorn && \
                       gunicorn -b 127.0.0.1:8080 --workers 2 --threads 2 app:app"

              # ── Web server: NGINX on :80 in front of gunicorn (what the ALB talks to) ──
              docker run -d --name nginx --restart always \
                --network host \
                -v /opt/app/nginx.conf:/etc/nginx/conf.d/default.conf:ro \
                nginx:1.27-alpine

              # ── Node Exporter (keep this — monitoring depends on it) ──
              docker run -d \
                --name node-exporter \
                --restart always \
                --pid host \
                --network host \
                prom/node-exporter:v1.8.2
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "asg-web-server"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# 3. Auto Scaling Group across Private Compute Subnets AZ-1A and AZ-1B
resource "aws_autoscaling_group" "web_asg" {
  name_prefix         = "web-asg-"
  vpc_zone_identifier = [
    aws_subnet.private_web_1a.id,
    aws_subnet.private_web_1b.id
  ]

  target_group_arns = [aws_lb_target_group.web_tg.arn]
  health_check_type = "ELB" # Uses ALB target group health checks and not EC2 instance status checks

  min_size         = 2
  max_size         = 4
  desired_capacity = 2

  launch_template {
    id      = aws_launch_template.web_lt.id
    version = "$Latest"
  }

  health_check_grace_period = 300

  lifecycle {
    create_before_destroy = true
  }
}

# 4. Target Tracking Scaling Policy: Dynamically scales based on average CPU utilization
resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "web-asg-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.web_asg.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }
}