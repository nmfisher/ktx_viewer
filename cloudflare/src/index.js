export default {
  async fetch(request, env) {

    const corsHeaders = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET,HEAD,POST,OPTIONS",
      "Access-Control-Max-Age": "86400",
    };

    async function handleRequest(request) {
            
      let assetResponse = await env.ASSETS.fetch(request);
      
      let response = new Response(assetResponse.body);
      response.headers.set("Cross-Origin-Opener-Policy", "same-origin");
      response.headers.set("Cross-Origin-Embedder-Policy", "require-corp");

      if(request.url.endsWith("wasm")) {
        response.headers.set('Content-Type', "application/wasm");
      } else if(request.url.endsWith(".js") || request.url.endsWith(".mjs")) {
        response.headers.set('Content-Type', "text/javascript");
      }
      console.log("Set COOP header");
      return response;
    }

    async function handleOptions(request) {
      if (
        request.headers.get("Origin") !== null &&
        request.headers.get("Access-Control-Request-Method") !== null &&
        request.headers.get("Access-Control-Request-Headers") !== null
      ) {
        // Handle CORS preflight requests.
        return new Response(null, {
          headers: {
            ...corsHeaders,
            "Access-Control-Allow-Headers": request.headers.get(
              "Access-Control-Request-Headers",
            ),
            "Cross-Origin-Opener-Policy":"same-origin",
            "Cross-Origin-Embedder-Policy": "require-corp"
          },
        });
      } else {
        // Handle standard OPTIONS request.
        return new Response(null, {
          headers: {
            Allow: "GET, HEAD, POST, OPTIONS",
          },
        });
      }
    }
    
    if (request.method === "OPTIONS") {
      return handleOptions(request);
    } 
    return handleRequest(request);
    
  },
};
