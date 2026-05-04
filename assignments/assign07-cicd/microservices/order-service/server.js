const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const { v4: uuidv4 } = require('uuid');
const promClient = require('prom-client');
require('dotenv').config();

// ============================================================
// Configuration
// ============================================================
const PORT = process.env.PORT || 3005;
const SNS_TOPIC_ARN = process.env.SNS_TOPIC_ARN || 'arn:aws:sns:us-east-1:000000000000:order-events';

// ============================================================
// Prometheus Metrics
// ============================================================
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register });

const httpRequestDurationHistogram = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.01, 0.05, 0.1, 0.3, 0.5, 1, 2, 5],
  registers: [register],
});

const orderCounter = new promClient.Counter({
  name: 'orders_total',
  help: 'Total number of orders by status',
  labelNames: ['status'],
  registers: [register],
});

// ============================================================
// Structured Logger
// ============================================================
function log(level, message, meta = {}) {
  const entry = {
    timestamp: new Date().toISOString(),
    level,
    service: 'order-service',
    message,
    ...meta,
  };
  console.log(JSON.stringify(entry));
}

// ============================================================
// In-Memory Data Store
// ============================================================
const orders = [];

// ============================================================
// Express App Setup
// ============================================================
const app = express();

app.use(helmet());
app.use(cors());
app.use(express.json());

// ============================================================
// Request Duration Middleware
// ============================================================
app.use((req, res, next) => {
  const end = httpRequestDurationHistogram.startTimer();
  res.on('finish', () => {
    end({
      method: req.method,
      route: req.route ? req.route.path : req.path,
      status_code: res.statusCode,
    });
  });
  next();
});

// ============================================================
// Health Check
// ============================================================
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'order-service' });
});

// ============================================================
// Prometheus Metrics Endpoint
// ============================================================
app.get('/metrics', async (req, res) => {
  try {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  } catch (err) {
    log('error', 'Failed to generate metrics', { error: err.message });
    res.status(500).end();
  }
});

// ============================================================
// Valid Order Statuses
// ============================================================
const VALID_STATUSES = [
  'pending',
  'confirmed',
  'processing',
  'shipped',
  'delivered',
  'cancelled',
];

// ============================================================
// Helper: Publish Order Event (SNS stub)
// ============================================================
function publishOrderEvent(eventType, order) {
  log('info', `Order event would be published to SNS`, {
    snsTopicArn: SNS_TOPIC_ARN,
    eventType,
    orderId: order.orderId,
    status: order.status,
  });
}

// ============================================================
// POST /api/orders - Create a new order
// ============================================================
app.post('/api/orders', (req, res) => {
  try {
    const { userId, items, shippingAddress } = req.body;

    // Validate required fields
    if (!userId) {
      return res.status(400).json({ error: 'userId is required' });
    }
    if (!items || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ error: 'items must be a non-empty array' });
    }
    if (!shippingAddress) {
      return res.status(400).json({ error: 'shippingAddress is required' });
    }

    // Validate each item
    for (const item of items) {
      if (!item.productId || !item.name || item.price == null || item.quantity == null) {
        return res.status(400).json({
          error: 'Each item must have productId, name, price, and quantity',
        });
      }
      if (typeof item.price !== 'number' || item.price < 0) {
        return res.status(400).json({ error: 'Item price must be a non-negative number' });
      }
      if (!Number.isInteger(item.quantity) || item.quantity < 1) {
        return res.status(400).json({ error: 'Item quantity must be a positive integer' });
      }
    }

    // Calculate total from items
    const total = items.reduce((sum, item) => sum + item.price * item.quantity, 0);
    const totalRounded = Math.round(total * 100) / 100;

    // Build order object
    const order = {
      orderId: uuidv4(),
      userId,
      items,
      shippingAddress,
      total: totalRounded,
      status: 'pending',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    };

    orders.push(order);

    // Increment metrics
    orderCounter.inc({ status: 'pending' });

    log('info', 'Order created', { orderId: order.orderId, userId, total: totalRounded });

    // Publish event to SNS (stubbed)
    publishOrderEvent('ORDER_CREATED', order);

    res.status(201).json(order);
  } catch (err) {
    log('error', 'Failed to create order', { error: err.message });
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// GET /api/orders/:orderId - Get order by ID
// ============================================================
app.get('/api/orders/:orderId', (req, res) => {
  try {
    const { orderId } = req.params;
    const order = orders.find((o) => o.orderId === orderId);

    if (!order) {
      return res.status(404).json({ error: 'Order not found' });
    }

    log('info', 'Order retrieved', { orderId });
    res.json(order);
  } catch (err) {
    log('error', 'Failed to retrieve order', { error: err.message });
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// GET /api/orders/user/:userId - Get all orders for a user
// ============================================================
app.get('/api/orders/user/:userId', (req, res) => {
  try {
    const { userId } = req.params;
    const userOrders = orders.filter((o) => o.userId === userId);

    log('info', 'User orders retrieved', { userId, count: userOrders.length });
    res.json(userOrders);
  } catch (err) {
    log('error', 'Failed to retrieve user orders', { error: err.message });
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// PUT /api/orders/:orderId/status - Update order status
// ============================================================
app.put('/api/orders/:orderId/status', (req, res) => {
  try {
    const { orderId } = req.params;
    const { status } = req.body;

    if (!status) {
      return res.status(400).json({ error: 'status is required' });
    }
    if (!VALID_STATUSES.includes(status)) {
      return res.status(400).json({
        error: `Invalid status. Must be one of: ${VALID_STATUSES.join(', ')}`,
      });
    }

    const order = orders.find((o) => o.orderId === orderId);
    if (!order) {
      return res.status(404).json({ error: 'Order not found' });
    }

    const previousStatus = order.status;
    order.status = status;
    order.updatedAt = new Date().toISOString();

    // Increment metrics
    orderCounter.inc({ status });

    log('info', 'Order status updated', { orderId, previousStatus, newStatus: status });

    // Publish event to SNS (stubbed)
    publishOrderEvent('ORDER_STATUS_UPDATED', order);

    res.json(order);
  } catch (err) {
    log('error', 'Failed to update order status', { error: err.message });
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// POST /api/orders/:orderId/cancel - Cancel an order
// ============================================================
app.post('/api/orders/:orderId/cancel', (req, res) => {
  try {
    const { orderId } = req.params;
    const order = orders.find((o) => o.orderId === orderId);

    if (!order) {
      return res.status(404).json({ error: 'Order not found' });
    }

    // Only allow cancellation if status is pending or confirmed
    if (order.status !== 'pending' && order.status !== 'confirmed') {
      return res.status(400).json({
        error: `Cannot cancel order with status "${order.status}". Only pending or confirmed orders can be cancelled.`,
      });
    }

    const previousStatus = order.status;
    order.status = 'cancelled';
    order.updatedAt = new Date().toISOString();

    // Increment metrics
    orderCounter.inc({ status: 'cancelled' });

    log('info', 'Order cancelled', { orderId, previousStatus });

    // Publish event to SNS (stubbed)
    publishOrderEvent('ORDER_CANCELLED', order);

    res.json(order);
  } catch (err) {
    log('error', 'Failed to cancel order', { error: err.message });
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ============================================================
// Start Server
// ============================================================
app.listen(PORT, () => {
  log('info', `Order service started`, { port: PORT, snsTopicArn: SNS_TOPIC_ARN });
});

module.exports = app;
