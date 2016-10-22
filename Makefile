# Create an access point on the same wifi card using dnsmasq and hostapd with
# interface named $(AP_IN) and subnet 192.168.20.0/24
#set -x
#set -e

AP_IN=ap0
WIFI_IN=wlp2s0 # wifi interface where to add ap0 interface
WAN_IN=wlp2s0 # wan interface where lan network to be redirected
AP_IP=192.168.20.1
AP_NET=$(AP_IP)/24
PWD=$(shell pwd)

default: clean lan sysctl firewall squid proxy_redirect dns samba ap clean

check_root:
	[ "$(shell id -u)" == "0" ]

clean:
	iptables -F
	iptables -t nat -F
	iptables -t mangle -F
	iptables -X
	iptables -t nat -X
	iptables -t nat -D POSTROUTING -o $(WAN_IN) -j MASQUERADE || true
	iptables -D FORWARD -i $(AP_IN)   -s 192.168.20.0/24 -j ACCEPT || true
	iptables -D FORWARD -i $(WAN_IN) -d 192.168.20.0/24 -j ACCEPT || true
	iptables -A INPUT -i lo -j ACCEPT
	iptables -A OUTPUT -o lo -j ACCEPT
	systemctl stop smbd nmbd
	kill -9 $(shell cat /var/run/dnsmasq-$(AP_IN).pid) || true
	kill $(shell cat /var/run/git-daemon-$(AP_IN).pid) || true
	kill $(shell cat /var/run/squid-$(AP_IN).pid) || true

lan:
	iw dev $(AP_IN) del 2>/dev/null || true
	iw dev $(WIFI_IN) interface add $(AP_IN) type __ap ## managed
	ip link set dev $(AP_IN) address 5a:9b:69:7c:b2:de
	ip link set up dev $(AP_IN)
	ip addr add $(AP_IP)/24 broadcast 192.168.20.255 dev $(AP_IN)

sysctl:
	# Controls IP packet forwarding
	sysctl -w net.ipv4.ip_forward=1
	# Controls source route verification
	sysctl -w net.ipv4.conf.default.rp_filter=0
	sysctl -w net.ipv4.conf.lo.rp_filter=0
	# Do not accept source routing
	sysctl -w net.ipv4.conf.default.accept_source_route=0

firewall:
	iptables -I INPUT -p tcp -i $(AP_IN) -s $(AP_NET) -d $(AP_NET) -m tcp --dport 22   -j ACCEPT # ssh
	iptables -I INPUT -p tcp -i $(AP_IN) -s $(AP_NET) -d $(AP_NET) -m tcp --dport 53   -j ACCEPT
	iptables -I INPUT -p udp -i $(AP_IN) -s $(AP_NET) -d $(AP_NET) -m udp --dport 53   -j ACCEPT
	iptables -I INPUT -p tcp -i $(AP_IN) -s $(AP_NET) -d $(AP_NET) -m tcp --dport 67   -j ACCEPT
	iptables -I INPUT -p udp -i $(AP_IN) -s $(AP_NET) -d $(AP_NET) -m udp --dport 67   -j ACCEPT
	iptables -I INPUT -p tcp -i $(AP_IN) -s $(AP_NET) -d $(AP_NET) -m tcp --dport 80   -j ACCEPT # http
	iptables -I INPUT -p tcp -i $(AP_IN) -s $(AP_NET) -d $(AP_NET) -m tcp --dport 137  -j ACCEPT # nmbd
	iptables -I INPUT -p tcp -i $(AP_IN) -s $(AP_NET) -d $(AP_NET) -m tcp --dport 138  -j ACCEPT # nmbd
	iptables -I INPUT -p tcp -i $(AP_IN) -s $(AP_NET) -d $(AP_NET) -m tcp --dport 139  -j ACCEPT # smbd
	iptables -I INPUT -p tcp -i $(AP_IN) -s $(AP_NET) -d $(AP_NET) -m tcp --dport 445  -j ACCEPT # smbd
	iptables -I INPUT -p tcp -i $(AP_IN) -s $(AP_NET) -d $(AP_NET) -m tcp --dport 3030 -j ACCEPT # squid
	iptables -I INPUT -p tcp -i $(AP_IN) -s $(AP_NET) -d $(AP_NET) -m tcp --dport 3031 -j ACCEPT # squid
	iptables -I INPUT -p tcp -i $(AP_IN) -s $(AP_NET) -d $(AP_NET) -m tcp --dport 8080 -j ACCEPT # http-alt
	iptables -I INPUT -p tcp -i $(AP_IN) -s $(AP_NET) -d $(AP_NET) -m tcp --dport 9418 -j ACCEPT # git-daemon
	iptables -A INPUT -i $(AP_IN) -m state --state RELATED,ESTABLISHED -j ACCEPT

