# Optional: your company's root certificate

If you are behind a corporate proxy that re-signs HTTPS (symptom while building the Jenkins image:
`PKIX path building failed` or `unable to find valid certification path`), copy your proxy's root
certificate here as `something.crt` (PEM format) and rebuild: `docker compose build jenkins`.
Files in this folder ending in `.crt` are trusted by Jenkins' Java. Nothing here is committed to Git.
