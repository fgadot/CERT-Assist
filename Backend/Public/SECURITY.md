# CERT-Assist Security Overview

## TL;DR - Can Someone Take Down Your Site?

**Short answer:** Partially, yes - but you can significantly harden it.

**Current status:**
- ✅ **Good protection** against casual attacks (rate limiting, SSL, security headers)
- ⚠️ **Vulnerable** to determined DDoS attacks
- ⚠️ **No resource limits** on Docker container
- ⚠️ **No firewall** configured yet

**Recommendation:** Implement the hardening steps in DEPLOYMENT.md

---

## Threat Model

### Cloud Server (cert.w6fgc.com)

**Exposed to:** Anyone on the internet

**Attack Vectors:**

1. **DDoS (Distributed Denial of Service)**
   - **Current protection:** Nginx rate limiting (10 req/sec)
   - **Vulnerability:** Large botnet could still overwhelm
   - **Mitigation:** Add CloudFlare, increase rate limits, add firewall

2. **Resource Exhaustion**
   - **Current protection:** None
   - **Vulnerability:** Attacker could fill memory/CPU
   - **Mitigation:** Add Docker resource limits (see DEPLOYMENT.md)

3. **WebSocket Flooding**
   - **Current protection:** 5 req/sec limit
   - **Vulnerability:** Could hold many connections open
   - **Mitigation:** Connection timeouts, max concurrent connections

4. **Data Injection/Manipulation**
   - **Current protection:** None (no authentication yet)
   - **Vulnerability:** Anyone can submit fake reports
   - **Mitigation:** Add authentication, API keys, input validation

5. **Port Scanning/Exploitation**
   - **Current protection:** None
   - **Vulnerability:** Port 8080 exposed to internet
   - **Mitigation:** Bind to localhost only, enable firewall

### Local Laptop Deployment

**Exposed to:** Only local network (WiFi/Ethernet)

**Attack Vectors:**

1. **Malicious Team Member**
   - **Vulnerability:** No authentication, anyone on network can access
   - **Mitigation:** Add PIN code or credentials

2. **WiFi Eavesdropping**
   - **Vulnerability:** HTTP traffic not encrypted
   - **Mitigation:** Use WPA3 WiFi encryption, add HTTPS

3. **Physical Access**
   - **Vulnerability:** Laptop could be stolen/damaged
   - **Mitigation:** Encrypt hard drive, backup data

**Generally safer** because not exposed to internet, but still needs authentication.

---

## Security Comparison

