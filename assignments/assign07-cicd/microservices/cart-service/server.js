require('dotenv').config();
const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const client = require('prom-client');

const app = express();
const PORT = process.env.PORT || 3003;

// ---------------------------------------------------------------------------
// Middleware
// ---------------------------------------------------------------------------
app.use(helmet());
app.use(cors());
app.use(express.json());

// ---------------------------------------------------------------------------
// Structured JSON logging helper
// ---------------------------------------------------------------------------
function log(level, message, meta = {}) {
  const entry = {
    timestamp: new Date().toISOString(),
    level,
    service: 'cart-service',
    message,
    ...meta,
  };
  console.log(JSON.stringify(entry));
}

// ---------------------------------------------------------------------------
// Prometheus metrics
// ---------------------------------------------------------------------------
const register = new client.Registry();
client.collectDefaultMetrics({ register });

const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.01, 0.05, 0.1, 0.3, 0.5, 1, 2, 5],
  registers: [register],
});

const httpRequestTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register],
});

// Request duration tracking middleware
app.use((req, res, next) => {
  const end = httpRequestDuration.startTimer();
  res.on('finish', () => {
    const route = req.route ? req.route.path : req.path;
    const labels = {
      method: req.method,
      route,
      status_code: res.statusCode,
    };
    end(labels);
    httpRequestTotal.inc(labels);
  });
  next();
});

// ---------------------------------------------------------------------------
// In-memory cart store (Map of userId -> array of items)
// ---------------------------------------------------------------------------
const carts = new Map();

function getCart(userId) {
  if (!carts.has(userId)) {
    carts.set(userId, []);
  }
  return carts.get(userId);
}

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

// Health check
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', service: 'cart-service' });
});

// Prometheus metrics endpoint
app.get('/metrics', async (_req, res) => {
  try {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  } catch (err) {
    log('error', 'Failed to generate metrics', { error: err.message });
    res.status(500).end();
  }
});

// GET /api/cart/:userId - get the full cart for a user
app.get('/api/cart/:userId', (req, res) => {
  const { userId } = req.params;
  const items = getCart(userId);
  log('info', 'Cart retrieved', { userId, itemCount: items.length });
  res.json({ userId, items });
});

// POST /api/cart/:userId/items - add an item to the cart
app.post('/api/cart/:userId/items', (req, res) => {
  const { userId } = req.params;
  const { productId, name, price, quantity } = req.body;

  if (!productId || !name || price == null || quantity == null) {
    return res.status(400).json({
      error: 'Missing required fields: productId, name, price, quantity',
    });
  }

  const items = getCart(userId);

  // If the product already exists in the cart, increment the quantity
  const existing = items.find((item) => item.productId === productId);
  if (existing) {
    existing.quantity += quantity;
    log('info', 'Cart item quantity updated (add)', { userId, productId, newQuantity: existing.quantity });
    return res.json({ userId, items });
  }

  items.push({ productId, name, price: Number(price), quantity: Number(quantity) });
  log('info', 'Item added to cart', { userId, productId, name });
  res.status(201).json({ userId, items });
});

// PUT /api/cart/:userId/items/:productId - update item quantity
app.put('/api/cart/:userId/items/:productId', (req, res) => {
  const { userId, productId } = req.params;
  const { quantity } = req.body;

  if (quantity == null) {
    return res.status(400).json({ error: 'Missing required field: quantity' });
  }

  const items = getCart(userId);
  const item = items.find((i) => i.productId === productId);

  if (!item) {
    log('warn', 'Cart item not found for update', { userId, productId });
    return res.status(404).json({ error: 'Item not found in cart' });
  }

  item.quantity = Number(quantity);
  log('info', 'Cart item quantity updated', { userId, productId, quantity: item.quantity });
  res.json({ userId, items });
});

// DELETE /api/cart/:userId/items/:productId - remove an item from the cart
app.delete('/api/cart/:userId/items/:productId', (req, res) => {
  const { userId, productId } = req.params;
  const items = getCart(userId);
  const index = items.findIndex((i) => i.productId === productId);

  if (index === -1) {
    log('warn', 'Cart item not found for removal', { userId, productId });
    return res.status(404).json({ error: 'Item not found in cart' });
  }

  items.splice(index, 1);
  log('info', 'Item removed from cart', { userId, productId });
  res.json({ userId, items });
});

// DELETE /api/cart/:userId - clear the entire cart
app.delete('/api/cart/:userId', (req, res) => {
  const { userId } = req.params;
  carts.delete(userId);
  log('info', 'Cart cleared', { userId });
  res.json({ userId, items: [] });
});

// GET /api/cart/:userId/total - calculate the cart total
app.get('/api/cart/:userId/total', (req, res) => {
  const { userId } = req.params;
  const items = getCart(userId);

  const total = items.reduce((sum, item) => sum + item.price * item.quantity, 0);
  const itemCount = items.reduce((sum, item) => sum + item.quantity, 0);

  log('info', 'Cart total calculated', { userId, total, itemCount });
  res.json({ userId, total: Math.round(total * 100) / 100, itemCount });
});

// ---------------------------------------------------------------------------
// Global error handler
// ---------------------------------------------------------------------------
app.use((err, _req, res, _next) => {
  log('error', 'Unhandled error', { error: err.message, stack: err.stack });
  res.status(500).json({ error: 'Internal server error' });
});

// ---------------------------------------------------------------------------
// Start server
// ---------------------------------------------------------------------------
if (require.main === module) {
  app.listen(PORT, () => {
    log('info', `cart-service listening on port ${PORT}`);
  });
}

module.exports = app;
