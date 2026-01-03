Client (inside LAN)
   |
   |  (DNS: pihole.home.fedoteh.com.ar -> 192.168.86.10)
   v
+------------------------------+
| Gateway (home-gw)            |   (VIP 192.168.86.10, listeners :80/:443)
+------------------------------+
   |
   |  matches hostname/path
   v
+------------------------------+
| HTTPRoute (gateway ns)       |
|  - hostnames: pihole....     |
|  - backendRef -> Service     |
+------------------------------+
   |
   |  cross-namespace backend reference allowed by
   v
+------------------------------+
| ReferenceGrant (apps ns)     |
|  allows: HTTPRoute(gateway)  |
|  to reference: Service(apps) |
+------------------------------+
   |
   |  backendRef
   v
+------------------------------+
| Service: pihole-web (apps)   |
|  type: ClusterIP             |
|  selector: app=pihole,...    |
|  ports: 80->targetPort:http  |
|         443->targetPort:https|
+------------------------------+
   |
   |  selector resolves to a dynamic set of endpoints
   |  (controller materializes this via EndpointSlice)
   v
+------------------------------+
| EndpointSlice(s) (apps)      |   discovery.k8s.io/v1
|  - owned by: Service         |
|  - endpoints: Pod IPs        |
|    * 10.244.1.174:80,443     |
|  - ready/serving conditions  |
+------------------------------+
   |
   |  actual traffic goes to selected endpoint(s)
   v
+------------------------------+
| Pod: pihole-... (apps)       |
|  IP: 10.244.1.174 (pi-003)   |
|  containerPorts: 80/443      |
+------------------------------+
   ^
   |
   |  created/maintained by
+------------------------------+
| Deployment -> ReplicaSet     |
|  ensures desired pod count   |
+------------------------------+

Thank ChatGPT 5.2 for this diagram