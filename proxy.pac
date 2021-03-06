/* global isInNet, dnsResolve, myIpAddress, dnsDomainIs */
/* jshint strict:false */
function FindProxyForURL(url, host) {
  if (isInNet(dnsResolve(host), "10.0.0.0", "255.0.0.0") ||
      isInNet(dnsResolve(host), "172.16.0.0", "255.240.0.0") ||
      isInNet(dnsResolve(host), "192.168.0.0", "255.255.0.0") ||
      isInNet(dnsResolve(host), "173.37.0.0", "255.255.0.0") ||
      isInNet(dnsResolve(host), "127.0.0.0", "255.255.255.0") ||
      isInNet(dnsResolve(host), "192.168.20.1", "255.255.255.0") ||
      dnsDomainIs(host, ".lan") || dnsDomainIs(host, "localhost"))
    return "DIRECT";

  return "PROXY mtcfss.lan:3031; DIRECT";
}
