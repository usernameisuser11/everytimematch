const http = require('node:http');
const serveHandler = require('serve-handler');
const webpush = require('web-push');

const port = Number(process.env.PORT || 8080);
const host = '0.0.0.0';

const server = http.createServer((req, res) => {
  serveHandler(req, res, { public: process.cwd() }).catch(error => {
    console.error('Request failed:', error.message);
    res.statusCode = 500;
    res.end('Internal Server Error');
  });
});

server.listen(port, host, () => {
  console.log('Everytime Match ready on port', port);
});
