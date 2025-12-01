const http = require('http');
const url = require('url');

exports.handler = async (event) => {
    console.log('Event:', JSON.stringify(event));
    
    const targetUrl = process.env.TARGET_URL || 'http://host.docker.internal:8080';
    
    // Get the actual path from the event
    const path = event.path || event.rawPath || '/';
    
    // Build query string if parameters exist
    const queryString = event.queryStringParameters 
        ? '?' + new URLSearchParams(event.queryStringParameters).toString() 
        : '';
    
    const fullUrl = `${targetUrl}${path}${queryString}`;
    console.log('Proxying to:', fullUrl);
    
    return new Promise((resolve, reject) => {
        const parsedUrl = url.parse(fullUrl);
        
        const options = {
            hostname: parsedUrl.hostname,
            port: parsedUrl.port || 80,
            path: parsedUrl.path,
            method: event.httpMethod || 'GET',
            headers: event.headers || {}
        };
        
        const req = http.request(options, (res) => {
            let data = '';
            
            res.on('data', chunk => {
                data += chunk;
            });
            
            res.on('end', () => {
                resolve({
                    statusCode: res.statusCode,
                    headers: {
                        'Content-Type': 'application/json',
                        'Access-Control-Allow-Origin': '*'
                    },
                    body: data
                });
            });
        });
        
        req.on('error', (error) => {
            console.error('Proxy error:', error);
            resolve({
                statusCode: 502,
                body: JSON.stringify({ error: 'Bad Gateway', details: error.message })
            });
        });
        
        // Send body if it exists (for POST/PUT requests)
        if (event.body) {
            req.write(event.body);
        }
        
        req.end();
    });
};