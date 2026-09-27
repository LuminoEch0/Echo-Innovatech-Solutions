# Echo-Innovatech-Solutions
This is the case study 1 project about for the Innovatech Solutions

The following are the steps that are taken 

This is the SSH command to use 
ssh -i ~/.ssh/aws-lab ec2-user@<vpn-ip>

# Runner-created stack's public IPs + private IPs:
aws ec2 describe-instances --region eu-central-1 --filters "Name=instance-state-name,Values=[running]" --query "Reservations[].Instances[].[Tags[?Key=='Name'].Value|[0],PrivateIpAddress,PublicIpAddress]" --output table

# New ALB DNS:
aws elbv2 describe-load-balancers --region eu-central-1 --query "LoadBalancers[].DNSName" --output text

# 1. SSH to the NEW VPN public IP:
ssh -A -i ~/.ssh/aws-lab ec2-user@<NEW_PUBLIC_IP>

# 2. Verify user data finished cleanly this time:
sudo tail -5 /var/log/cloud-init-output.log     # no usage-text errors
sudo docker ps                                   # openvpn container Up

# 3. Issue + export your client cert (fresh PKI):
sudo docker run -v ovpn-data:/etc/openvpn --rm -e EASYRSA_BATCH=1 \
  kylemanna/openvpn easyrsa build-client-full mylaptop nopass
sudo docker run -v ovpn-data:/etc/openvpn --rm \
  kylemanna/openvpn ovpn_getclient mylaptop > /tmp/mylaptop.ovpn
exit

# 4. From laptop, download it:
scp -i C:\Users\jacks\.ssh\aws-lab ec2-user@<NEW_PUBLIC_IP>:/tmp/mylaptop.ovpn .

Because of using the -A tag before, the private key is saved by an agent and could be called directly from the first ssh instance to the second and so on still using the -A tag
example: Connecting to moinitornig machine: 

ssh -A 10.0.30.x

NB: if it doesn't work (Permission denied), the ssh agent did not run successfully and this happens often so run the followoing code:

exit
ssh-add -l     >> "Could not open a connection to your authentication agent." >> Then run the code below

eval $(ssh-agent)
ssh-add ~/.ssh/aws-lab
ssh-add -l     

Then try the ssh chain again
ssh -A -i ~/.ssh/aws-lab ec2-user@<NEW_PUBLIC_IP>
ssh -A ec2-user@<NEW_PRIVATE_IP>