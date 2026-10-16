# Orca Whisper Cloudflare Worker

A lightweight Cloudflare Worker that accepts audio recordings (AAC M4A or WAV) and transcribes them using Cloudflare Workers AI (`@cf/openai/whisper-large-v3-turbo`).

## Prerequisites

- [Node.js](https://nodejs.org) (v18+)
- A free [Cloudflare Account](https://dash.cloudflare.com)

## Quick Deployment

1. **Install dependencies**:
   ```bash
   cd worker
   npm install
   ```

2. **Authenticate with Cloudflare**:
   ```bash
   npx wrangler login
   ```

3. **Deploy the Worker**:
   ```bash
   npx wrangler deploy
   ```
   Note the deployment URL output (e.g. `https://orca-whisper-worker.<your-subdomain>.workers.dev`).

4. **Set your Secret Auth Token**:
   Generate a long, random secret token:
   ```bash
   openssl rand -hex 32
   ```
   Save it to your worker secrets:
   ```bash
   npx wrangler secret put AUTH_TOKEN
   ```
   When prompted, paste your generated token.

## Testing with cURL

### 1. Test Unauthorized Access (Should return 401)
```bash
curl -i -X POST "https://<your-worker-url>/"
```

### 2. Test Health Endpoint (Should return 200 `{"status":"ok"}`)
```bash
curl -i -X POST "https://<your-worker-url>/health"
```

### 3. Test Audio Transcription (Should return 200 `{"text":"..."}`)
```bash
curl -X POST "https://<your-worker-url>/" \
  -H "Authorization: Bearer <your-secret-token>" \
  -H "Content-Type: audio/m4a" \
  --data-binary "@test.m4a"
```

## Client App Configuration

In the Orca Whisper macOS app:
1. Open the app and navigate to **Settings > Transcription**.
2. Set **Endpoint URL** to `https://<your-worker-url>/`.
3. Set **Bearer Token** to your secret token.
4. Click **Test Worker Connection** on the Overview screen to verify.
