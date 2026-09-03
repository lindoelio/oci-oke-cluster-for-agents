// TCP/HTTP proxy that exposes Chrome's loopback-only CDP endpoint to the
// cluster, rewriting the Host header so DevTools accepts remote clients.
const http = require("http");
const net = require("net");
const TARGET_HOST = process.env.CDP_TARGET_HOST || "127.0.0.1";
const TARGET_PORT = parseInt(process.env.CDP_TARGET_PORT || "9223", 10);
const LISTEN_PORT = parseInt(process.env.CDP_LISTEN_PORT || "9222", 10);

function rewrite(headers) {
  const h = { ...headers, host: `${TARGET_HOST}:${TARGET_PORT}` };
  delete h.origin;
  return h;
}

const srv = http.createServer((req, res) => {
  const preq = http.request(
    { host: TARGET_HOST, port: TARGET_PORT, path: req.url, method: req.method, headers: rewrite(req.headers) },
    (pres) => {
      // Rewrite the loopback target out of /json* payloads so clients get a
      // webSocketDebuggerUrl pointing at the proxy, not at chrome's loopback.
      const isJson = (pres.headers["content-type"] || "").includes("json");
      if (req.url.startsWith("/json") && isJson && !pres.headers["content-encoding"]) {
        const chunks = [];
        pres.on("data", (c) => chunks.push(c));
        pres.on("end", () => {
          const body = Buffer.concat(chunks)
            .toString("utf8")
            .split(`${TARGET_HOST}:${TARGET_PORT}`)
            .join(req.headers.host || `${TARGET_HOST}:${TARGET_PORT}`);
          const headers = { ...pres.headers, "content-length": String(Buffer.byteLength(body)) };
          res.writeHead(pres.statusCode, headers);
          res.end(body);
        });
      } else {
        res.writeHead(pres.statusCode, pres.headers);
        pres.pipe(res);
      }
    },
  );
  preq.on("error", () => res.end());
  req.pipe(preq);
});

srv.on("upgrade", (req, socket, head) => {
  const conn = net.connect(TARGET_PORT, TARGET_HOST, () => {
    const headerBlock = Object.entries(rewrite(req.headers))
      .map(([k, v]) => `${k}: ${v}`)
      .join("\r\n");
    conn.write(`${req.method} ${req.url} HTTP/1.1\r\n${headerBlock}\r\n\r\n`);
  });
  socket.pipe(conn);
  conn.pipe(socket);
  conn.on("error", () => socket.destroy());
  socket.on("error", () => conn.destroy());
});

srv.listen(LISTEN_PORT, "0.0.0.0", () => console.log(`cdp proxy up on ${LISTEN_PORT}`));
