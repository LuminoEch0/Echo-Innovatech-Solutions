# Echo-Innovatech-Solutions
This is the case study 1 project about for the Innovatech Solutions

This is the SSH command to use 
ssh -i ~/.ssh/aws-lab ec2-user@<vpn-ip>

# Runner-created stack's public IPs + private IPs:
aws ec2 describe-instances --region eu-central-1 --filters "Name=instance-state-name,Values=[running]" --query "Reservations[].Instances[].[Tags[?Key=='Name'].Value|[0],PrivateIpAddress,PublicIpAddress]" --output table

# New ALB DNS:
aws elbv2 describe-load-balancers --region eu-central-1 --query "LoadBalancers[].DNSName" --output text