# Install lsb
which sudo || apt update;apt install -y sudo
sudo apt update && sudo apt install lsb-release gpg curl wget -y

# Add cloudflare gpg key
curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | sudo gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg

# Add this repo to your apt repositories
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/cloudflare-client.list

# Install
sudo apt update && sudo apt install cloudflare-warp -y

while :;do systemctl start warp-svc.service && break;sleep 0.1;done
yes y | warp-cli registration delete
warp-cli registration new

if [ "$1" == "4" ]; then
	# ipv4-only VPS
	warp-cli add-excluded-route 0.0.0.0/0
	echo "precedence ::ffff:0:0/96 100" >>/etc/gai.conf
elif [ "$1" == "6" ]; then
	# ipv6-only VPS
	warp-cli add-excluded-route ::0/0
	rm /etc/gai.conf
fi


warp-cli mode warp
warp-cli connect
