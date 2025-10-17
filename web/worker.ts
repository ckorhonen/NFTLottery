export default {
  async fetch(req: Request, env: any): Promise<Response> {
    const url = new URL(req.url)
    if (url.pathname === '/health') return new Response('ok')
    // Try static asset first
    const staticResp = await env.ASSETS.fetch(req)
    if (staticResp.status !== 404) return staticResp
    // Fallback to SPA index.html
    const indexReq = new Request(new URL('/index.html', url.origin), req)
    return env.ASSETS.fetch(indexReq)
  }
}