proxy_none:
	### Forward without passing by squid
	iptables -t nat -I POSTROUTING -o $(WAN_IN) -j MASQUERADE
	iptables -I FORWARD -i $(AP_IN)   -s 192.168.20.0/24 -j ACCEPT
	iptables -I FORWARD -i $(WAN_IN)  -d 192.168.20.0/24 -j ACCEPT
	#iptables -P OUTPUT ACCEPT

# NO
tproxy:
	iptables -t nat -A PREROUTING  -i $(AP_IN) -s $(AP_NET) -d $(AP_NET) -p tcp --dport 80  -j ACCEPT
	iptables -t nat -A PREROUTING  -i $(AP_IN) -s $(AP_NET) -d $(AP_NET) -p tcp --dport 443 -j ACCEPT
	iptables -t tproxy -A PREROUTING -i $(AP_IN) -p tcp -m tcp --dport 80  -j TPROXY --on-port 3032
	iptables -t tproxy -A PREROUTING -i $(AP_IN) -p tcp -m tcp --dport 443 -j TPROXY --on-port 3032

# YES
proxy_redirect:
	iptables -I INPUT -p tcp -i $(AP_IN) -s $(AP_NET) -d $(AP_NET) -m tcp --dport 80   -j ACCEPT # http
	iptables -t nat -A PREROUTING  -i $(AP_IN) -s $(AP_NET) -d $(AP_NET) -p tcp --dport 80 -j ACCEPT
	#iptables -t nat -A PREROUTING  -i $(AP_IN) -s $(AP_NET) -d $(AP_NET) -p tcp --dport 443 -j ACCEPT
	iptables -t nat -A PREROUTING -i $(AP_IN) -p tcp -m tcp --dport 80  -j REDIRECT --to-port 3030
	iptables -A FORWARD -p tcp -m tcp --dport 443 -j REJECT --reject-with icmp-port-unreachable
	#iptables -t nat -A PREROUTING -i $(AP_IN) -p tcp -m tcp --dport 443 -j REDIRECT --to-port 3030
	#iptables -I FORWARD -i $(AP_IN) -o $(AP_IN) -s $(AP_NET) -d $(AP_IP) -p tcp --dport 3030 -j ACCEPT
	iptables -t nat -A POSTROUTING -o $(WAN_IN) -j MASQUERADE
	#iptables -t mangle -A PREROUTING -p tcp --dport 3030 -j DROP
	#iptables -P FORWARD DROP
	#iptables -P OUTPUT ACCEPT

# NO
proxy_dnat_snat:
	iptables -t nat -A PREROUTING  -i $(AP_IN) -s $(AP_NET) -d $(AP_NET) -p tcp --dport 80 -j ACCEPT
	iptables -t nat -A PREROUTING  -i $(AP_IN) -s $(AP_NET) -d $(AP_NET) -p tcp --dport 443 -j ACCEPT
	iptables -t nat -A PREROUTING -i $(AP_IN) -p tcp --dport 80  -j DNAT --to-destination $(AP_IP):3030
	iptables -t nat -A PREROUTING -i $(AP_IN) -p tcp --dport 443 -j DNAT --to-destination $(AP_IP):3030
	iptables -t nat -I POSTROUTING -o $(AP_IN) -s $(AP_NET) -d $(AP_IP) -p tcp -j SNAT --to $(AP_IP)
	iptables -t nat -I PREROUTING  -i $(AP_IN) -d $(AP_IP)/24 -j ACCEPT
	iptables -t nat -I PREROUTING  -i $(AP_IN) -d 10.0.0.0/13 -j ACCEPT
	iptables -I FORWARD -i $(AP_IN) -o $(AP_IN) -s $(AP_NET) -d $(AP_IP) -p tcp --dport 3030 -j ACCEPT
	#iptables -t nat -A PREROUTING -i $(AP_IN) -p tcp --dport 80 -j DNAT --to 0.0.0.0:3030
	#iptables -t nat -A PREROUTING -i $(AP_IN) -p tcp --dport 80 -j REDIRECT --to-port 3030

dns:
	dnsmasq -C dnsmasq.conf -x /var/run/dnsmasq-$(AP_IN).pid -8 $(PWD)/logs/dnsmasq.log -H $(PWD)/hosts --server 8.8.8.8

git:
	/usr/lib/git-core/git-daemon --listen=0.0.0.0 --export-all --verbose \
		--base-path=/mnt/Others/git/ --detach --reuseaddr --pid-file=/var/run/git-daemon-$(AP_IN).pid

samba:
	systemctl start smbd nmbd

squid:
	squid -f squid.conf

# trap quit HUP TERM

# set +e
ap:
	hostapd hostapd.conf
