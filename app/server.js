const http = require('http');

const PORT = process.env.PORT || 3000;

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ status: 'healthy', version: process.env.APP_VERSION || '1.0.0' }));
  }
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ message: 'Hello from Simple CI/CD Pipeline!', timestamp: new Date().toISOString() }));
});

server.listen(PORT, () => console.log(`Server running on port ${PORT}`));
process.on('SIGTERM', () => { server.close(() => process.exit(0)); });
