export interface Env {
  AI: Ai;
  AUTH_TOKEN?: string;
}

const MAX_BODY_BYTES = 25 * 1024 * 1024; // 25 MB cap

function timingSafeEqualStrings(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const bufA = enc.encode(a);
  const bufB = enc.encode(b);
  if (bufA.byteLength !== bufB.byteLength) {
    return false;
  }
  return crypto.subtle.timingSafeEqual(bufA, bufB);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    // Only accept POST requests
    if (request.method !== "POST") {
      return new Response("Method Not Allowed", {
        status: 405,
        headers: { Allow: "POST" },
      });
    }

    // Health / connection test check
    const url = new URL(request.url);
    if (url.pathname === "/health" || url.pathname === "/ping") {
      return Response.json({ status: "ok" });
    }

    // Bearer token authentication
    const authHeader = request.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response("Unauthorized", { status: 401 });
    }

    const token = authHeader.substring(7).trim();
    const expectedToken = env.AUTH_TOKEN ? env.AUTH_TOKEN.trim() : "";

    if (!expectedToken || !timingSafeEqualStrings(token, expectedToken)) {
      return new Response("Unauthorized", { status: 401 });
    }

    // Check payload size
    const contentLength = request.headers.get("Content-Length");
    if (contentLength && parseInt(contentLength, 10) > MAX_BODY_BYTES) {
      return new Response("Payload Too Large", { status: 413 });
    }

    let audioBytes: Uint8Array;

    try {
      const contentType = request.headers.get("Content-Type") || "";

      if (contentType.includes("multipart/form-data")) {
        const formData = await request.formData();
        const file = formData.get("file") || formData.get("audio");
        if (!file || typeof file === "string") {
          return new Response("Missing audio file in form data", { status: 400 });
        }
        const arrayBuffer = await (file as Blob).arrayBuffer();
        if (arrayBuffer.byteLength > MAX_BODY_BYTES) {
          return new Response("Payload Too Large", { status: 413 });
        }
        audioBytes = new Uint8Array(arrayBuffer);
      } else {
        // Raw audio body
        const arrayBuffer = await request.arrayBuffer();
        if (arrayBuffer.byteLength > MAX_BODY_BYTES) {
          return new Response("Payload Too Large", { status: 413 });
        }
        audioBytes = new Uint8Array(arrayBuffer);
      }

      if (audioBytes.byteLength === 0) {
        return new Response("Empty audio payload", { status: 400 });
      }
    } catch (err) {
      console.error("Failed to read audio input:", err);
      return new Response("Invalid request body", { status: 400 });
    }

    // Call Cloudflare Workers AI Whisper model
    try {
      let binary = "";
      const chunkSize = 8192;
      for (let i = 0; i < audioBytes.length; i += chunkSize) {
        const chunk = audioBytes.subarray(i, i + chunkSize);
        binary += String.fromCharCode.apply(null, chunk as unknown as number[]);
      }
      const base64Audio = btoa(binary);

      const response = await env.AI.run("@cf/openai/whisper-large-v3-turbo", {
        audio: base64Audio,
      });

      const text = (response as { text?: string }).text ?? "";
      return Response.json({ text: text.trim() });
    } catch (err) {
      console.error("Workers AI Whisper inference error:", err);
      return new Response("Internal Server Error", { status: 500 });
    }
  },
};
