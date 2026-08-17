---
name: security-audit
description: Audit the codebase for common security vulnerabilities (OWASP, secrets, auth, injection)
disable-model-invocation: true
argument-hint: "[file-or-directory-to-focus-on]"
---

# Security Audit

Scan the codebase for common security vulnerabilities. Focus on `$ARGUMENTS` if provided, otherwise audit the full project.

## Steps

1. **Secrets & credentials** - search for hardcoded secrets, API keys, tokens, passwords:
   - Grep for patterns: `API_KEY=`, `SECRET=`, `password`, `token`, bearer tokens, base64-encoded strings that look like keys
   - Check `.gitignore` covers `.env*`, credentials files, key files
   - Check no `.env` file is tracked in git: `git ls-files | grep -i env`

2. **Auth & access control** - review authentication and authorization:
   - Verify auth checks exist before sensitive operations
   - Check for missing auth middleware on routes/endpoints
   - Look for insecure session handling, missing CSRF protection
   - Check Firestore/database security rules if present

3. **Injection vulnerabilities** - check for:
   - SQL injection (unparameterized queries)
   - XSS (unescaped user input rendered as HTML, `dangerouslySetInnerHTML`, `innerHTML`)
   - Command injection (`exec`, `spawn` with unsanitized input)
   - Path traversal (user input in file paths)

4. **Webhook & API security** - if webhooks exist:
   - Verify signature validation (HMAC, etc.)
   - Check for replay attack protection
   - Verify input validation on all external-facing endpoints

5. **Dependencies** - run `npm audit` (if package.json exists) and flag high/critical vulnerabilities.

6. **Report** - output findings grouped by severity:

```
## CRITICAL (fix immediately)
- [description] - [file:line]

## HIGH
- ...

## MEDIUM
- ...

## LOW / INFO
- ...
```

If no issues found in a category, skip it. End with a one-line summary.

## Do NOT
- Modify any files - this is read-only
- Report false positives from vendored/generated files (node_modules, .next, dist)
- Flag env var USAGE (like `process.env.X`) as a leaked secret - only flag hardcoded values
