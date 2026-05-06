const API_BASE = process.env.NEXT_PUBLIC_API_URL || '';

export interface Product {
  id: number;
  name: string;
  price: number;
  description: string;
  category: string;
  stock: number;
}

export interface CartItem {
  productId: number;
  name: string;
  price: number;
  quantity: number;
}

export interface User {
  id: number;
  email: string;
  name: string;
}

export interface Order {
  id: number;
  userId: number;
  items: CartItem[];
  total: number;
  status: string;
  createdAt: string;
}

// Products API
export async function getProducts(): Promise<Product[]> {
  const res = await fetch(`${API_BASE}/api/products`);
  const data = await res.json();
  return data.data || data;
}

export async function getProduct(id: number): Promise<Product> {
  const res = await fetch(`${API_BASE}/api/products/${id}`);
  return res.json();
}

// Cart API
export async function getCart(userId: string): Promise<CartItem[]> {
  const res = await fetch(`${API_BASE}/api/cart/${userId}`);
  const data = await res.json();
  return data.items || [];
}

export async function addToCart(userId: string, productId: number, quantity: number = 1): Promise<void> {
  await fetch(`${API_BASE}/api/cart/${userId}/items`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ productId, quantity }),
  });
}

export async function removeFromCart(userId: string, productId: number): Promise<void> {
  await fetch(`${API_BASE}/api/cart/${userId}/items/${productId}`, {
    method: 'DELETE',
  });
}

export async function clearCart(userId: string): Promise<void> {
  await fetch(`${API_BASE}/api/cart/${userId}`, {
    method: 'DELETE',
  });
}

// Users API
export async function getUsers(): Promise<User[]> {
  const res = await fetch(`${API_BASE}/api/users`);
  return res.json();
}

export async function createUser(email: string, name: string, password: string): Promise<User> {
  const res = await fetch(`${API_BASE}/api/users`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, name, password }),
  });
  return res.json();
}

// Orders API
export async function getOrders(userId?: number): Promise<Order[]> {
  const url = userId ? `${API_BASE}/api/orders?userId=${userId}` : `${API_BASE}/api/orders`;
  const res = await fetch(url);
  const data = await res.json();
  return data.data || data;
}

export async function createOrder(userId: number, items: CartItem[]): Promise<Order> {
  const res = await fetch(`${API_BASE}/api/orders`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ userId, items }),
  });
  return res.json();
}

// Payments API
export async function processPayment(orderId: number, amount: number, method: string): Promise<any> {
  const res = await fetch(`${API_BASE}/api/payments`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ orderId, amount, method }),
  });
  return res.json();
}