| Feature | Cloud Server | Local Laptop |
|---------|-------------|--------------|
| **Exposure** | ❌ Internet-facing | ✅ Local network only |
| **HTTPS/SSL** | ✅ Yes (Let's Encrypt) | ⚠️ No (HTTP) |
| **Rate Limiting** | ✅ Yes (nginx) | ❌ No |
| **Firewall** | ⚠️ Recommended (not yet) | ✅ Isolated network |
| **Authentication** | ❌ None yet | ❌ None yet |
| **DDoS Risk** | ⚠️ High | ✅ Low (local only) |
| **Data Privacy** | ⚠️ On internet | ✅ Physically controlled |
| **Availability** | ✅ 24/7 online | ⚠️ Only when laptop on |

**Conclusion:**
- **Cloud = More convenient, more exposed**
- **Local = More private, less convenient**
- **Both need authentication eventually**

---

## Hardening Priorities

### Critical (Do ASAP)

1. **Docker resource limits** - Prevents container from consuming all server resources
   ```yaml
   deploy:
     resources:
       limits:
         cpus: '2.0'
         memory: 1G
   ```

2. **Bind to localhost only** - Prevent direct internet access to Docker
   ```yaml
   ports:
     - "127.0.0.1:8080:8080"  # Only nginx can access
   ```

3. **Enable firewall (ufw)** - Block all ports except 80, 443, 22
   ```bash
   sudo ufw enable
   sudo ufw allow 80,443,22/tcp
   ```

### High Priority (Within 1-2 weeks)

4. **Fail2ban** - Auto-block IPs after suspicious activity
5. **Authentication** - PIN code or credentials for dashboard access
6. **Input validation** - Sanitize all user inputs
7. **Database persistence** - Currently in-memory (data lost on restart)

### Medium Priority (Before public release)

8. **CloudFlare or DDoS protection** - If site becomes widely used
9. **API keys for county access** - Secure county-level dashboard
10. **Audit logging** - Track who did what, when
11. **Backup strategy** - Regular exports of incident data

### Low Priority (Nice to have)

12. **Monitoring/alerting** - Prometheus + Grafana
13. **Penetration testing** - Hire security researcher
14. **Bug bounty program** - If app becomes popular

---

## For CERT Use Case

**Your use case is INTERNAL TEAM COORDINATION, not public-facing service.**

This changes the threat model significantly:

✅ **Expected users:** ~10-50 CERT team members per deployment  
✅ **Usage pattern:** Only during emergencies (hours to days)  
✅ **Trust level:** Team members are vetted volunteers  
✅ **Network:** Often local/isolated during disasters

**This means:**
- Authentication can be simple (shared PIN, not full OAuth)
- Rate limiting can be relaxed for known IPs
- Availability more important than perfect security
- Local deployment often more appropriate than cloud

**Recommendation:**
1. **For demos/training:** Use cloud server (cert.w6fgc.com) - convenient
2. **For real incidents:** Use local laptop - more resilient, more private
3. **Add basic authentication** - Prevents accidental access, not military-grade security
4. **Focus on data integrity** - Immutable logs, timestamps, audit trail

---

## Specific Answers to Your Questions

### "Can someone take the site down if it's installed on Docker?"

**Cloud server (cert.w6fgc.com):**
- **Yes, somewhat.** A determined attacker with a botnet could overwhelm your nginx rate limiting and exhaust resources.
- **Mitigation:** Implement Docker resource limits, enable firewall, add CloudFlare if needed.
- **Risk level:** LOW for a small CERT project (nobody knows about it), MEDIUM if publicized.

**Local laptop:**
- **No, not from the internet.** Only people on the local network could interfere.
- **Physical security matters more** - protect the laptop, use WiFi password.
- **Risk level:** VERY LOW (isolated network, trusted users).

### "Is it possible to secure it properly?"

**Yes, absolutely!** Your current setup is a good foundation. Add:
1. Docker resource limits (10 minutes to implement)
2. Firewall rules (5 minutes)
3. Authentication (1-2 days development)
4. Input validation (ongoing as you add features)

**You don't need Fort Knox.** This is for CERT teams, not banking. Reasonable security is:
- Stop casual vandals: ✅ Rate limiting
- Stop script kiddies: ✅ Firewall + resource limits
- Stop insider threats: ⚠️ Add authentication
- Stop nation-state actors: ❌ Out of scope (not needed)

### "Are we good like that?"

**For a demo/prototype: YES, you're fine.**

**For production CERT use:**
- ✅ Cloud deployment is demo-ready
- ⚠️ Add resource limits before heavy use
- ⚠️ Add authentication before deployment to real teams
- ✅ Local deployment is already quite secure (network isolation)

**Next steps:**
1. Update docker-compose.yml with resource limits (do this now)
2. Enable firewall on Ubuntu server (do this now)
3. Plan authentication system (do this before real deployment)

---

## Recommended Reading

- [OWASP Top 10](https://owasp.org/www-project-top-ten/) - Common web vulnerabilities
- [Docker Security Best Practices](https://docs.docker.com/engine/security/)
- [Nginx Security Tips](https://nginx.org/en/docs/http/ngx_http_limit_req_module.html)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework) - For government/emergency services

---

## Contact for Security Issues

Frank Gadot - W6FGC

**Found a vulnerability?** Email privately, don't post publicly until fixed.
