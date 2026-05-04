const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const promClient = require('prom-client');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3002;

// ---------------------------------------------------------------------------
// Prometheus Metrics
// ---------------------------------------------------------------------------
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });

const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.01, 0.05, 0.1, 0.3, 0.5, 1, 2, 5],
  registers: [register]
});

const httpRequestTotal = new promClient.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register]
});

// ---------------------------------------------------------------------------
// Middleware
// ---------------------------------------------------------------------------
app.use(helmet());
app.use(cors());
app.use(express.json());

// Structured JSON logging
app.use((req, res, next) => {
  const start = Date.now();
  const originalEnd = res.end;

  res.end = function (...args) {
    const duration = Date.now() - start;
    const logEntry = {
      timestamp: new Date().toISOString(),
      service: 'product-service',
      method: req.method,
      path: req.originalUrl,
      statusCode: res.statusCode,
      durationMs: duration,
      userAgent: req.get('user-agent') || 'unknown'
    };
    console.log(JSON.stringify(logEntry));

    // Record Prometheus metrics
    const route = req.route ? req.route.path : req.originalUrl;
    httpRequestDuration.observe(
      { method: req.method, route, status_code: res.statusCode },
      duration / 1000
    );
    httpRequestTotal.inc({
      method: req.method,
      route,
      status_code: res.statusCode
    });

    originalEnd.apply(res, args);
  };

  next();
});

// ---------------------------------------------------------------------------
// In-Memory Sample Products
// ---------------------------------------------------------------------------
let products = [
  {
    id: 1,
    name: 'Laptop',
    price: 999.99,
    description: 'High-performance laptop with 16GB RAM and 512GB SSD',
    category: 'electronics',
    stock: 50
  },
  {
    id: 2,
    name: 'Phone',
    price: 699.99,
    description: 'Latest smartphone with OLED display and 128GB storage',
    category: 'electronics',
    stock: 120
  },
  {
    id: 3,
    name: 'Headphones',
    price: 199.99,
    description: 'Wireless noise-cancelling headphones with 30-hour battery',
    category: 'accessories',
    stock: 200
  },
  {
    id: 4,
    name: 'Keyboard',
    price: 149.99,
    description: 'Mechanical keyboard with RGB lighting and Cherry MX switches',
    category: 'accessories',
    stock: 75
  },
  {
    id: 5,
    name: 'Monitor',
    price: 449.99,
    description: '27-inch 4K IPS monitor with HDR support',
    category: 'electronics',
    stock: 30
  }
];

let nextId = 6;

// ---------------------------------------------------------------------------
// Health & Metrics Routes
// ---------------------------------------------------------------------------
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'product-service' });
});

app.get('/metrics', async (req, res) => {
  try {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  } catch (err) {
    res.status(500).json({ error: 'Failed to collect metrics' });
  }
});

// ---------------------------------------------------------------------------
// Product Routes
// ---------------------------------------------------------------------------

// GET /api/products - List all products
app.get('/api/products', (req, res) => {
  res.json({
    success: true,
    count: products.length,
    data: products
  });
});

// GET /api/products/category/:category - Filter by category
// NOTE: This route must be defined BEFORE /api/products/:id so that
// "category" is not interpreted as a product ID.
app.get('/api/products/category/:category', (req, res) => {
  const { category } = req.params;
  const filtered = products.filter(
    (p) => p.category.toLowerCase() === category.toLowerCase()
  );

  res.json({
    success: true,
    count: filtered.length,
    data: filtered
  });
});

// GET /api/products/:id - Get product by ID
app.get('/api/products/:id', (req, res) => {
  const id = parseInt(req.params.id, 10);
  const product = products.find((p) => p.id === id);

  if (!product) {
    return res.status(404).json({
      success: false,
      error: `Product with id ${id} not found`
    });
  }

  res.json({ success: true, data: product });
});

// POST /api/products - Create a new product
app.post('/api/products', (req, res) => {
  const { name, price, description, category, stock } = req.body;

  if (!name || price === undefined) {
    return res.status(400).json({
      success: false,
      error: 'Name and price are required'
    });
  }

  const newProduct = {
    id: nextId++,
    name,
    price: parseFloat(price),
    description: description || '',
    category: category || 'uncategorized',
    stock: stock !== undefined ? parseInt(stock, 10) : 0
  };

  products.push(newProduct);

  res.status(201).json({ success: true, data: newProduct });
});

// PUT /api/products/:id - Update a product
app.put('/api/products/:id', (req, res) => {
  const id = parseInt(req.params.id, 10);
  const index = products.findIndex((p) => p.id === id);

  if (index === -1) {
    return res.status(404).json({
      success: false,
      error: `Product with id ${id} not found`
    });
  }

  const { name, price, description, category, stock } = req.body;

  products[index] = {
    ...products[index],
    ...(name !== undefined && { name }),
    ...(price !== undefined && { price: parseFloat(price) }),
    ...(description !== undefined && { description }),
    ...(category !== undefined && { category }),
    ...(stock !== undefined && { stock: parseInt(stock, 10) })
  };

  res.json({ success: true, data: products[index] });
});

// DELETE /api/products/:id - Delete a product
app.delete('/api/products/:id', (req, res) => {
  const id = parseInt(req.params.id, 10);
  const index = products.findIndex((p) => p.id === id);

  if (index === -1) {
    return res.status(404).json({
      success: false,
      error: `Product with id ${id} not found`
    });
  }

  const deleted = products.splice(index, 1)[0];

  res.json({ success: true, data: deleted });
});

// ---------------------------------------------------------------------------
// Start Server
// ---------------------------------------------------------------------------
app.listen(PORT, () => {
  console.log(
    JSON.stringify({
      timestamp: new Date().toISOString(),
      service: 'product-service',
      message: `Product service running on port ${PORT}`,
      port: PORT
    })
  );
});

module.exports = app;
