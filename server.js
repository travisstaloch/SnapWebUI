import { serve } from "bun";
import { join } from "path";

serve({
  port: 8000,
  fetch(request) {
    const url = new URL(request.url);
    console.log("request ", url.href)
    let filePath = join(process.cwd(), "public", url.pathname === "/" ? "index.html" : url.pathname);
    return new Response(Bun.file(filePath));
  },
});

console.log("Bun server listening on http://localhost:8000");